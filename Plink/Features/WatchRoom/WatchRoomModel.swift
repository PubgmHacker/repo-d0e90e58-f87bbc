// Plink/Features/WatchRoom/WatchRoomModel.swift
// Single owner of room session lifecycle (runbook §21, Brain Review 4 P0-28)
//
// This is the composition root for the v2 realtime + playback path.
// Implements RealtimeClientDelegate — receives clock probes, snapshots,
// session ready, and other server messages, routing them to the right
// controller.
//
// Lifecycle:
//   1. init(roomId, ticket, realtimeClient, clock, syncController, coordinator)
//   2. connect() → RealtimeClient.connect(roomId:)
//   3. RealtimeClient session.ready → .synchronizing → snapshot → .connected
//   4. Clock probes ingested via ClockSynchronizer
//   5. Snapshots + live states applied via OrderedSyncController
//   6. Chat messages routed to chatTimeline
//   7. Reactions/participant events routed to UI
//   8. disconnect() → RealtimeClient.disconnect() + PlaybackCoordinator.teardown()
//
// Feature flag: WatchRoomModel is only instantiated when
// FeatureFlag.realtime_protocol_v2 is true. Otherwise legacy
// RoomViewModel + WebSocketClient + SyncEngine path is used.

import Foundation
import Observation

@MainActor
@Observable
public final class WatchRoomModel: RealtimeClientDelegate {
    // MARK: - Public state (UI binds to these)
    public private(set) var connectionState: RealtimeConnectionState = .idle
    public private(set) var isHost: Bool = false
    public private(set) var participants: [ParticipantInfo] = []
    public private(set) var chatMessages: [ChatMessageInfo] = []
    public private(set) var lastError: String?
    public private(set) var clockSynced: Bool = false
    public private(set) var hardCorrectionCount: Int = 0

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator

    // MARK: - Config
    public let roomId: String
    private let mediaSource: PlaybackSource?
    private var chatCatchupCursor: String?  // last messageId received
    private var clientMessageIds = Set<String>()  // dedupe (P1-11)

    public init(
        roomId: String,
        baseEndpoint: URL,
        ticketProvider: @escaping (String) async throws -> RealtimeTicket,
        mediaSource: PlaybackSource? = nil,
        clock: ClockSynchronizer = ClockSynchronizer(),
        coordinator: PlaybackCoordinator = PlaybackCoordinator()
    ) {
        self.roomId = roomId
        self.mediaSource = mediaSource
        self.clock = clock
        self.coordinator = coordinator

        // Create sync controller with clock + coordinator's current controller
        // (coordinator.currentController is set after prepare)
        let player = coordinator.currentController ?? NativePlayerController()
        self.syncController = OrderedSyncController(clock: clock, player: player)

        self.realtimeClient = RealtimeClient(baseEndpoint: baseEndpoint, ticketProvider: ticketProvider)
        self.realtimeClient.delegate = self
    }

    // MARK: - Lifecycle

    public func connect() async {
        if let source = mediaSource {
            await coordinator.prepare(source)
            // Re-create syncController with the now-prepared controller
            // (coordinator.currentController was nil at init time)
        }
        realtimeClient.connect(roomId: roomId)
    }

    public func disconnect() {
        realtimeClient.disconnect()
        coordinator.teardown()
        syncController.resetCompletely()
        clock.reset()
        participants = []
        chatMessages = []
        clientMessageIds.removeAll()
    }

    // MARK: - Host commands (host only)

