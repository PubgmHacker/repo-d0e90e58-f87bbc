// Plink/Features/WatchRoom/WatchRoomModel.swift
// Single owner of room session lifecycle (runbook §21, Brain Review 5 P0-29..P0-37)
//
// Brain Review 5 fixes:
//   P0-29: PlaybackProxy — syncController talks to stable proxy, not dummy player
//   P0-30: RoomRole — sessionDidConnect(role:) sets isHost
//   P0-31: stateChanges stream — connectionState reflects all states
//   P0-33: functional host controls (optimistic local apply + v2 command)
//   P0-34: chat button opens sheet (handled in WatchRoomScreen)
//   P0-35: fetchChatCatchup REST client with cursor paging
//   P0-36: presence snapshot + reaction stream
//   P0-37: composition root (wiring in MainTabView handled separately)
//   P1-32: current user identity via init
//   P1-33: typed mediaId in host commands
//   P1-34: lastError + hardCorrectionCount + driftMs wired to UI

import Foundation
import Observation
import UIKit  // PATCH 16: UIApplication + UIWindowScene for Rutube fallback presentation

@MainActor
@Observable
public final class WatchRoomModel: RealtimeClientDelegate {
    // MARK: - Public state (UI binds to these)
    public private(set) var connectionState: RealtimeConnectionState = .idle
    public private(set) var isHost: Bool = false
    public private(set) var role: RoomRole = .viewer
    public private(set) var participants: [ParticipantInfo] = []
    public private(set) var chatMessages: [ChatMessageInfo] = []
    public private(set) var lastError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var hardCorrectionCount: Int = 0
    public private(set) var lastDriftMs: Double = 0
    // P1-51: reactions — renamed to WatchReactionEvent to avoid @Observable
    // macro type ambiguity with existing ReactionEvent from SyncEvents.swift
    // P1-61: reactions auto-expire after 3 seconds
    public private(set) var reactions: [WatchReactionEvent] = []
    private var reactionExpiryTask: Task<Void, Never>?

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator
    private let playbackProxy: PlaybackProxy  // P0-29: stable proxy for syncController

    // PATCH 14: DanmakuEngine + AmbientVideoSampler owned by the model.
    // One per room session — never global singletons (runbook §16).
    // The engine is fed by chat broadcast handler (chat messages become
    // danmaku placements). The sampler is fed by coordinator.nativePlayer
    // (palette drives PurpleAmbientBackdrop).
    private let danmakuEngine: DanmakuEngine
    private let ambientSampler: AmbientVideoSampler
    private var danmakuSnapshot: [DanmakuPlacement] = []
    private var ambientPalette: AmbientPalette = .defaultPalette
    private var danmakuPollTask: Task<Void, Never>?
    private var ambientSampleTask: Task<Void, Never>?

    // GPT-5.6 Final §7: Room theme + AI state + moderation
    var roomTheme: PlinkLivingTheme = PlinkThemeCatalog.resolve(nil)
    var aiAssistantEnabled = false
    var aiRecommendationsEnabled = false
    var aiState: V4AIState = .idle
    var moderationLevel: RoomModerationLevel = .standard

    // MARK: - Config
    // P0-30: roomId stored as _roomId (private) + protocol conformance via
    // computed var roomId: String? { _roomId }. Only ONE declaration.
    private let _roomId: String
    public let mediaSource: PlaybackSource?
    public let mediaId: String?  // P1-33: typed media ID for host commands
    public let currentUserId: String  // P1-32: identity via init, not UserDefaults
    public let currentUsername: String  // P1-32
    private var chatCatchupCursor: String?  // P0-59: opaque server cursor
    // P0-60: persistent messageIds set — initialized from current chatMessages
    private var knownMessageIds = Set<String>()
    private var clientMessageIds = Set<String>()
    private var stateChangesTask: Task<Void, Never>?
    // P0-52/P1-63: serial state pump — coalesce to latest state
    private var statePumpTask: Task<Void, Never>?
    private var pendingStates: [RealtimeRoomState] = []
    // P0-58: snapshot revision — buffer participant events during snapshot fetch
    private var snapshotInFlight = false
    private var bufferedParticipantEvents: [(isJoin: Bool, userId: String, username: String)] = []
    // P0-61: single authoritative rollback state
    private var lastAuthoritativeState: RealtimeRoomState?

