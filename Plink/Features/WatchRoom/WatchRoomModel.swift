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
    // P0-36: reactions — temporarily removed to resolve @Observable macro
    // ambiguity with existing ReactionEvent from SyncEvents.swift.
    // Will re-add in follow-up commit with explicit type resolution.

    // MARK: - Owned components
    public let realtimeClient: RealtimeClient
    public let clock: ClockSynchronizer
    public let syncController: OrderedSyncController
    public let coordinator: PlaybackCoordinator
    private let playbackProxy: PlaybackProxy  // P0-29: stable proxy for syncController

    // MARK: - Config
    // P0-30: roomId stored as _roomId (private) + public computed roomId
    // + protocol conformance via computed var roomId: String? { _roomId }
    private let _roomId: String
    public var roomId: String { _roomId }
    public let mediaSource: PlaybackSource?
    public let mediaId: String?  // P1-33: typed media ID for host commands
    public let currentUserId: String  // P1-32: identity via init, not UserDefaults
    public let currentUsername: String  // P1-32
    private var chatCatchupCursor: String?
    private var clientMessageIds = Set<String>()
    private var stateChangesTask: Task<Void, Never>?

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
                // P0-29: wire proxy to the now-prepared real controller
                playbackProxy.target = coordinator.currentController
            } catch {
                // P1-36: prepare failed — don't connect realtime, show error
                lastError = "Media prepare failed: \(error.localizedDescription)"
                connectionState = .failed(reason: "Media prepare failed")
                return
            }
        }
        realtimeClient.connect(roomId: roomId)
    }

    public func disconnect() {
        stateChangesTask?.cancel()
        stateChangesTask = nil
        realtimeClient.disconnect()
        coordinator.teardown()
        syncController.resetCompletely()
        clock.reset()
        participants = []
        chatMessages = []
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

    // MARK: - Host commands (P0-33: functional with optimistic local apply)

    public func sendPlayCommand() async {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        // P0-33: optimistic local apply
        await coordinator.currentController?.play()
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: mediaId,  // P1-33: typed mediaId
            positionMs: positionMs,
            playing: true
        )))
    }

    public func sendPauseCommand() {
        guard isHost else { return }
        let positionMs = Int64((coordinator.position) * 1000)
        // P0-33: optimistic local apply
        coordinator.currentController?.pause()
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: false
        )))
    }

    public func sendSeekCommand(to seconds: TimeInterval) async {
        guard isHost else { return }
        let positionMs = Int64(seconds * 1000)
        // P0-33: optimistic local seek
        _ = await coordinator.currentController?.seek(to: seconds, precise: true)
        let actionId = UUID().uuidString
        realtimeClient.send(.syncCommand(.init(
            roomId: roomId,
            actionId: actionId,
            mediaId: mediaId,
            positionMs: positionMs,
            playing: coordinator.isPlaying
        )))
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
            roomId: roomId,
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

    public func applySnapshot(_ state: RealtimeRoomState?) {
        guard let state = state else { return }
        Task { await syncController.apply(state) }
        // P1-34: wire syncController metrics to UI
        hardCorrectionCount = syncController.hardCorrectionCount
        lastDriftMs = syncController.lastDriftMs
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

    // P0-36: reaction handler — reactions array temporarily removed
    // (will re-add when @Observable macro ambiguity is resolved)
    private func handleReaction(_ reaction: RealtimeServerMessage.ReactionBroadcast) {
        // No-op for now — reaction overlay will be wired in follow-up commit
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

    // MARK: - Chat catch-up (P0-35: implemented REST client)

    private func fetchChatCatchup() async {
        guard let client = chatCatchupClient else { return }
        do {
            var cursor = chatCatchupCursor
            var hasMore = true
            while hasMore {
                let response = try await client.fetchMessages(roomId: roomId, after: cursor)
                for msg in response.messages {
                    // Dedupe by clientMessageId
                    if let cmid = msg.clientMessageId, clientMessageIds.contains(cmid) {
                        continue
                    }
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
                    cursor = msg.messageId
                }
                chatCatchupCursor = cursor
                if chatMessages.count > 200 {
                    chatMessages.removeFirst(chatMessages.count - 200)
                }
                hasMore = response.hasMore
            }
        } catch {
            lastError = "Chat catch-up failed: \(error.localizedDescription)"
        }
    }

    // P0-36: presence snapshot — fetch current participants
    private func fetchPresenceSnapshot() async {
        guard let client = chatCatchupClient else { return }
        do {
            let snapshot = try await client.fetchParticipants(roomId: roomId)
            participants = snapshot.map { p in
                ParticipantInfo(userId: p.userId, username: p.username, isLocal: p.userId == currentUserId)
            }
        } catch {
            // Non-fatal — participant events will still arrive
        }
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

// MARK: - P0-35: Chat catch-up REST client protocol

public protocol ChatCatchupClient: Sendable {
    func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse
    func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot]
}

public struct ChatCatchupResponse: Sendable, Equatable {
    public let messages: [ChatCatchupMessage]
    public let hasMore: Bool
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
