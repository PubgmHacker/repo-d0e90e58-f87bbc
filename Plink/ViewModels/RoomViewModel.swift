import Foundation

// MARK: - Room View Model
/// Оркестрирует комнатную сессию: WebSocket ↔ SyncEngine ↔ VoiceChatService.
/// Все состояния — @MainActor (iOS 17+ @Observable).
@MainActor
@Observable
final class RoomViewModel: WebSocketClientDelegate {

    // MARK: - State

    var room: Room
    var messages: [ChatMessage] = []
    var chatText = ""
    var errorMessage: String?
    var connectionStatus: ConnectionStatus = .connecting
    /// 🔧 FIX C8: Host's premium status — used by AdSessionManager to skip ads.
    /// Set by RoomView.setupViewModel from PremiumStatusManager.shared.isPremium.
    var hostIsPremium: Bool = false
    /// Cap on message history to prevent unbounded memory growth (FIX H13)
    private let maxMessages = 200
    /// Защита от повторного входа в joinRoomFlow / cleanup.
    private var isJoining = false
    private var didCleanup = false

    enum ConnectionStatus: Equatable {
        case connecting
        case connected
        case reconnecting
        case disconnected
    }

    // Поддвижки для привязки AVPlayer и индикаторов в RoomView.
    let syncEngine: SyncEngine
    let voiceChat: VoiceChatServiceProtocol

    var isHost: Bool { room.hostID == currentUserId }

    // MARK: - Dependencies (инжектируются через init)

    private let wsClient: WebSocketClient
    private let roomService: RoomServiceProtocol
    private let authService: AuthService
    /// 🔧 FIX H5/H6: Made internal so RoomView can access it for chat senderID
    let currentUserId: String

    // MARK: - Init

    init(room: Room,
         currentUserId: String,
         wsClient: WebSocketClient,
         roomService: RoomServiceProtocol,
         authService: AuthService,
         syncEngine: SyncEngine,
         voiceChat: VoiceChatServiceProtocol) {

        self.room = room
        self.currentUserId = currentUserId
        self.wsClient = wsClient
        self.roomService = roomService
        self.authService = authService
        self.syncEngine = syncEngine
        self.voiceChat = voiceChat

        // Восстановление сессии после прозрачного реконнекта WS.
        self.wsClient.onSessionRestored = { [weak self] in
            Task { @MainActor [weak self] in self?.handleSessionRestore() }
        }
    }

    nonisolated deinit {
        // Cleanup: только синхронная отмена socket из nonisolated context.
        // delegate и state mutations убраны — @MainActor класс освобождается целиком.
        wsClient.cancelSocketForDeinit()
    }

    // MARK: - Join Flow (главный async-вход экрана комнаты)

    /// Полный безопасный вход в комнату:
    /// 1. Получить свежий JWT.
    /// 2. Подключить WS с авторизацией + roomId.
    /// 3. Запустить voice mesh.
    /// Все ошибки пишутся в `errorMessage` (@MainActor).
    func joinRoomFlow() async {
        guard !isJoining else { return }
        isJoining = true
        connectionStatus = .connecting
        errorMessage = nil

        do {
            // 1) Свежий токен.
            let token = await authService.getFreshToken()
            wsClient.setAuthToken(token)
            wsClient.setActiveRoom(room.id)
            wsClient.delegate = self

            // 2) Подключение WS (токен + roomId уйдут в query).
            wsClient.connectToServer(roomID: room.id)

            // 3) Запуск голосовой mesh. Ждём подключения сигналинга слегка,
            //    чтобы joinRoom не потерялся при гонке с WS-handshake.
            try await Task.sleep(for: .milliseconds(300))
            try await voiceChat.startCall(roomId: room.id)

            // 🔧 FIX 1.1: Late joiner requests initial state from host
            syncEngine.requestInitialState()

        } catch {
            errorMessage = "Не удалось войти в комнату: \(error.localizedDescription)"
            Logger.ws.error("joinRoomFlow failed: \(error.localizedDescription)")
        }

        isJoining = false
    }

    // MARK: - Cleanup Flow (выход из комнаты)