    public func sendPlayCommand(positionMs: Int64) {
        guard isHost else { return }
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: nil,
            positionMs: positionMs,
            playing: true
        )))
    }

    public func sendPauseCommand(positionMs: Int64) {
        guard isHost else { return }
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: nil,
            positionMs: positionMs,
            playing: false
        )))
    }

    public func sendSeekCommand(positionMs: Int64, playing: Bool) {
        guard isHost else { return }
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: nil,
            positionMs: positionMs,
            playing: playing
        )))
    }

    // MARK: - Chat (optimistic + reconciliation)

    public func sendChat(text: String) {
        let clientMessageId = UUID().uuidString
        // Optimistic local add
        let optimistic = ChatMessageInfo(
            messageId: nil,
            clientMessageId: clientMessageId,
            senderId: currentUserId ?? "",
            senderName: currentUsername ?? "me",
            text: text,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            isPending: true
        )
        chatMessages.append(optimistic)
        clientMessageIds.insert(clientMessageId)
        // Trim to maxMessages=200 (runbook §19)
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }
        // Send to server — server will broadcast back with messageId
        realtimeClient.send(.chatSend(.init(
            roomId: roomId,
            clientMessageId: clientMessageId,
            text: text
        )))
    }

    // MARK: - RealtimeClientDelegate

    public var lastEpoch: Int64 { syncController.lastEpoch }
    public var lastSeq: Int64 { syncController.lastSeq }

    public func ingestClockProbe(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double) {
        clock.ingest(clientSentMs: clientSentMs, serverMs: serverMs, clientReceivedMs: clientReceivedMs)
        clockSynced = clock.isSynchronized
    }

    public func applySnapshot(_ state: RealtimeRoomState?) {
        guard let state = state else { return }
        Task { await syncController.apply(state) }
    }

    public func sessionDidConnect() {
        connectionState = .connected
        // P1-11: request chat catch-up after reconnect
        Task { await fetchChatCatchup() }
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
            // Reconnect will be triggered by RealtimeClient on close
        case .error(let err):
            lastError = "\(err.code): \(err.message)"
        case .syncState, .syncStateSnapshot, .clockProbeReply, .sessionReady:
            // Handled by RealtimeClient directly
            break
        }
    }

    // MARK: - Private handlers

    private var currentUserId: String?
    private var currentUsername: String?

    private func handleChatBroadcast(_ chat: RealtimeServerMessage.ChatBroadcast) {
        // P1-11: dedupe by clientMessageId — if we sent this optimistically,
        // reconcile (replace pending with confirmed) instead of appending.
        if let cmid = chat.clientMessageId, clientMessageIds.contains(cmid) {
            // Find optimistic message and mark as confirmed
            if let idx = chatMessages.firstIndex(where: { $0.clientMessageId == cmid }) {
                let optimistic = chatMessages[idx]
                chatMessages[idx] = ChatMessageInfo(
                    messageId: chat.messageId,
                    clientMessageId: cmid,
                    senderId: chat.senderId,
                    senderName: chat.senderName,
                    text: chat.text,
                    createdAtMs: chat.createdAtMs,
                    isPending: false
                )
                _ = optimistic
            }
            return
        }
        // New message from another user
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
        // Trim to maxMessages=200
        if chatMessages.count > 200 {
            chatMessages.removeFirst(chatMessages.count - 200)
        }
    }

    private func handleReaction(_ reaction: RealtimeServerMessage.ReactionBroadcast) {
        // UI layer (WatchRoomScreen) subscribes to reactionStream and displays
        // flying emoji. We just forward — no state to track here.
        // (Future: expose as AsyncStream)
        lastError = nil  // clear error on activity
    }

    private func handleParticipantJoined(_ event: RealtimeServerMessage.ParticipantEvent) {
        let info = ParticipantInfo(userId: event.userId, username: event.username, isLocal: event.userId == currentUserId)
        if !participants.contains(where: { $0.userId == info.userId }) {
            participants.append(info)
        }
    }

    private func handleParticipantLeft(_ event: RealtimeServerMessage.ParticipantEvent) {
        participants.removeAll { $0.userId == event.userId }
    }

    // MARK: - Chat catch-up (P1-11)

    /// After reconnect, fetch chat messages that may have been missed during
    /// offline/PubSub outage. Uses REST endpoint with after-cursor.
    private func fetchChatCatchup() async {
        // TODO: call GET /api/rooms/:id/messages?after=<chatCatchupCursor>
        // For now, this is a stub — the REST endpoint must be implemented
        // on the backend (P1-11 deferred item).
        // When implemented:
        //   1. Fetch messages after chatCatchupCursor
        //   2. Filter out clientMessageIds already in clientMessageIds set
        //   3. Append to chatMessages
        //   4. Update chatCatchupCursor to last received messageId
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