    // P0-35: REST client for chat catch-up
    private let chatCatchupClient: ChatCatchupClient?

    // P0-5: init — class is @MainActor, init inherits isolation.
    // Default params use nil-coalescing inside body to avoid @MainActor
    // default expression evaluation in nonisolated context.
    public init(
        roomId: String,
        currentUserId: String,
        currentUsername: String,
        baseEndpoint: URL,
        ticketProvider: @escaping (String) async throws -> RealtimeTicket,
        mediaSource: PlaybackSource? = nil,
        mediaId: String? = nil,
        chatCatchupClient: ChatCatchupClient? = nil,
        clock: ClockSynchronizer? = nil,
        coordinator: PlaybackCoordinator? = nil
    ) {
        self._roomId = roomId
        self.currentUserId = currentUserId
        self.currentUsername = currentUsername
        self.mediaSource = mediaSource
        self.mediaId = mediaId
        self.chatCatchupClient = chatCatchupClient
        let resolvedClock = clock ?? ClockSynchronizer()
        self.clock = resolvedClock
        self.coordinator = coordinator ?? PlaybackCoordinator()

        // P0-29: create stable proxy — syncController talks to proxy, not dummy
        let proxy = PlaybackProxy()
        self.playbackProxy = proxy
        self.syncController = OrderedSyncController(clock: resolvedClock, player: proxy)

        // PATCH 14: instantiate engine + sampler BEFORE any use of self
        // (delegate = self below requires all stored properties initialized).
        // PATCH 16g: capture local let before assigning to self, so the
        // Task can configure it without requiring self to be fully
        // initialized.
        let danmakuEngine = DanmakuEngine()
        let ambientSampler = AmbientVideoSampler()
        self.danmakuEngine = danmakuEngine
        self.ambientSampler = ambientSampler

        // Now all stored properties are initialized — safe to use self.
        self.realtimeClient = RealtimeClient(baseEndpoint: baseEndpoint, ticketProvider: ticketProvider)
        self.realtimeClient.delegate = self

        // PATCH 16: DanmakuEngine has no startSampling() — caller polls
        // via poll(at:) which is started in connect().
        Task { @MainActor [danmakuEngine] in
            await danmakuEngine.configure(laneCount: 5)
        }
    }

    // MARK: - Lifecycle

    /// Brain Revision 3 Step 5: connect() is idempotent AND does NOT set .connected.
    ///
    /// State machine:
    ///   idle -> connecting (set here) -> joining/synchronizing (set by realtime callbacks)
    ///        -> connected (set ONLY by realtime session-ready/snapshot handshake)
    ///
    /// connect() sets .connecting and starts the realtime client. The realtime
    /// client's session-ready callback (handleRealtimeSessionReady) promotes
    /// to .connected. This prevents falsely advertising "connected" before the
    /// server has confirmed the session.
    public func connect() async {
        // Idempotent guard — already connected or in-flight.
        if connectionState == .connecting
            || connectionState == .connected
            || connectionState == .joining
            || connectionState == .synchronizing {
            return
        }
        connectionState = .connecting

        // P0-31: subscribe to stateChanges stream
        startStateChangesSubscription()

        // P0-29: prepare media, then wire proxy.target to real controller
        if let source = mediaSource {
            do {
                try await coordinator.prepare(source)
                // P0-29/P0-53: wire proxy to the now-prepared real controller
                playbackProxy.attachTarget(coordinator.currentController)

                // PATCH 14: attach native player to AmbientVideoSampler.
                // Only native HLS/MP4 sources have an AVPlayer — YouTube
                // and Rutube use WKWebView, so sampler falls back to
                // default palette (no sampling).
                if let player = coordinator.nativePlayer {
                    await ambientSampler.attach(player: player)
                    await ambientSampler.startSampling()
                    startAmbientPalettePolling()
                }
            } catch {
                lastError = "Media prepare failed: \(error.localizedDescription)"
                connectionState = .failed(reason: "Media prepare failed")
                return
            }
        }

        // Brain Revision 3: set .joining before realtime connect.
        // Realtime session-ready callback will promote to .connected.
        connectionState = .joining
        realtimeClient.connect(roomId: _roomId)

        // PATCH 14: start polling danmaku engine for snapshot.
        startDanmakuPolling()

        // NOTE: do NOT set .connected here.
        // handleRealtimeSessionReady() (called by RealtimeClient on session-ready
        // or snapshot handshake) is the only place that promotes to .connected.
    }