    /// Безопасный выход: стоп sync, endCall, disconnect WS, REST leave.
    /// Идемпотентный (защита от двойного вызова из onDisappear + кнопки).
    func cleanupFlow() async {
        guard !didCleanup else { return }
        didCleanup = true

        syncEngine.cleanup()
        await voiceChat.endCall()
        wsClient.setActiveRoom(nil)
        wsClient.disconnect()

        do {
            try await roomService.leaveRoom(roomID: room.id)
        } catch {
            Logger.ws.warn("leaveRoom REST failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Restore

    /// Вызывается WebSocketClient после прозрачного реконнекта.
    private func handleSessionRestore() {
        Logger.ws.info("Сессия восстановлена — ресинхронизация")
        connectionStatus = .connected

        if syncEngine.currentMediaItem == nil, let mediaItem = room.mediaItem {
            syncEngine.loadMedia(mediaItem)
        }

        if !isHost {
            syncEngine.requestStateFromHost()
            syncEngine.startDriftMonitor()
        }
    }

    // MARK: - Chat

    func sendMessage() {
        let trimmed = chatText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // 🔧 FIX 3.3 (client-side): Don't send senderID/senderName in payload.
        // Server will inject them from JWT. Client sends only text + roomID.
        // This prevents identity spoofing even if client is compromised.
        let payload: [String: Any] = [
            "type": "chat",
            "roomID": room.id,
            "text": trimmed
            // senderID and senderName intentionally omitted — server adds from JWT
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            wsClient.send(json)
        }

        messages.append(ChatMessage(
            id: UUID().uuidString,
            roomID: room.id,
            senderID: currentUserId,
            senderName: "You",
            text: trimmed,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        ))
        chatText = ""
    }

    // MARK: - WebSocket Delegate
    //
    // 🔧 SWIFT 6: протокол WebSocketClientDelegate теперь @MainActor, поэтому
    // методы делегата тоже @MainActor. Раньше они были nonisolated с обёрткой
    // `Task { @MainActor }` — workaround под старый nonisolated протокол.
    // Теперь обёртки не нужны: RoomViewModel сам @MainActor, методы вызываются
    // напрямую на main actor.

    func webSocketDidConnect(_ client: any WebSocketClientProtocol) {
        guard !Task.isCancelled else { return }
        self.connectionStatus = .connected
        self.errorMessage = nil
        Logger.ws.info("Connected → room \(self.room.id)")

        // 🔧 DEBUG: log mediaItem state to diagnose why video doesn't load
        let mediaItemExists = self.room.mediaItem != nil
        let streamURL = self.room.mediaItem?.streamURL ?? "nil"
        let source = self.room.mediaItem?.source.rawValue ?? "nil"
        Logger.ws.info("🔍 room.mediaItem exists: \(mediaItemExists), streamURL: \(streamURL), source: \(source)")
        Logger.ws.info("🔍 syncEngine.currentMediaItem == nil: \(self.syncEngine.currentMediaItem == nil)")

        if let mediaItem = self.room.mediaItem, self.syncEngine.currentMediaItem == nil {
            Logger.ws.info("🔍 Calling syncEngine.loadMedia...")
            self.syncEngine.loadMedia(mediaItem)
            Logger.ws.info("🔍 After loadMedia, currentMediaItem == nil: \(self.syncEngine.currentMediaItem == nil)")
        } else {
            Logger.ws.warn("🔍 SKIP loadMedia: mediaItem=\(mediaItemExists), currentMediaItem nil=\(self.syncEngine.currentMediaItem == nil)")
        }
        if self.isHost {
            self.syncEngine.startStateBroadcast()
        } else {
            self.syncEngine.startDriftMonitor()
        }
    }

    func webSocketDidDisconnect(_ client: any WebSocketClientProtocol, reason: String?) {
        Logger.ws.error("Disconnected: \(reason ?? "unknown")")
        // WS сам реконнектится с exponential backoff; не показываем ошибку сразу.
        if self.connectionStatus != .reconnecting {
            self.connectionStatus = .reconnecting
        }
    }

    func webSocket(_ client: any WebSocketClientProtocol, didReceiveMessage message: String) {
        routeInbound(message)
    }

    func webSocket(_ client: any WebSocketClientProtocol, didReceiveError error: Error) {
        self.errorMessage = error.localizedDescription
    }

    // MARK: - Inbound Routing

    /// Маршрутизация входящих WS-сообщений по типу payload.
    /// 🔧 FIX M3: Was decoding every message up to 4 times via try? JSONDecoder
    /// chain — CPU waste on the hot path + mis-routing risk if fields overlap.
    /// Now peeks at a single discriminator field once, then dispatches.
    private func routeInbound(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }

        // 🔧 FIX: Single parse — extract type field, then decode once
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Try sync command first (has "command" field)
        if let cmd = json["command"] as? String {
            switch cmd {
            case "play", "pause", "seek", "correction", "stateRequest", "stateResponse", "changeMedia":
                if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
                    syncEngine.handleSyncMessage(syncMsg)
                    return
                }
            default: break
            }
        }

        // Try WebRTC signaling (has "kind" field)
        if let kind = json["kind"] as? String, SignalingMessage.Kind(rawValue: kind) != nil {
            if voiceChat.ingest(raw: raw) { return }
        }

        // Try chat (has "senderID" field)
        if json["senderID"] != nil || json["sender_id"] != nil {
            if let chatMsg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                messages.append(chatMsg)
                if messages.count > maxMessages {
                    messages.removeFirst(messages.count - maxMessages)
                }
                return
            }
        }

        // Try participant update (has "action" field)
        if json["action"] != nil {
            if let payload = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) {
                handleParticipantUpdate(payload)
                return
            }
        }

        // Try room closed (has "reason" field)
        if json["reason"] != nil {
            if let closed = try? JSONDecoder().decode(RoomClosedPayload.self, from: data) {
                errorMessage = "Хост завершил комнату."
                connectionStatus = .disconnected
                Logger.ws.info("Room closed: \(closed.reason)")
            }
        }
    }

    // MARK: - Participant Updates

    private func handleParticipantUpdate(_ payload: ParticipantUpdate) {
        if payload.action == "joined" {
            if !room.participants.contains(where: { $0.id == payload.userID }) {
                room.participants.append(UserPreview(
                    id: payload.userID, username: payload.username,
                    avatarURL: nil, isOnline: true
                ))
            }
        } else {
            room.participants.removeAll { $0.id == payload.userID }
        }
    }
}

// MARK: - WS Payloads (client-side decode helpers)

struct ParticipantUpdate: Decodable {
    let type: String          // "participant_joined" | "participant_left"
    let roomID: String
    let userID: String
    let username: String

    var action: String { type == "participant_joined" ? "joined" : "left" }
}

struct RoomClosedPayload: Decodable {
    let type: String          // "room_closed"
    let roomID: String
    let reason: String
}
