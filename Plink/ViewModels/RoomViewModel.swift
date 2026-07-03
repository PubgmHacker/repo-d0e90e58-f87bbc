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
    private let currentUserId: String

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

        let payload = ChatPayload(type: "chat", roomID: room.id,
                                  senderID: currentUserId,
                                  senderName: "You", text: trimmed)
        if let data = try? JSONEncoder().encode(payload),
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

    nonisolated func webSocketDidConnect(_ client: any WebSocketClientProtocol) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connectionStatus = .connected
            self.errorMessage = nil
            Logger.ws.info("Connected → room \(self.room.id)")

            if let mediaItem = self.room.mediaItem, self.syncEngine.currentMediaItem == nil {
                self.syncEngine.loadMedia(mediaItem)
            }
            if self.isHost {
                self.syncEngine.startStateBroadcast()
            } else {
                self.syncEngine.startDriftMonitor()
            }
        }
    }

    nonisolated func webSocketDidDisconnect(_ client: any WebSocketClientProtocol, reason: String?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Logger.ws.error("Disconnected: \(reason ?? "unknown")")
            // WS сам реконнектится с exponential backoff; не показываем ошибку сразу.
            if self.connectionStatus != .reconnecting {
                self.connectionStatus = .reconnecting
            }
        }
    }

    nonisolated func webSocket(_ client: any WebSocketClientProtocol, didReceiveMessage message: String) {
        Task { @MainActor [weak self] in
            self?.routeInbound(message)
        }
    }

    nonisolated func webSocket(_ client: any WebSocketClientProtocol, didReceiveError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Inbound Routing

    /// Маршрутизация входящих WS-сообщений по типу payload.
    /// 🔧 FIX M3: Was decoding every message up to 4 times via try? JSONDecoder
    /// chain — CPU waste on the hot path + mis-routing risk if fields overlap.
    /// Now peeks at a single discriminator field once, then dispatches.
    private func routeInbound(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }

        // Peek at the JSON once to determine the message type
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // 1. WebRTC signaling (kind field) → VoiceChatService
        if let kind = jsonObject["kind"] as? String,
           SignalingMessage.Kind(rawValue: kind) != nil {
            if voiceChat.ingest(raw: raw) { return }
        }

        // 2. Sync command (command field) → SyncEngine
        if jsonObject["command"] != nil {
            if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
                syncEngine.handleSyncMessage(syncMsg)
                return
            }
        }

        // 3. Chat message (senderID + text fields) → messages array
        if jsonObject["senderID"] != nil || jsonObject["sender_id"] != nil {
            if let chatMsg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                messages.append(chatMsg)
                if messages.count > maxMessages {
                    messages.removeFirst(messages.count - maxMessages)
                }
                return
            }
        }

        // 4. Participant update (action + userID fields) → handleParticipantUpdate
        if jsonObject["action"] != nil, jsonObject["userID"] != nil || jsonObject["user_id"] != nil {
            if let payload = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) {
                handleParticipantUpdate(payload)
                return
            }
        }

        // 5. Room closed (reason field) → disconnect
        if jsonObject["reason"] != nil {
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
