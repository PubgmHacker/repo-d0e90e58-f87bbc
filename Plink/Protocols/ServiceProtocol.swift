import Foundation

// MARK: - Service Protocols
/// Единый файл контрактов. Все протоколы, управляющие UI-состоянием,
/// изолированы на @MainActor (iOS 17+ @Observable binding) и/или Sendable.

// MARK: - Auth Service Protocol
protocol AuthServiceProtocol: AnyObject, Sendable {
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String, username: String) async throws -> User
    func signOut() async throws
    func currentUser() async -> User?
    func deleteAccount() async throws
    /// 🔧 Pack v3: Synchronous access to current user (for hostName in room creation)
    var currentUserValue: User? { get }
    /// 🔧 Pack v3: Fetch fresh user data from server (GET /users/me)
    func fetchCurrentUser() async throws -> User
    /// 🔧 Pack v3: Update profile on server (PATCH /users/me)
    func updateProfile(username: String?, avatarURL: String?) async throws -> User
    /// 🔧 Pack v3: Update local cached user (after server update)
    func updateCachedUser(_ user: User)
}

// MARK: - Room Service Protocol
protocol RoomServiceProtocol: Sendable {
    func createRoom(_ request: CreateRoomRequest) async throws -> Room
    func joinRoom(code: String, password: String?) async throws -> Room
    func leaveRoom(roomID: String) async throws
    func fetchActiveRooms() async throws -> [Room]
    func fetchRoom(id: String) async throws -> Room
    func fetchMyRooms() async throws -> [Room]
    func deleteRoom(roomID: String) async throws
}

// MARK: - WebSocket Client Protocol
/// Сетевой транспорт. Реализация (`WebSocketClient`) изолирована на @MainActor,
/// но протокол оставлен nonisolated с синхронными fire-and-forget методами:
/// отправка ставит сообщение в очередь, приём уведомляет через delegate.
protocol WebSocketClientProtocol: AnyObject, Sendable {
    var delegate: WebSocketClientDelegate? { get set }

    func connect(to url: URL)
    func disconnect()
    func send(_ data: Data)
    func send(_ string: String)
    var isConnected: Bool { get }
}

protocol WebSocketClientDelegate: AnyObject {
    func webSocketDidConnect(_ client: any WebSocketClientProtocol)
    func webSocketDidDisconnect(_ client: any WebSocketClientProtocol, reason: String?)
    func webSocket(_ client: any WebSocketClientProtocol, didReceiveMessage message: String)
    func webSocket(_ client: any WebSocketClientProtocol, didReceiveError error: Error)
}

// MARK: - Voice Chat Service Protocol
/// Управляет UI-состоянием (isMuted, activePeers, isActive) → изолирован на @MainActor.
/// Строгие async-сигнатуры гарантируют безопасную интеграцию с @Observable ViewModels.
@MainActor
protocol VoiceChatServiceProtocol: AnyObject {

    // ── Published UI-состояние (только для чтения снаружи) ──
    var isMuted: Bool { get }
    var isActive: Bool { get }
    var activePeers: Set<String> { get }

    /// Колбэк изменения состояния микрофона участника.
    var onParticipantMutedChanged: ((String, Bool) -> Void)? { get set }

    // ── Жизненный цикл вызова ──────────────────────────────

    /// Запуск голосовой сессии в mesh-топологии.
    /// Инициализирует аудиосессию, подключает сигналинг, анонсирует `joinRoom`.
    /// Бросает при ошибке конфигурации AVAudioSession / WebRTC-фабрики.
    func startCall(roomId: String) async throws

    /// Безопасное завершение: закрывает все RTCPeerConnection,
    /// сбрасывает аудиосессию, отправляет `leaveRoom`.
    func endCall() async

    // ── Сигналинг ──────────────────────────────────────────

    /// Обработка входящего сигнального сообщения от бэкенда (SDP/ICE/join/leave).
    /// Бросает при ошибке применения SDP или добавления ICE-кандидата.
    func ingest(message: SignalingMessage) async throws

    /// Текстовый мост для raw WS-сообщений (маршрутизация из RoomViewModel).
    /// Возвращает `true`, если payload был сигнальным и обработан.
    @discardableResult
    func ingest(raw text: String) -> Bool

    // ── Управление микрофоном ──────────────────────────────

    /// Переключатель микрофона (mute/unmute).
    func toggleMute()
}
