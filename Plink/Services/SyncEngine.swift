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

    /// 🔧 v34.18: public setter for currentMediaItem
    func setCurrentMediaItem(_ item: MediaItem) {
        currentMediaItem = item
    }

    /// 🔧 v35.6: public setter for isPlaying — updated from YouTube IFrame API
    /// state changes so ControlsOverlay shows correct play/pause icon.
    func setIsPlaying(_ playing: Bool) {
        isPlaying = playing
    }
    @Published private(set) var errorMessage: String?
    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    // Latency telemetry — surfaced for the SyncIndicatorView
    @Published private(set) var estimatedRTTms: Int = 0
    @Published private(set) var lastCompensationMs: Int = 0

    // MARK: - Private State

    // 🔧 FIX H3: Expose player as internal so VideoContainerView can use the SAME
    // AVPlayer instance (was: private — forced VideoContainerView to create its own
    // second AVPlayer, causing visual desync).
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var lastSyncEventTime: TimeInterval = 0      // server time of last event
    private var lastSyncMediaTime: TimeInterval = 0      // media time at last event
    private var lastSyncWasPlaying: Bool = false
    private var driftCorrectionTimer: Timer?
    private var stateBroadcastTimer: Timer?
    private var seekCompletionHandler: ((Bool) -> Void)?
    /// 🔧 FIX 1.2: Buffer underrun observer
    private var bufferObserver: NSObjectProtocol?
    private var bufferUnderrunCount = 0

    private let wsClient: WebSocketClient
    private let roomID: String
    private let userID: String
    private let isHost: Bool
    /// 🔧 FIX 2.2: Throttle for play/pause to prevent rapid-fire WS spam
    private var lastCommandTime: TimeInterval = 0
    private let commandThrottle: TimeInterval = 0.3  // 300ms min between commands

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
        // 🔧 v34.15: GUARD — don't reload the same media item!
        // WS reconnects on fullscreen toggle → calls loadMedia with the SAME item
        // → teardownPlayer sets currentMediaItem = nil → VideoContainerView re-renders
        // → WKWebView re-attached → rendering context destroyed → black screen.
        // If the same item is already loaded AND WebView already has it, skip entirely.
        if let existing = currentMediaItem,
           existing.id == item.id,
           existing.streamURL == item.streamURL,
           WebViewControl.shared.loadedVideoId != nil {
            Logger.sync.info("🔍 loadMedia: SAME item already loaded — skipping (prevents rendering destroy)")
            return
        }

        teardownPlayer()
        isLoadingMedia = true
        errorMessage = nil

        // 🔧 FIX: For WebView playback mode (YouTube embed, cinema sites, HTML pages),
        // AVPlayer can't play the URL — it would just spin forever. Skip AVPlayer setup
        // entirely. RoomView's VideoContainerView will use WebVideoView instead.
        // We still set currentMediaItem so RoomView knows to render the video section.
        if item.effectivePlaybackMode == .webview {
            currentMediaItem = item
            isLoadingMedia = false
            errorMessage = nil  // 🔧 FIX: explicitly clear any stale error from previous AVPlayer
            Logger.sync.info("🔍 loadMedia: webview mode, skipping AVPlayer. errorMessage cleared.")
            // Host still broadcasts the new media to participants
            if isHost {
                let msg = SyncMessage(
                    command: .changeMedia,
                    roomID: roomID,
                    senderID: userID,
                    mediaItem: item
                )
                broadcast(msg)
            }
            return
        }

        guard let url = URL(string: item.streamURL) else {
            errorMessage = "Invalid media URL"
            isLoadingMedia = false
            return
        }

        // 🔧 FIX v8.1 (July 2026): use AVURLAsset with custom HTTP headers
        // for googlevideo.com URLs (backend yt-dlp extraction results).
        //
        // 🔧 v9 (July 2026): for backend proxy URLs (youtube-stream endpoint),
        // add Authorization header with JWT token — backend requires auth.
        // The proxy URL looks like:
        //   https://plink-backend.../api/media/youtube-stream?id=VIDEO_ID
        // Without the Authorization header, backend returns 401 → AVPlayer fails.
        //
        // AVAsset(url:) doesn't let you set headers, but AVURLAsset does via
        // the AVURLAssetHTTPHeaderFieldsKey option.
        //
        // 🔧 FIX v8.2: AVURLAssetHTTPHeaderFieldsKey is an Obj-C NSString
        // constant that's not directly importable in Swift. Use the raw
        // string literal "AVURLAssetHTTPHeaderFieldsKey" instead — this is
        // the underlying value Apple's AVFoundation uses internally.
        let asset: AVAsset
        let lowerURL = item.streamURL.lowercased()
        if lowerURL.contains("googlevideo.com") {
            // Direct googlevideo URL (v8 approach — IP-bound, may fail)
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                "Referer": "https://www.youtube.com/",
                "Origin": "https://www.youtube.com",
            ]
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
            ]
            asset = AVURLAsset(url: url, options: options)
            Logger.sync.info("🔍 loadMedia: googlevideo.com URL — added User-Agent + Referer headers")
        } else if lowerURL.contains("plink-backend") && lowerURL.contains("youtube-stream") {
            // 🔧 v9.3: auth via query param — AVPlayer drops Authorization headers
            // on Range requests, causing 401 → -1008. Instead, append token as
            // ?token=JWT to the URL itself. AVPlayer always sends the full URL,
            // so the token is guaranteed to reach the backend.
            //
            // The URL already has ?id=VIDEO_ID — we append &token=JWT.
            // Backend reads token from query param (v9.3) instead of header.
            var finalURL = url
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                // Append token as query param
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let tokenItem = URLQueryItem(name: "token", value: token)
                if var existing = components?.queryItems {
                    existing.append(tokenItem)
                    components?.queryItems = existing
                } else {
                    components?.queryItems = [tokenItem]
                }
                if let modifiedURL = components?.url {
                    finalURL = modifiedURL
                }
            }
            asset = AVAsset(url: finalURL)
            Logger.sync.info("🔍 loadMedia: backend proxy URL — token in query param: \(finalURL.absoluteString.prefix(80))...")
        } else {
            asset = AVAsset(url: url)
        }

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
        observeBufferUnderrun(playerItem)  // 🔧 FIX 1.2: Wire up buffer observer

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
        let now = Date().timeIntervalSince1970
        guard now - lastCommandTime >= commandThrottle else { return }
        lastCommandTime = now
        player?.play()
        isPlaying = true

        // 🔧 WEBVIEW: for YouTube/cinema, send JS command to the WebView player.
        // AVPlayer is nil in webview mode, so player?.play() is a no-op.
        // WebViewControl.shared sends playVideo()/pauseVideo() to the WKWebView.
        if player == nil {
            WebViewControl.shared.play()
        }

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
        let now = Date().timeIntervalSince1970
        guard now - lastCommandTime >= commandThrottle else { return }
        lastCommandTime = now
        player?.pause()
        isPlaying = false

        // 🔧 WEBVIEW: pause the YouTube/cinema player via JS
        if player == nil {
            WebViewControl.shared.pause()
        }

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
        // 🔧 v32.11: in webview mode, duration is often 0 (never set from AVPlayer).
        // min(time, 0) = 0 → seek always goes to start. Fix: only clamp to duration
        // if duration > 0. In webview mode, video.duration is handled by JS.
        let clamped: TimeInterval
        if duration > 0 {
            clamped = max(0, min(time, duration))
        } else {
            clamped = max(0, time)  // don't clamp upper bound if duration unknown
        }

        // 🔧 v32.19: set seek lock — block WebView timeupdate for 1.5s so
        // seek bar shows the new position immediately (YouTube seek is async,
        // timeupdate sends old position for ~0.5s before seek takes effect)
        seekLockUntil = Date().addingTimeInterval(1.5)

        // 🔧 FIX: for webview mode, there's no AVPlayer to seek. Just update
        // currentTime, send JS seek to YouTube player, and broadcast.
        if player == nil {
            currentTime = clamped
            WebViewControl.shared.seek(to: clamped)
            broadcastSyncCommand(.seek, mediaTime: clamped)
            return
        }

        let handler: @Sendable (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = clamped
                self.broadcastSyncCommand(.seek, mediaTime: clamped)
                self.seekCompletionHandler = nil
            }
        }
        seekCompletionHandler = handler
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     completionHandler: handler)

        // 🔧 FIX 2.3: Fallback timeout — if seek doesn't complete in 2s, broadcast anyway
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.seekCompletionHandler != nil else { return }
            Logger.sync.warn("Seek timeout — broadcasting anyway")
            self.currentTime = clamped
            self.broadcastSyncCommand(.seek, mediaTime: clamped)
            self.seekCompletionHandler = nil
        }
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    /// 🔧 v32.10 (July 2026): Update currentTime from WebView timeupdate events.
    /// This does NOT seek — it only updates the published currentTime property
    /// so the UI (seek bar, time display) reflects actual playback position.
    /// Without this, seekRelative(+10) would seek to (0 + 10) = 10s instead of
    /// (currentTime + 10), because currentTime was never updated from WebView.
    /// 🔧 v32.17: removed the < 5.0 difference check — it was blocking legitimate
    /// updates after seeks (seek to 100s, timeupdate sends 100.5, diff > 5 →
    /// blocked). Now always updates, but only triggers objectWillChange if the
    /// value actually changed (SwiftUI @Published deduplicates automatically).
    /// 🔧 v32.19: added seekLock — after user seek, block WebView timeupdate
    /// for 1.5s so the seek bar shows the new position immediately instead of
    /// lagging back to old position (YouTube seek is async).
    private var seekLockUntil: Date = .distantPast

    func updateCurrentTimeFromWebView(_ time: TimeInterval) {
        // v32.19: if we're within 1.5s of a user seek, ignore WebView updates
        // (they send old position before seek takes effect)
        if Date() < seekLockUntil {
            return
        }
        currentTime = time
    }

    /// 🔧 v32.11 (July 2026): Update duration from WebView.
    /// In webview mode, AVPlayer is nil → duration never set from AVPlayer
    /// observers. Without this, seek() clamps to min(time, 0) = 0 → always
    /// seeks to start. This method sets duration from HTML5 video.duration.
    func updateDurationFromWebView(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        self.duration = duration
        print("📏 SyncEngine v32.19: duration = \(duration)s")
    }

    // MARK: - Late Joiner Support

    /// 🔧 FIX 1.1: Late joiner must request current state from host immediately.
    /// Without this, new viewers see black screen until host does play/pause/seek.
    func requestInitialState() {
        guard !isHost else { return }
        Logger.sync.info("Requesting initial state from host (late joiner)")
        requestStateFromHost()
    }

    // MARK: - Incoming Sync Command Handling (LATENCY COMPENSATED)

    func handleSyncMessage(_ message: SyncMessage) {
        // Ignore echoes of our own commands (server broadcasts to all incl. sender)
        guard message.senderID != userID else { return }

        // 🔧 v49 (Gemini audit fix #1): Validate mediaItemID to prevent race conditions.
        // If a play/pause/seek command arrives for a DIFFERENT video than what's
        // currently loaded, ignore it — it's a stale command from before video change.
        if message.command == .play || message.command == .pause || message.command == .seek {
            if let currentId = currentMediaItem?.id,
               let messageId = message.mediaItem?.id,
               currentId != messageId {
                Logger.sync.warn("🔍 Ignoring stale command for old media (current=\(currentId), got=\(messageId))")
                return
            }
        }

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
        // 🔧 v34: ENABLE state broadcast for webview mode too — needed for sync.
        // Previously disabled because there's no AVPlayer, but now WebViewControl
        // provides currentTime via updateCurrentTimeFromWebView().
        // Without state broadcast, non-host participants drift indefinitely.

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

        // 🔧 v34: WEBVIEW mode — control YouTube player via JS bridge
        if player == nil {
            isPlaying = true
            // Seek to compensated position first, then play
            if abs(currentTime - compensatedTarget) > 1.0 {
                WebViewControl.shared.seek(to: compensatedTarget)
                currentTime = compensatedTarget
            }
            WebViewControl.shared.play()
            return
        }

        // 🔧 FAST PATH: If we're already playing and within tolerance, do nothing
        // (avoids stutter on rapid play/pause toggles)
        if isPlaying && abs(currentTime - compensatedTarget) < Constants.seekTolerance {
            return
        }

        // 🔧 FAST PATH: If drift is small (< 2s), just play without seeking —
        // the drift monitor will self-correct within a few seconds.
        // This avoids the "seek then play" stutter that was causing delay.
        if abs(currentTime - compensatedTarget) < 2.0 {
            player?.play()
            isPlaying = true
            return
        }

        // Large drift — seek to compensated position, then play
        player?.seek(to: CMTime(seconds: compensatedTarget, preferredTimescale: 600)) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player?.play()
                self.isPlaying = true
                self.currentTime = compensatedTarget
            }
        }
    }

    /// PAUSE command received.
    /// 🔧 IMMEDIATE: Pause instantly for zero-latency visual sync.
    /// Seek to exact frame happens after pause (non-blocking).
    private func handlePause(_ message: SyncMessage) {
        let eventMediaTime = message.mediaTime ?? currentTime
        recordSyncPoint(mediaTime: eventMediaTime, isPlaying: false, serverTime: message.timestamp)

        Logger.sync.info("⏸️ PAUSE at \(fmt(eventMediaTime))s")

        // 🔧 v34: WEBVIEW mode — pause YouTube player via JS bridge
        if player == nil {
            isPlaying = false
            currentTime = eventMediaTime
            WebViewControl.shared.pause()
            return
        }

        // 🔧 IMMEDIATE pause — no waiting for seek completion
        player?.pause()
        isPlaying = false
        currentTime = eventMediaTime

        // Seek to exact paused frame (async, non-blocking)
        player?.seek(to: CMTime(seconds: eventMediaTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.currentTime = eventMediaTime }
        }
    }

    /// SEEK command received (also used as periodic state pulse from host).
    /// Compensate for latency so we land where the host actually is now.
    ///
    /// 🔧 FIX M1: Was using `elapsedSinceEvent < stateBroadcastInterval + 1` as a
    /// heuristic to detect state pulses vs real seeks. But the host's periodic
    /// state broadcast (every 2s) and a user-initiated seek can both arrive within
    /// that 3s window, causing real seeks to be silently reverted (extrapolated
    /// back to the original position).
    ///
    /// New heuristic: a state pulse is a seek where |eventMediaTime - lastSyncMediaTime|
    /// is small (≤ 2s, normal playback progress). A real seek has a large jump.
    /// This distinguishes "host is just broadcasting position" from "host actually
    /// jumped to a new position".
    private func handleSeek(_ message: SyncMessage) {
        guard let eventMediaTime = message.mediaTime else { return }
        let eventServerTime = message.timestamp
        let elapsedSinceEvent = max(0, currentServerTime - eventServerTime)

        // 🔧 v56 (Gemini): Soft Sync — don't seek if delta < 2.5 seconds.
        // Small deltas are from normal drift, not real seeks. Seeking
        // causes YouTube to flush its buffer → 5-second freeze.
        let compensatedTarget: TimeInterval
        if isPlaying {
            compensatedTarget = min(eventMediaTime + elapsedSinceEvent, duration > 0 ? duration : .infinity)
        } else {
            compensatedTarget = eventMediaTime
        }

        let timeDelta = abs(currentTime - compensatedTarget)
        if timeDelta < 2.5 {
            // 🔧 v56: Within 2.5s — soft sync, NO seek. Just update recorded time.
            recordSyncPoint(mediaTime: compensatedTarget, isPlaying: isPlaying, serverTime: currentServerTime)
            Logger.sync.info("⏩ SKIP seek (delta=\(fmt(timeDelta))s < 2.5s) — soft sync")
            return
        }

        // Real seek needed (delta > 2.5s)
        recordSyncPoint(mediaTime: compensatedTarget, isPlaying: isPlaying, serverTime: currentServerTime)
        Logger.sync.info("⏩ SEEK host@\(fmt(eventMediaTime))s → \(fmt(compensatedTarget))s [delta=\(fmt(timeDelta))s]")

        // 🔧 v34: WEBVIEW mode — seek YouTube player via JS bridge
        if player == nil {
            currentTime = compensatedTarget
            seekLockUntil = Date().addingTimeInterval(1.5)
            WebViewControl.shared.seek(to: compensatedTarget)
            return
        }

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
                Task { @MainActor in self.currentTime = clamped }
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
            Task { @MainActor in self.currentTime = time.seconds }
        }
    }

    private func teardownPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // 🔧 FIX 1.2: Remove buffer observer on teardown
        if let observer = bufferObserver {
            NotificationCenter.default.removeObserver(observer)
            bufferObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        currentMediaItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil  // 🔧 FIX: clear error message on teardown
        stopDriftMonitor()
        stopStateBroadcast()
        // 🔧 FIX: clear ALL Combine subscriptions (observeStatus, observeDuration, etc.)
        // Without this, stale AVPlayerItem observers can fire .failed status and
        // set errorMessage = "Ошибка настройки видеопроигрывателя" (error 153)
        // even after we've moved to webview playback mode.
        cancellables.removeAll()
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
                    let errDesc = item.error?.localizedDescription ?? "Failed to load media"
                    let errCode = (item.error as NSError?)?.code ?? -1
                    Logger.sync.error("🔍 observeStatus .failed: code=\(errCode), desc=\(errDesc)")
                    Logger.sync.error("🔍 observeStatus: currentMediaItem.streamURL=\(self?.currentMediaItem?.streamURL ?? "nil")")
                    Logger.sync.error("🔍 observeStatus: effectivePlaybackMode=\(self?.currentMediaItem?.effectivePlaybackMode.rawValue ?? "nil")")
                    // 🔧 FIX: don't set errorMessage if we're in webview mode —
                    // AVPlayer failure is expected (YouTube URL can't play in AVPlayer).
                    // The WebView handles playback, not AVPlayer.
                    if self?.currentMediaItem?.effectivePlaybackMode == .webview {
                        Logger.sync.info("🔍 observeStatus: ignoring AVPlayer failure (webview mode)")
                        self?.isLoadingMedia = false
                        return
                    }
                    self?.errorMessage = errDesc
                    self?.isLoadingMedia = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // 🔧 FIX 1.2: Buffer underrun observer — detects when AVPlayer stalls
    // due to slow network. Pauses local playback (without broadcasting pause
    // to other participants), then resumes + requests fresh state from host
    // when buffer recovers. Prevents visible desync during buffering.
    private func observeBufferUnderrun(_ item: AVPlayerItem) {
        // Listen for playback stall notification
        bufferObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isHost else { return }
            Task { @MainActor in
                self.bufferUnderrunCount += 1
                Logger.sync.warn("Buffer underrun #\(self.bufferUnderrunCount) — local pause (no broadcast)")
                self.player?.pause()
            }
        }

        // Also observe isPlaybackLikelyToKeepUp for recovery
        item.publisher(for: \.isPlaybackLikelyToKeepUp, options: .new)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canKeepUp in
                guard let self, !self.isHost else { return }
                if canKeepUp && self.isPlaying {
                    // Buffer recovered — resume local playback + request fresh state
                    Logger.sync.info("Buffer recovered — resuming + requesting fresh state from host")
                    self.player?.play()
                    self.requestStateFromHost()
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