    /// Brain Revision 3 Step 5: called by RealtimeClient when session-ready /
    /// snapshot handshake completes. This is the ONLY place .connected is set.
    func handleRealtimeSessionReady() {
        guard connectionState == .connecting || connectionState == .joining || connectionState == .synchronizing else {
            return
        }
        connectionState = .connected
    }

    /// Brain Revision 3 Step 5: called by RealtimeClient during sync handshake.
    func handleRealtimeSynchronizing() {
        guard connectionState == .connecting || connectionState == .joining else { return }
        connectionState = .synchronizing
    }

    /// Brain Phase 6: disconnect() is idempotent.
    /// Calling it again when already idle is a no-op. This prevents
    /// double-teardown if onDisappear fires after leaveRoom (e.g. when
    /// fullScreenCover dismiss propagates).
    public func disconnect() {
        // Idempotent guard — already torn down.
        if connectionState == .idle { return }

        stateChangesTask?.cancel()
        stateChangesTask = nil
        statePumpTask?.cancel()
        statePumpTask = nil
        pendingStates.removeAll()
        pendingActions.removeAll()
        realtimeClient.disconnect()
        coordinator.teardown()
        syncController.resetCompletely()
        clock.reset()
        participants = []
        chatMessages = []
        reactions = []
        clientMessageIds.removeAll()
        connectionState = .idle

        // PATCH 14: stop engine + sampler
        // PATCH 16: DanmakuEngine has no stopSampling() — cancelling the
        // poll task is sufficient (engine itself is passive).
        danmakuPollTask?.cancel()
        danmakuPollTask = nil
        ambientSampleTask?.cancel()
        ambientSampleTask = nil
        Task { [danmakuEngine, ambientSampler] in
            await danmakuEngine.clear()
            await ambientSampler.stopSampling()
            await ambientSampler.detach()
        }
        danmakuSnapshot = []
        ambientPalette = .defaultPalette
    }

    // MARK: - PATCH 14: Danmaku polling

