import AVFoundation
import Foundation
import Combine

// MARK: - Sync Engine (Production — Latency Compensated)
/// Synchronizes AVPlayer playback across all room participants with
/// **network latency compensation**.
///
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                   THE LATENCY PROBLEM                            │
/// │                                                                  │
/// │  Host presses Play at media-time = 10.0s, wall-clock T0.        │
/// │  Command travels to server (T0 + uplink)                         │
/// │  Server broadcasts to all clients (T0 + uplink + downlink)       │
/// │  Client receives command at T0 + RTT                              │
/// │                                                                  │
/// │  If client seeks to 10.0s and plays, it is already RTT seconds   │
/// │  behind the host. Everyone sees different frames.                │
///                                                                  │
/// │  SOLUTION: compensate using synchronized server clock + RTT.     │
/// └─────────────────────────────────────────────────────────────────┘
///
/// Compensation formula:
///   elapsedSinceEvent = currentServerTime - eventServerTimestamp
///   targetMediaTime = eventMediaTime + (isPlayingEvent ? elapsedSinceEvent : 0)
///
/// The client's view of "currentServerTime" is kept accurate by the
/// WebSocketClient's ping/pong clock-sync (see synchronizedServerTime).

@MainActor
final class SyncEngine: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentMediaItem: MediaItem?
    @Published private(set) var syncQuality: SyncQuality = .perfect
    @Published private(set) var isLoadingMedia = false
    @Published private(set) var errorMessage: String?
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    // Latency telemetry — surfaced for the SyncIndicatorView
    @Published private(set) var estimatedRTTms: Int = 0
    @Published private(set) var lastCompensationMs: Int = 0

    // MARK: - Private State

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var lastSyncEventTime: TimeInterval = 0      // server time of last event
    private var lastSyncMediaTime: TimeInterval = 0      // media time at last event
    private var lastSyncWasPlaying: Bool = false
    private var driftCorrectionTimer: Timer?
    private var stateBroadcastTimer: Timer?
    private var seekCompletionHandler: ((Bool) -> Void)?

    private let wsClient: WebSocketClient
    private let roomID: String
    private let userID: String
    private let isHost: Bool

    // MARK: - Constants

    private enum Constants {
        static let driftThreshold: TimeInterval = 0.5        // 500ms — visible desync
        static let hardResyncThreshold: TimeInterval = 1.5   // 1.5s — force reseek
        static let seekTolerance: TimeInterval = 0.05         // 50ms — don't reseek for tiny diffs
        static let stateBroadcastInterval: TimeInterval = 2.0
        static let driftCheckInterval: TimeInterval = 1.0
        static let maxPredictiveJump: TimeInterval = 5.0     // cap extrapolation
    }

    // MARK: - Init

    init(wsClient: WebSocketClient, roomID: String, userID: String, isHost: Bool) {
        self.wsClient = wsClient
        self.roomID = roomID
        self.userID = userID
        self.isHost = isHost
        super.init()
    }

    deinit {
        // Cannot touch @MainActor state in deinit; just tear down player.
        player?.pause()
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
    }

    // MARK: - Server Time Accessor

    /// The client's best estimate of the current server wall-clock time.
    /// Maintained by WebSocketClient via ping/pong clock synchronization.
    private var currentServerTime: TimeInterval {
        wsClient.synchronizedServerTime > 0
            ? wsClient.synchronizedServerTime
            : Date().timeIntervalSince1970
    }

    private var estimatedRTT: TimeInterval {
        wsClient.estimatedRTT
    }

    // MARK: - Load Media

    func loadMedia(_ item: MediaItem) {
        teardownPlayer()
        isLoadingMedia = true
        errorMessage = nil

        guard let url = URL(string: item.streamURL) else {
            errorMessage = "Invalid media URL"
            isLoadingMedia = false
            return
        }

        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.playerItem = playerItem

        let player = AVPlayer(playerItem: playerItem)
        player.volume = volume
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        currentMediaItem = item

        observeDuration(playerItem)
        observeStatus(playerItem)
        addTimeObserver()

        // Host broadcasts the new media so participants load the same item
        if isHost {
            let msg = SyncMessage(
                command: .changeMedia,
                roomID: roomID,
                senderID: userID,
                mediaItem: item
            )
            broadcast(msg)
        }
    }

    // MARK: - Playback Controls (HOST ONLY)

    func play() {
        guard isHost else { return }
        player?.play()
        isPlaying = true

        // Stamp the command with current server time so receivers can compensate
        let msg = SyncMessage(
            command: .play,
            roomID: roomID,
            senderID: userID,
            mediaTime: currentTime,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    func pause() {
        guard isHost else { return }
        player?.pause()
        isPlaying = false

        let msg = SyncMessage(
            command: .pause,
            roomID: roomID,
            senderID: userID,
            mediaTime: currentTime,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        guard isHost else { return }
        let clamped = max(0, min(time, duration))

        let handler: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.currentTime = clamped
            self.broadcastSyncCommand(.seek, mediaTime: clamped)
            self.seekCompletionHandler = nil
        }
        seekCompletionHandler = handler
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     completionHandler: handler)
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    // MARK: - Incoming Sync Command Handling (LATENCY COMPENSATED)

    func handleSyncMessage(_ message: SyncMessage) {
        // Ignore echoes of our own commands (server broadcasts to all incl. sender)
        guard message.senderID != userID else { return }

        switch message.command {
        case .play:
            handlePlay(message)
        case .pause:
            handlePause(message)
        case .seek:
            handleSeek(message)
        case .changeMedia:
            if let item = message.mediaItem {
                handleMediaChange(item, from: message)
            }
        case .stateRequest:
            // A participant is asking the host for the current state
            if isHost {
                respondWithCurrentState()
            }
        case .stateResponse:
            handleStateResponse(message)
        case .correction:
            handleForcedCorrection(message)
        case .ping, .pong:
            break
        }
    }

    // MARK: - Host: Periodic State Broadcast

    func startStateBroadcast() {
        stopStateBroadcast()
        guard isHost else { return }

        stateBroadcastTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.stateBroadcastInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastPeriodicState()
            }
        }
    }

    func stopStateBroadcast() {
        stateBroadcastTimer?.invalidate()
        stateBroadcastTimer = nil
    }

    // MARK: - Host: Periodic State Broadcast
    /// Every 2s the host sends its current playback position stamped with
    /// server time. Participants use this to detect and correct drift.
    private func broadcastPeriodicState() {
        guard isHost else { return }

        // Use a lightweight "seek" envelope as a heartbeat state sync.
        // Participants ignore seek commands within tolerance, but reseek
        // if drift exceeds the threshold.
        let msg = SyncMessage(
            command: .seek,        // reuse seek as a state pulse
            roomID: roomID,
            senderID: userID,
            mediaTime: currentTime,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    // MARK: - Drift Monitoring

    func startDriftMonitor() {
        stopDriftMonitor()
        driftCorrectionTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.driftCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDrift()
            }
        }
    }

    func stopDriftMonitor() {
        driftCorrectionTimer?.invalidate()
        driftCorrectionTimer = nil
    }

    /// Compare local playback position against the extrapolated host position.
    /// If drift exceeds threshold, self-correct (participant) or request state (host).
    private func checkDrift() {
        guard lastSyncEventTime > 0 else { return }

        // Extrapolate where the host SHOULD be right now
        let elapsed = currentServerTime - lastSyncEventTime
        let extrapolatedHostTime: TimeInterval
        if lastSyncWasPlaying {
            extrapolatedHostTime = min(lastSyncMediaTime + elapsed, duration)
        } else {
            extrapolatedHostTime = lastSyncMediaTime
        }

        let drift = abs(currentTime - extrapolatedHostTime)
        let driftMs = drift * 1000
        syncQuality = .fromDrift(driftMs)

        // Surface telemetry
        estimatedRTTms = Int(estimatedRTT * 1000)

        // Hard resync: participant drifted way off — request fresh state from host
        if !isHost && drift > Constants.hardResyncThreshold {
            Logger.sync.warn("Hard drift: \(String(format: "%.0f", driftMs))ms — requesting state from host")
            requestStateFromHost()
            return
        }

        // Soft correction: small drift, nudge locally without a visible jump
        if !isHost && drift > Constants.driftThreshold && drift <= Constants.hardResyncThreshold {
            Logger.sync.info("Soft drift: \(String(format: "%.0f", driftMs))ms — self-correcting to \(String(format: "%.2f", extrapolatedHostTime))s")
            seekSilently(to: extrapolatedHostTime, preserveRate: isPlaying)
            lastCompensationMs = Int(driftMs)
        }
    }

    // MARK: - Latency-Compensated Command Handlers

    /// PLAY command received.
    /// The host stamped this with (mediaTime, serverTimestamp).
    /// By the time we receive it, real playback on the host has advanced by
    /// (currentServerTime - serverTimestamp). We must seek AHEAD by that delta
    /// so we're aligned with where the host actually is right now.
    private func handlePlay(_ message: SyncMessage) {
        let eventMediaTime = message.mediaTime ?? 0
        let eventServerTime = message.timestamp

        // ─── Core latency compensation ───
        let elapsedSinceEvent = max(0, currentServerTime - eventServerTime)
        let compensatedTarget = min(
            eventMediaTime + min(elapsedSinceEvent, Constants.maxPredictiveJump),
            duration > 0 ? duration : .infinity
        )

        let compensationMs = Int(elapsedSinceEvent * 1000)
        lastCompensationMs = compensationMs
        recordSyncPoint(mediaTime: compensatedTarget, isPlaying: true, serverTime: currentServerTime)

        Logger.sync.info("▶️ PLAY  host@\(fmt(eventMediaTime))s → seek to \(fmt(compensatedTarget))s (+\(compensationMs)ms latency, RTT \(Int(estimatedRTT*1000))ms)")

        // If we're already playing and within tolerance, do nothing (avoids stutter)
        if isPlaying && abs(currentTime - compensatedTarget) < Constants.seekTolerance {
            return
        }

        // Seek to compensated position, then play
        player?.seek(to: CMTime(seconds: compensatedTarget, preferredTimescale: 600)) { [weak self] _ in
            guard let self else { return }
            self.player?.play()
            self.isPlaying = true
            self.currentTime = compensatedTarget
        }
    }

    /// PAUSE command received.
    /// Pause is less latency-sensitive (a paused frame is a paused frame),
    /// but we still seek to the host's exact frame for visual consistency.
    private func handlePause(_ message: SyncMessage) {
        let eventMediaTime = message.mediaTime ?? currentTime
        recordSyncPoint(mediaTime: eventMediaTime, isPlaying: false, serverTime: message.timestamp)

        Logger.sync.info("⏸️ PAUSE at \(fmt(eventMediaTime))s")

        player?.pause()
        isPlaying = false

        // Seek to exact paused frame
        player?.seek(to: CMTime(seconds: eventMediaTime, preferredTimescale: 600)) { [weak self] _ in
            self?.currentTime = eventMediaTime
        }
    }

    /// SEEK command received (also used as periodic state pulse from host).
    /// Compensate for latency so we land where the host actually is now.
    private func handleSeek(_ message: SyncMessage) {
        guard let eventMediaTime = message.mediaTime else { return }
        let eventServerTime = message.timestamp
        let elapsedSinceEvent = max(0, currentServerTime - eventServerTime)

        // If host is playing, extrapolate forward; if paused, hold position.
        // We infer "playing" from whether this seek arrived as a state pulse
        // vs an explicit seek — but conservatively, we extrapolate only if
        // the gap is small (state pulse) to avoid over-jumping on real seeks.
        let isStatePulse = elapsedSinceEvent < Constants.stateBroadcastInterval + 1
        let compensatedTarget: TimeInterval
        if isStatePulse && isPlaying {
            compensatedTarget = min(eventMediaTime + elapsedSinceEvent, duration > 0 ? duration : .infinity)
        } else {
            compensatedTarget = eventMediaTime
        }

        // Within tolerance → ignore (prevents jitter from periodic pulses)
        if abs(currentTime - compensatedTarget) < Constants.seekTolerance {
            recordSyncPoint(mediaTime: compensatedTarget, isPlaying: isPlaying, serverTime: currentServerTime)
            return
        }

        recordSyncPoint(mediaTime: compensatedTarget, isPlaying: isPlaying, serverTime: currentServerTime)
        Logger.sync.info("⏩ SEEK  host@\(fmt(eventMediaTime))s → \(fmt(compensatedTarget))s")

        let wasPlaying = isPlaying
        seekSilently(to: compensatedTarget, preserveRate: wasPlaying)
    }

    private func handleMediaChange(_ item: MediaItem, from message: SyncMessage) {
        Logger.sync.info("🎬 Media change: \(item.displayTitle)")
        loadMedia(item)

        // If host is already partway in, jump to their position
        if let startTime = message.mediaTime, startTime > 0.1 {
            player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            currentTime = startTime
            recordSyncPoint(mediaTime: startTime, isPlaying: false, serverTime: message.timestamp)
        }
    }

    private func handleStateResponse(_ message: SyncMessage) {
        guard !isHost, let hostMediaTime = message.mediaTime else { return }

        // Host responded to our stateRequest with its current position + server time.
        // Apply full latency compensation.
        let elapsedSinceEvent = max(0, currentServerTime - message.timestamp)
        let hostPlaying = message.command == .play  // host marks play vs seek
        let target = hostPlaying
            ? min(hostMediaTime + elapsedSinceEvent, duration > 0 ? duration : .infinity)
            : hostMediaTime

        let drift = abs(currentTime - target)
        if drift > Constants.driftThreshold {
            Logger.sync.warn("State response: correcting \(String(format: "%.0f", drift*1000))ms → \(fmt(target))s")
            seekSilently(to: target, preserveRate: hostPlaying)
            recordSyncPoint(mediaTime: target, isPlaying: hostPlaying, serverTime: currentServerTime)
        }
    }

    private func handleForcedCorrection(_ message: SyncMessage) {
        guard let target = message.mediaTime else { return }
        Logger.sync.info("🔄 Forced correction → \(fmt(target))s")
        seekSilently(to: target, preserveRate: isPlaying)
        recordSyncPoint(mediaTime: target, isPlaying: isPlaying, serverTime: currentServerTime)
        syncQuality = .perfect
    }

    // MARK: - Seek Helpers

    /// Seek without a visible stutter — used for drift correction.
    /// Uses tolerant seeking to avoid rebuffering on tiny adjustments.
    private func seekSilently(to time: TimeInterval, preserveRate: Bool) {
        let clamped = max(0, min(time, duration))
        let tolerance = CMTime(seconds: Constants.seekTolerance, preferredTimescale: 600)
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance,
            completionHandler: { [weak self] _ in
                guard let self else { return }
                self.currentTime = clamped
            }
        )
        if preserveRate { player?.play() }
    }

    // MARK: - Host State Response

    private func respondWithCurrentState() {
        let msg = SyncMessage(
            command: isPlaying ? .play : .pause,  // signal play vs pause state
            roomID: roomID,
            senderID: userID,
            mediaTime: currentTime,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    func requestStateFromHost() {
        let msg = SyncMessage(
            command: .stateRequest,
            roomID: roomID,
            senderID: userID,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    // MARK: - Sync Point Bookkeeping

    private func recordSyncPoint(mediaTime: TimeInterval, isPlaying: Bool, serverTime: TimeInterval) {
        lastSyncEventTime = serverTime
        lastSyncMediaTime = mediaTime
        lastSyncWasPlaying = isPlaying
        syncQuality = .perfect
    }

    // MARK: - Broadcast Helpers

    private func broadcastSyncCommand(_ command: SyncCommand, mediaTime: TimeInterval) {
        let msg = SyncMessage(
            command: command,
            roomID: roomID,
            senderID: userID,
            mediaTime: mediaTime,
            timestamp: currentServerTime
        )
        broadcast(msg)
    }

    private func broadcast(_ message: SyncMessage) {
        // Inject synchronized server time into every outgoing command
        var msg = message
        if msg.timestamp == 0 { msg.timestamp = currentServerTime }

        if let data = try? JSONEncoder().encode(msg),
           let string = String(data: data, encoding: .utf8) {
            wsClient.send(string)
        }
    }

    // MARK: - AVPlayer Observation

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, time.seconds.isFinite else { return }
            self.currentTime = time.seconds
        }
    }

    private func teardownPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        currentMediaItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopDriftMonitor()
        stopStateBroadcast()
    }

    func cleanup() {
        teardownPlayer()
    }

    private func observeDuration(_ item: AVPlayerItem) {
        item.publisher(for: \.duration, options: .new)
            .compactMap { $0.seconds.isFinite ? $0.seconds : nil }
            .assign(to: &$duration)
    }

    private func observeStatus(_ item: AVPlayerItem) {
        item.publisher(for: \.status, options: .new)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isLoadingMedia = false
                    self?.errorMessage = nil
                case .failed:
                    self?.errorMessage = item.error?.localizedDescription ?? "Failed to load media"
                    self?.isLoadingMedia = false
                    Logger.sync.error("AVPlayerItem failed: \(self?.errorMessage ?? "unknown")")
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Formatting

    private func fmt(_ t: TimeInterval) -> String {
        String(format: "%.2f", t)
    }
}
