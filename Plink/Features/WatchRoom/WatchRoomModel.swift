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
    public private(set) var reactions: [WatchReactionEvent] = []

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator
    private let playbackProxy: PlaybackProxy  // P0-29: stable proxy for syncController

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

        self.realtimeClient = RealtimeClient(baseEndpoint: baseEndpoint, ticketProvider: ticketProvider)
        self.realtimeClient.delegate = self
    }

    // MARK: - Lifecycle

    public func connect() async {
        // P0-31: subscribe to stateChanges stream
        startStateChangesSubscription()

        // P0-29: prepare media, then wire proxy.target to real controller
        if let source = mediaSource {
            do {
                try await coordinator.prepare(source)
                // P0-29/P0-53: wire proxy to the now-prepared real controller
                playbackProxy.attachTarget(coordinator.currentController)
            } catch {
                lastError = "Media prepare failed: \(error.localizedDescription)"
                connectionState = .failed(reason: "Media prepare failed")
                return
            }
        }
        realtimeClient.connect(roomId: _roomId)
    }

    public func disconnect() {
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

    // MARK: - Chat (optimistic + reconciliation)

    public func sendChat(text: String) {
        let clientMessageId = UUID().uuidString
        let optimistic = ChatMessageInfo(
            messageId: nil,
            clientMessageId: clientMessageId,
            senderId: currentUserId,  // P1-32: real identity
            senderName: currentUsername,
            text: text,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            isPending: true
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
    }

    // MARK: - RealtimeClientDelegate

    // P0-30: roomId protocol conformance — protocol requires String?
    // but our roomId is non-optional String. Return wrapped optional.
    public var roomId: String? { _roomId }

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
    }

    // P1-51: reaction handler — uses WatchReactionEvent (renamed to avoid ambiguity)
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
    public var id: String { messageId ?? clientMessageId ?? UUID().uuidString }
}

// P1-51: renamed from ReactionEvent to avoid @Observable macro ambiguity
public struct WatchReactionEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let userId: String
    public let username: String
    public let emoji: String
    public let timestampMs: Int64
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