    /// Polls the DanmakuEngine every 250ms for the current placement
    /// snapshot. Caches in danmakuSnapshot so views can read without
    /// awaiting on the actor during render.
    private func startDanmakuPolling() {
        danmakuPollTask?.cancel()
        danmakuPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = ContinuousClock.now
                let snapshot = await self.danmakuEngine.poll(at: now)
                self.danmakuSnapshot = snapshot
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Updates the danmaku lane count based on orientation. Called by
    /// WatchRoomScreen on rotation.
    public func updateDanmakuLaneCount(_ count: Int) {
        Task { [danmakuEngine] in
            await danmakuEngine.configure(laneCount: count)
        }
    }

    // MARK: - PATCH 14: Ambient palette polling

    /// Polls the AmbientVideoSampler every 500ms for the current palette.
    /// Caches in ambientPalette so views can read without awaiting.
    private func startAmbientPalettePolling() {
        ambientSampleTask?.cancel()
        ambientSampleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let palette = await self.ambientSampler.currentPalette()
                let enabled = AmbientCapability.shouldEnableLivingBackground()
                self.ambientPalette = enabled ? palette : .defaultPalette
                await self.ambientSampler.setEnabled(enabled)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // P0-31: subscribe to RealtimeClient.stateChanges
    private func startStateChangesSubscription() {
        stateChangesTask?.cancel()
        stateChangesTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.realtimeClient.stateChanges {
                guard !Task.isCancelled else { return }
                self.connectionState = state
            }
        }
    }

    // P0-54: pending actions for reconciliation/rollback
    private struct PendingAction {
        let actionId: String
        let preActionPosition: Double
        let preActionPlaying: Bool
        let timestamp: Date
    }
    private var pendingActions: [String: PendingAction] = [:]
    private static let actionTimeoutMs: Int64 = 10_000

    // MARK: - Host commands (P0-33: functional with optimistic local apply + P0-54: reconciliation)

    public func sendPlayCommand() async {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local apply
        await coordinator.currentController?.play()
        let actionId = UUID().uuidString
        // P0-54: track pending action for rollback
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date()
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: true
        )))
        scheduleActionTimeout(actionId)
    }

    public func sendPauseCommand() {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local apply
        coordinator.currentController?.pause()
        let actionId = UUID().uuidString
        // P0-54: track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date()
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: false
        )))
        scheduleActionTimeout(actionId)
    }

    public func sendSeekCommand(to seconds: TimeInterval) async {
        guard isHost else { return }
        let positionMs = Int64(seconds * 1000)
        let prePosition = coordinator.position
        let prePlaying = coordinator.isPlaying
        // P0-33: optimistic local seek
        _ = await coordinator.currentController?.seek(to: seconds, precise: true)
        let actionId = UUID().uuidString
        // P0-54: track pending action
        pendingActions[actionId] = PendingAction(
            actionId: actionId,
            preActionPosition: prePosition,
            preActionPlaying: prePlaying,
            timestamp: Date()
        )
        realtimeClient.send(.syncCommand(.init(
            roomId: _roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: coordinator.isPlaying
        )))
        scheduleActionTimeout(actionId)
    }

    // P0-62: single authoritative rollback — NOT concurrent Tasks per action.
    // Rollback to last authoritative state, request fresh snapshot.
    private func handleActionRejection(_ errorCode: String) {
        pendingActions.removeAll()
        // P0-61/P0-62: restore to last authoritative state in a single operation
        if let state = lastAuthoritativeState {
            Task { [weak self] in
                guard let self else { return }
                let target = Double(state.positionMs) / 1000.0
                _ = await self.coordinator.currentController?.seek(to: target, precise: true)
                if state.playing {
                    await self.coordinator.currentController?.play()
                } else {
                    self.coordinator.currentController?.pause()
                }
                self.coordinator.currentController?.setRate(Float(state.rate))
            }
        }
        // P0-62: request fresh snapshot immediately
        realtimeClient.send(.stateRequest(.init(roomId: _roomId, afterSeq: lastSeq)))
        lastError = "Command rejected: \(errorCode) — rolled back to authoritative state"
    }

    // P0-54: timeout pending actions
    private func scheduleActionTimeout(_ actionId: String) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.actionTimeoutMs) * 1_000_000)
            guard let self else { return }
            if self.pendingActions[actionId] != nil {
                self.pendingActions.removeValue(forKey: actionId)
                self.lastError = "Command timeout — no server confirmation"
            }
        }
    }

    // P0-54: clear pending action when authoritative state arrives
    private func clearPendingActionsIfConfirmed(state: RealtimeRoomState) {
        // Clear confirmed/stale pending actions
        pendingActions = pendingActions.filter { (_, action) in
            Date().timeIntervalSince(action.timestamp) < Double(Self.actionTimeoutMs / 1000)
        }
    }

    // MARK: - Chat (optimistic + reconciliation + P1-54 failure/retry)

    public func sendChat(text: String) {
        let clientMessageId = UUID().uuidString
        let optimistic = ChatMessageInfo(
            messageId: nil,
            clientMessageId: clientMessageId,
            senderId: currentUserId,
            senderName: currentUsername,
            text: text,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            isPending: true,
            isFailed: false
        )
        chatMessages.append(optimistic)
        clientMessageIds.insert(clientMessageId)
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId,
            clientMessageId: clientMessageId,
            text: text
        )))
        // P1-54: schedule 5s timeout — mark as failed if no server echo
        scheduleChatSendTimeout(clientMessageId: clientMessageId)
    }

    // P1-54: retry a failed chat message
    public func retryChatMessage(_ message: ChatMessageInfo) {
        guard message.isFailed, let cmid = message.clientMessageId else { return }
        // Find and update the message back to pending
        if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
            chatMessages[idx] = ChatMessageInfo(
                messageId: nil,
                clientMessageId: cmid,
                senderId: message.senderId,
                senderName: message.senderName,
                text: message.text,
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                isPending: true,
                isFailed: false
            )
        }
        realtimeClient.send(.chatSend(.init(
            roomId: _roomId,
            clientMessageId: cmid,
            text: message.text
        )))
        scheduleChatSendTimeout(clientMessageId: cmid)
    }

    // P1-54: mark message as failed after 5s if no server confirmation
    private func scheduleChatSendTimeout(clientMessageId: String) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            // If still pending (no server echo), mark as failed
            if let idx = self.chatMessages.firstIndex(where: {
                $0.clientMessageId == clientMessageId && $0.isPending
            }) {
                let msg = self.chatMessages[idx]
                self.chatMessages[idx] = ChatMessageInfo(
                    messageId: msg.messageId,
                    clientMessageId: msg.clientMessageId,
                    senderId: msg.senderId,
                    senderName: msg.senderName,
                    text: msg.text,
                    createdAtMs: msg.createdAtMs,
                    isPending: false,
                    isFailed: true
                )
            }
        }
    }

    // MARK: - RealtimeClientDelegate

    // P0-30: roomId protocol conformance — protocol requires String?
    // but our roomId is non-optional String. Return wrapped optional.
    public var roomId: String? { _roomId }

    /// Brain Revision 3 Step 5: stable id for PlayerStage identity.
    public var roomID: String? { _roomId }

    /// Brain Revision 3 Step 8: thumbnail URL for artwork-driven palette.
    /// For YouTube content, returns the standard thumbnail URL.
    /// For other sources, returns nil (uses Cinema2026 default palette).
    public var mediaThumbnailURL: String? {
        guard let source = mediaSource else { return nil }
        switch source {
        case .youtube(let videoId):
            return "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
        case .rutube(let videoId):
            // Rutube thumbnails are at rutube.ru/thumbs/<id>/
            return "https://pic.rutube.ru/video/\(videoId)/"
        case .hls, .mp4, .external:
            return nil
        }
    }

    public var lastEpoch: Int64 { syncController.lastEpoch }
    public var lastSeq: Int64 { syncController.lastSeq }

    public func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double) {
        clock.ingest(clientSentMs: clientSentMs, serverMs: serverMs, clientReceivedMs: clientReceivedMs)
        clockSynced = clock.isSynchronized
    }

    // P0-52: serial state pump — enqueue state, process in order
    public func applySnapshot(_ state: RealtimeRoomState?) {
        guard let state = state else { return }
        pendingStates.append(state)
        startStatePumpIfNeeded()
    }

    private func startStatePumpIfNeeded() {
        guard statePumpTask == nil, !pendingStates.isEmpty else { return }
        statePumpTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingStates.isEmpty && !Task.isCancelled {
                let state = self.pendingStates.removeFirst()
                await self.syncController.apply(state)
                // P0-61: store last authoritative state for rollback
                self.lastAuthoritativeState = state
                // P1-34: update UI metrics AFTER each apply completes
                self.hardCorrectionCount = self.syncController.hardCorrectionCount
                self.lastDriftMs = self.syncController.lastDriftMs
                // P0-61: clear pending actions that match this state
                self.clearPendingActionsIfConfirmed(state: state)
            }
            self.statePumpTask = nil
        }
    }

    // P0-30: sessionDidConnect now carries role
    public func sessionDidConnect(role: RoomRole) {
        self.role = role
        self.isHost = (role == .host)
        connectionState = .connected
        // P0-35: request chat catch-up after reconnect
        Task { await fetchChatCatchup() }
        // P0-36: request presence snapshot
        Task { await fetchPresenceSnapshot() }
    }

    public func handleOtherMessage(_ message: RealtimeServerMessage) {
        switch message {
        case .chatBroadcast(let chat):
            handleChatBroadcast(chat)
        case .reactionBroadcast(let reaction):
            handleReaction(reaction)
        case .participantJoined(let event):
            handleParticipantJoined(event)
        case .participantLeft(let event):
            handleParticipantLeft(event)
        case .serverDraining(let drain):
            lastError = drain.message
        case .error(let err):
            lastError = "\(err.code): \(err.message)"
            // P0-54: rollback on rejection errors
            if err.code == "NOT_HOST" || err.code == "STALE_EPOCH" || err.code == "RATE_LIMITED" {
                handleActionRejection(err.code)
            }
        case .syncState, .syncStateSnapshot, .clockProbeReply, .sessionReady:
            break
        }
    }

    // MARK: - Private handlers

    private func handleChatBroadcast(_ chat: RealtimeServerMessage.ChatBroadcast) {
        if let cmid = chat.clientMessageId, clientMessageIds.contains(cmid) {
            if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
                chatMessages[idx] = ChatMessageInfo(
                    messageId: chat.messageId,
                    clientMessageId: cmid,
                    senderId: chat.senderId,
                    senderName: chat.senderName,
                    text: chat.text,
                    createdAtMs: chat.createdAtMs,
                    isPending: false
                )
            }
            // P0-35: update cursor for confirmed own messages too
            chatCatchupCursor = chat.messageId
            return
        }
        let msg = ChatMessageInfo(
            messageId: chat.messageId,
            clientMessageId: chat.clientMessageId,
            senderId: chat.senderId,
            senderName: chat.senderName,
            text: chat.text,
            createdAtMs: chat.createdAtMs,
            isPending: false
        )
        chatMessages.append(msg)
        if let cmid = chat.clientMessageId { clientMessageIds.insert(cmid) }
        chatCatchupCursor = chat.messageId
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }

        // PATCH 14: enqueue danmaku placement for this chat message.
        // Skip system/admin messages (they don't fly as danmaku).
        // Text width is estimated at 8pt per character — close enough
        // for lane scheduling; the actual rendered width is irrelevant
        // to lane availability.
        let danmakuMsg = DanmakuMessage(
            text: msg.text,
            color: .white,
            senderName: msg.senderName,
            createdAt: Date(),
            isPremium: msg.isPremium,
            isAdmin: msg.isAdmin
        )
        let estimatedWidth = CGFloat(msg.text.count * 8)
        Task { [danmakuEngine] in
            await danmakuEngine.enqueue(
                danmakuMsg,
                textWidth: estimatedWidth,
                viewportWidth: 400  // conservative default; engine clamps duration anyway
            )
        }
    }

    // P1-51/P1-61: reaction handler with auto-expiry
    private func handleReaction(_ reaction: RealtimeServerMessage.ReactionBroadcast) {
        let event = WatchReactionEvent(
            id: UUID(),
            userId: reaction.userId,
            username: reaction.username,
            emoji: reaction.emoji,
            timestampMs: reaction.serverTimeMs
        )
        reactions.append(event)
        if reactions.count > 50 {
            reactions.removeFirst(reactions.count - 50)
        }
        // P1-61: auto-expire reactions after 3 seconds
        scheduleReactionExpiry()
    }

    // P1-61: remove old reactions after 3s
    private func scheduleReactionExpiry() {
        reactionExpiryTask?.cancel()
        reactionExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 3000
            self.reactions.removeAll { $0.timestampMs < cutoff }
        }
    }

    private func handleParticipantJoined(_ event: RealtimeServerMessage.ParticipantEvent) {
        // P0-58: buffer if snapshot is in flight
        if snapshotInFlight {
            bufferedParticipantEvents.append((isJoin: true, userId: event.userId, username: event.username))
            return
        }
        let info = ParticipantInfo(userId: event.userId, username: event.username, isLocal: event.userId == currentUserId)
        if !participants.contains(where: { $0.userId == info.userId }) {
            participants.append(info)
        }
    }

    private func handleParticipantLeft(_ event: RealtimeServerMessage.ParticipantEvent) {
        // P0-58: buffer if snapshot is in flight
        if snapshotInFlight {
            bufferedParticipantEvents.append((isJoin: false, userId: event.userId, username: event.username))
            return
        }
        participants.removeAll { $0.userId == event.userId }
    }

    // MARK: - Chat catch-up (P0-35: implemented REST client)

    // P0-59/P0-60: fetchChatCatchup with opaque cursor + persistent dedupe
    private func fetchChatCatchup() async {
        guard let client = chatCatchupClient else { return }

        // P0-60: initialize knownMessageIds from current chatMessages
        for msg in chatMessages {
            if let mid = msg.messageId { knownMessageIds.insert(mid) }
        }

        do {
            var cursor = chatCatchupCursor
            var hasMore = true
            var pageCount = 0
            let maxPages = 20

            while hasMore && pageCount < maxPages {
                let response = try await client.fetchMessages(roomId: _roomId, after: cursor)
                pageCount += 1

                for msg in response.messages {
                    // P0-60: dedupe by messageId using persistent set
                    if knownMessageIds.contains(msg.messageId) { continue }
                    if let cmid = msg.clientMessageId, clientMessageIds.contains(cmid) {
                        knownMessageIds.insert(msg.messageId)
                        continue
                    }
                    knownMessageIds.insert(msg.messageId)

                    let info = ChatMessageInfo(
                        messageId: msg.messageId,
                        clientMessageId: msg.clientMessageId,
                        senderId: msg.senderId,
                        senderName: msg.senderName,
                        text: msg.text,
                        createdAtMs: msg.createdAtMs,
                        isPending: false
                    )
                    chatMessages.append(info)
                    if let cmid = msg.clientMessageId { clientMessageIds.insert(cmid) }
                }

                // P0-59: use server-provided opaque nextCursor, not messageId
                if let next = response.nextCursor {
                    cursor = next
                    chatCatchupCursor = next
                } else {
                    hasMore = false
                }
                hasMore = response.hasMore && cursor != nil

                if chatMessages.count > 200 {
                    chatMessages.removeFirst(chatMessages.count - 200)
                }
            }
            // P0-60: sort chronologically after merge
            chatMessages.sort { $0.createdAtMs < $1.createdAtMs }
        } catch {
            lastError = "Chat catch-up failed: \(error.localizedDescription)"
        }
    }

    // P0-58/P0-36: presence snapshot with event buffering
    private func fetchPresenceSnapshot() async {
        guard let client = chatCatchupClient else { return }
        snapshotInFlight = true  // P0-58: buffer events during fetch
        do {
            let snapshot = try await client.fetchParticipants(roomId: _roomId)
            // P0-58: apply snapshot, then merge buffered events
            participants = snapshot.map { p in
                ParticipantInfo(userId: p.userId, username: p.username, isLocal: p.userId == currentUserId)
            }
            // P0-58: replay buffered participant events
            for event in bufferedParticipantEvents {
                if event.isJoin {
                    let info = ParticipantInfo(userId: event.userId, username: event.username, isLocal: event.userId == currentUserId)
                    if !participants.contains(where: { $0.userId == info.userId }) {
                        participants.append(info)
                    }
                } else {
                    participants.removeAll { $0.userId == event.userId }
                }
            }
            bufferedParticipantEvents.removeAll()
        } catch {
            // Non-fatal — participant events will still arrive
        }
        snapshotInFlight = false
    }

    // MARK: - UI properties (some stubs, some wired)

    var bufferedFraction: Double { 0 }
    var qualityLabel: String { coordinator.capabilities.supportsPiP ? "HD" : "SD" }
    var hostId: String? { nil }
    var activeSpeakerName: String? { nil }
    var microphoneState: MicrophoneUIState { .off }
    var cameraState: CameraUIState { .off }
    var unreadCount: Int { 0 }

    // PATCH 14: danmaku placements come from DanmakuEngine. The model
    // polls the engine every 250ms (display-linked cadence) and caches
    // the snapshot in danmakuSnapshot. Views read from this cached array
    // — they never await on the actor during render.
    var danmakuPlacements: [DanmakuPlacement] { danmakuSnapshot }
    var danmakuLaneCount: Int { 5 }
    var danmakuOpacity: Double { 0.85 }

    // PATCH 14: ambient palette comes from AmbientVideoSampler. Drives
    // PurpleAmbientBackdrop's primaryColor + secondaryColor so the room
    // haze breathes with the movie.
    var ambientState: AmbientState {
        AmbientState(
            intensity: AmbientCapability.shouldEnableLivingBackground() ? 0.55 : 0.0,
            primaryColor: ambientPalette.primaryColor,
            secondaryColor: ambientPalette.secondaryColor
        )
    }

    // PATCH 14: Rutube fallback indicator. True when source is .rutube
    // and the embedded player's JS API is unavailable — UI shows a toast
    // prompting the user to open the video in Rutube's external app.
    var requiresRutubeFallback: Bool {
        guard case .rutube = coordinator.currentSource else { return false }
        guard let rutube = coordinator.currentController as? RutubePlaybackController else {
            return false
        }
        return rutube.requiresExternalFallback
    }

    // PATCH 14: open current Rutube video in SFSafariViewController.
    // Called by WatchRoomScreen when user taps "Open in Rutube" toast.
    func openInRutubeExternal() {
        guard let rutube = coordinator.currentController as? RutubePlaybackController else {
            return
        }
        // Find the top-most view controller to present from.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else {
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        rutube.openInExternalPlayer(from: topVC)
    }

    func leaveRoom() { disconnect() }
    func openPlayerSettings() {}
    func startPiP() {}
    func enterFullscreen() {
        // Brain §5: no forced orientation. Fullscreen = hide chat/social,
        // player fills screen. System rotation handles landscape.
    }

    func exitFullscreen() {
        // No-op — system rotation handles return to portrait.
    }
    func openEmojiPicker() {}  // PATCH 14: kept for back-compat; picker is now shown by composer
    func toggleMicrophone() async {}
    func toggleCamera() async {}

    // PATCH 14: send a reaction emoji via RealtimeClient.
    // Validates against ReactionPalette — free emojis always sendable,
    // premium requires Plink+ entitlement.
    func sendReaction(emoji: String, hasPremium: Bool) {
        guard ReactionPalette.canSend(emoji, hasPremium: hasPremium) else {
            lastError = "Cannot send emoji: \(emoji) requires Plink+"
            return
        }
        let msg = RealtimeClientMessage.reactionSend(
            .init(roomId: _roomId, emoji: emoji)
        )
        realtimeClient.send(msg)
    }
}

// MARK: - UI models

public struct ParticipantInfo: Identifiable, Sendable, Equatable {
    public let userId: String
    public let username: String
    public let isLocal: Bool
    public var id: String { userId }
}

public struct ChatMessageInfo: Identifiable, Sendable, Equatable {
    public let messageId: String?
    public let clientMessageId: String?
    public let senderId: String
    public let senderName: String
    public let text: String
    public let createdAtMs: Int64
    public let isPending: Bool
    public var isFailed: Bool  // P1-54: failed messages can be retried
    public var isAdmin: Bool = false
    public var isPremium: Bool = false
    public var id: String { messageId ?? clientMessageId ?? UUID().uuidString }

    // P1-54: convenience init without isFailed
    public init(messageId: String?, clientMessageId: String?, senderId: String,
                senderName: String, text: String, createdAtMs: Int64,
                isPending: Bool, isFailed: Bool = false) {
        self.messageId = messageId
        self.clientMessageId = clientMessageId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.createdAtMs = createdAtMs
        self.isPending = isPending
        self.isFailed = isFailed
    }
}

// P1-51: renamed from ReactionEvent to avoid @Observable macro ambiguity
public struct WatchReactionEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let userId: String
    public let username: String
    public let emoji: String
    public let timestampMs: Int64
    // Blueprint: reaction animation properties
    public let startX: CGFloat
    public let rotation: Double
    public let scale: CGFloat
    public let opacity: Double

    public init(id: UUID = UUID(), userId: String, username: String, emoji: String, timestampMs: Int64) {
        self.id = id
        self.userId = userId
        self.username = username
        self.emoji = emoji
        self.timestampMs = timestampMs
        self.startX = CGFloat.random(in: 0.1...0.9)
        self.rotation = Double.random(in: -30...30)
        self.scale = 1.5
        self.opacity = 1.0
    }

    public func currentY(in height: CGFloat) -> CGFloat {
        let elapsed = max(0, Date().timeIntervalSince1970 * 1000 - Double(timestampMs))
        let progress = min(1, elapsed / 2500)
        return height * (1 - CGFloat(progress) * 0.8)
    }
}

// MARK: - P0-35: Chat catch-up REST client protocol

public protocol ChatCatchupClient: Sendable {
    func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse
    func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot]
}

public struct ChatCatchupResponse: Sendable, Equatable {
    public let messages: [ChatCatchupMessage]
    public let hasMore: Bool
    public let nextCursor: String?  // P0-59: opaque server cursor
}

public struct ChatCatchupMessage: Sendable, Equatable {
    public let messageId: String
    public let clientMessageId: String?
    public let senderId: String
    public let senderName: String
    public let text: String
    public let createdAtMs: Int64

    public init(messageId: String, clientMessageId: String?, senderId: String, senderName: String, text: String, createdAtMs: Int64) {
        self.messageId = messageId
        self.clientMessageId = clientMessageId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.createdAtMs = createdAtMs
    }
}

public struct ParticipantSnapshot: Sendable, Equatable {
    public let userId: String
    public let username: String
}
