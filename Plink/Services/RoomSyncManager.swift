import Foundation
import Combine
import UIKit

// MARK: - Room Sync Manager (Блок 5 + Блок 1 UGC)
/// Менеджер состояния комнаты на базе WebSocket.
///
/// Обрабатывает события:
/// - "user_joined" / "user_left" — обновление списка участников.
/// - "media_play" / "media_pause" / "media_seek" — синхронизация плеера
///   (использует существующие `SyncCommand`/`SyncMessage` из SyncState.swift).
///   Если локальный плеер отстаёт от хоста > 1 сек — плавная коррекция.
/// - "send_reaction" — реакции (Блок 3).
/// - "chat" — сообщения чата (Блок 2).
///
/// UGC-оптимизация (Блок 1):
/// - Автоочистка чата: хранится не более 200 сообщений (экономия RAM).
/// - Реакции удаляются строго через 2 секунды.
/// - Background-handling: при сворачивании приложения — reconnect + sync таймкода.
///
/// Thin-слой над существующим `WebSocketClient`: парсит входящие пакеты
/// и диспатчит события через `@Published` свойства и callbacks.
@MainActor
final class RoomSyncManager: ObservableObject {

    // MARK: - Config

    /// Максимальное количество сообщений в памяти (экономия RAM, требование Apple).
    private let maxChatMessages = 200

    /// Время жизни реакции в секундах (строго 2 сек по спеке Блока 3).
    private let reactionLifetime: TimeInterval = 2.0

    // MARK: - Published State

    /// Текущий список участников комнаты.
    @Published private(set) var participants: [UserPreview] = []

    /// Активные реакции (для оверлея-анимации, Блок 3).
    @Published private(set) var activeReactions: [ReactionEvent] = []

    /// Чат-сообщения комнаты (фильтрованные от заблокированных юзеров).
    @Published private(set) var chatMessages: [ChatMessage] = []

    /// Статус соединения.
    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Sync State

    /// Последняя позиция плеера хоста (для коррекции рассинхрона).
    @Published private(set) var lastHostPosition: TimeInterval?

    /// Флаг: нужен ли плавный seek для выравнивания (> 1 сек рассинхрона).
    @Published private(set) var needsCorrection: Bool = false

    // MARK: - Callbacks

    /// Вызывается при получении медиа-команд.
    var onPlayCommand: ((TimeInterval) -> Void)?
    var onPauseCommand: ((TimeInterval) -> Void)?
    var onSeekCommand: ((TimeInterval) -> Void)?
    var onReactionReceived: (() -> Void)?

    /// Запрос текущего таймкода при возвращении из background (для resync).
    var onResyncRequested: (() -> Void)?

    // MARK: - Dependencies

    private let wsClient: WebSocketClient
    private let roomID: String
    private let blockManager: UserBlockManager

    /// Все сообщения (до фильтрации) — нужно для перерисовки при блокировке.
    private var allChatMessages: [ChatMessage] = []

    // MARK: - Background Handling

    private var backgroundTask: UIBackgroundTaskIdentifier?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var didDisconnectInBackground = false

    // MARK: - Thresholds

    /// Максимально допустимое расхождение таймкода (сек) до принудительной коррекции.
    private let syncThreshold: TimeInterval = 1.0

    // MARK: - Init

    init(wsClient: WebSocketClient, roomID: String, blockManager: UserBlockManager? = nil) {
        self.wsClient = wsClient
        self.roomID = roomID
        self.blockManager = blockManager ?? UserBlockManager()
        // 🔧 FIX M14: Reset stale background-disconnect flag on init — if the OS
        // killed the app while in background, didDisconnectInBackground would stay
        // true on the next launch, leaving connectionStatus stuck at .reconnecting.
        self.didDisconnectInBackground = false

        setupBackgroundObservers()
    }

    // MARK: - Connection Lifecycle

    func connect() {
        wsClient.delegate = self
        wsClient.connectToServer(roomID: roomID)
        connectionStatus = .connecting
    }

    func disconnect() {
        removeBackgroundObservers()
        wsClient.disconnect()
        connectionStatus = .disconnected
    }

    // MARK: - Outbound: Sync Commands

    /// Отправляет команду медиа на сервер (когда локальный юзер — хост).
    func sendMediaCommand(_ command: SyncCommand, position: TimeInterval, senderId: String) {
        let message = SyncMessage(
            command: command,
            roomID: roomID,
            senderID: senderId,
            mediaTime: position,
            timestamp: Date().timeIntervalSince1970
        )
        sendCodable(message)
    }

    // MARK: - Outbound: Reaction (Блок 3)

    func sendReaction(emoji: String, senderId: String, senderName: String) {
        let payload = ReactionPayload(
            emoji: emoji,
            roomId: roomID,
            senderId: senderId,
            senderName: senderName
        )
        sendCodable(payload)

        // Локально тоже показываем реакцию сразу (не ждём эха сервера).
        addReaction(ReactionEvent(emoji: emoji, senderName: senderName))
    }

    // MARK: - Outbound: Chat (Блок 2)

    func sendChatMessage(_ message: ChatMessage) {
        appendChatMessage(message)
        sendCodable(ChatPayload(
            type: "chat",
            roomID: message.roomID,
            senderID: message.senderID,
            senderName: message.senderName,
            text: message.text
        ))
    }

    // MARK: - Block Manager Access (для контекстного меню)

    func blockUser(_ userId: String) {
        blockManager.blockUser(userId)
        refreshFilteredMessages()
    }

    func isUserBlocked(_ userId: String) -> Bool {
        blockManager.isBlocked(userId)
    }

    // MARK: - Raw WS Send (для ad commands и др.)

    /// Отправка сырой JSON-строки через WebSocket (для ad commands и др.).
    func sendRaw(_ json: String) {
        wsClient.send(json)
    }

    // MARK: - Ad Command (Блок 2 — синхронизированная реклама)

    /// Рассылка рекламной команды участникам через WS.
    func sendAdCommand(_ command: AdRoomCommand, roomID: String) {
        let payload = AdCommandPayload(command: command, roomID: roomID)
        if let data = try? JSONEncoder().encode(payload),
           let json = String(data: data, encoding: .utf8) {
            wsClient.send(json)
        }
    }

    /// Получение рекламной команды от хоста через WS.
    func handleAdCommand(_ payload: AdCommandPayload) {
        // Делегируется в RoomView через callback.
        onAdCommandReceived?(payload.command)
    }

    /// Callback для получения рекламных команд.
    var onAdCommandReceived: ((AdRoomCommand) -> Void)?

    // MARK: - Incoming Event Handling

    /// Главная точка обработки входящих WS-пакетов.
    func handleRawMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Игнорируем ping/pong (обрабатываются в WebSocketClient).
        if let pingPong = try? JSONDecoder().decode(WSPingPong.self, from: data) {
            if pingPong.command == "ping" || pingPong.command == "pong" { return }
        }

        // 0. Ad Command (Блок 2 — синхронизированная реклама).
        if let adCmd = try? JSONDecoder().decode(AdCommandPayload.self, from: data) {
            handleAdCommand(adCmd)
            return
        }

        // 1. Пробуем разобрать как SyncMessage (существующий протокол синхронизации).
        if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
            handleSyncMessage(syncMsg)
            return
        }

        // 2. Пробуем универсальный конверт (реакции, чат, участники).
        guard let envelope = try? JSONDecoder().decode(RoomEventEnvelope.self, from: data) else {
            return
        }

        handleEnvelope(envelope)
    }

    // MARK: - SyncMessage Routing

    private func handleSyncMessage(_ msg: SyncMessage) {
        let position = msg.mediaTime ?? 0

        switch msg.command {
        case .play:
            lastHostPosition = position
            onPlayCommand?(position)

        case .pause:
            lastHostPosition = position
            onPauseCommand?(position)

        case .seek:
            lastHostPosition = position
            onSeekCommand?(position)

        case .correction:
            needsCorrection = true
            onSeekCommand?(position)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                needsCorrection = false
            }

        case .stateRequest, .stateResponse, .changeMedia, .ping, .pong:
            break
        }
    }

    // MARK: - Envelope Routing

    private func handleEnvelope(_ envelope: RoomEventEnvelope) {
        switch envelope.type {
        case "user_joined":
            guard let userId = envelope.userId, let username = envelope.username else { return }
            let user = UserPreview(
                id: userId,
                username: username,
                avatarURL: envelope.avatarURL,
                isOnline: envelope.isOnline ?? true
            )
            if !participants.contains(where: { $0.id == user.id }) {
                participants.append(user)
            }

        case "user_left":
            if let userId = envelope.userId {
                participants.removeAll { $0.id == userId }
            }

        case "send_reaction", "reaction":
            guard let emoji = envelope.emoji else { return }
            // Фильтруем реакции от заблокированных юзеров.
            if let senderId = envelope.senderId, blockManager.isBlocked(senderId) {
                return
            }
            addReaction(ReactionEvent(emoji: emoji, senderName: envelope.senderName))

        case "chat":
            guard let roomId = envelope.roomId,
                  let senderId = envelope.senderId,
                  let senderName = envelope.senderName,
                  let text = envelope.text else { return }
            // Фильтруем сообщения от заблокированных юзеров — не сохраняем вообще.
            if blockManager.isBlocked(senderId) { return }
            let message = ChatMessage(
                id: UUID().uuidString,
                roomID: roomId,
                senderID: senderId,
                senderName: senderName,
                text: text,
                timestamp: Date(),
                isRead: false,
                senderAvatarURL: nil
            )
            appendChatMessage(message)

        default:
            break
        }
    }

    // MARK: - Chat Memory Management (Блок 1 — автоочистка)

    /// Добавляет сообщение и поддерживает лимит в 200 записей.
    private func appendChatMessage(_ message: ChatMessage) {
        allChatMessages.append(message)

        // Жёсткий лимит — удаляем самые старые.
        if allChatMessages.count > maxChatMessages {
            let excess = allChatMessages.count - maxChatMessages
            allChatMessages.removeFirst(excess)
        }

        refreshFilteredMessages()
    }

    /// Перестраивает published-список с учётом текущих блокировок.
    private func refreshFilteredMessages() {
        chatMessages = blockManager.filterMessages(allChatMessages)
    }

    // MARK: - Drift Check

    /// Вызывается RoomViewModel'ю с актуальным локальным таймкодом.
    /// Возвращает `true`, если нужна коррекция (расхождение > threshold).
    func checkDrift(localPosition: TimeInterval) -> Bool {
        guard let hostPosition = lastHostPosition else { return false }
        let drift = abs(localPosition - hostPosition)
        let shouldCorrect = drift > syncThreshold
        needsCorrection = shouldCorrect
        return shouldCorrect
    }

    // MARK: - Reactions Lifecycle (Блок 3 — автоудаление через 2 сек)

    private func addReaction(_ reaction: ReactionEvent) {
        activeReactions.append(reaction)
        onReactionReceived?()

        // Строгое автоудаление через reactionLifetime секунд (экономия памяти).
        let reactionId = reaction.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.reactionLifetime ?? 2.0) * 1_000_000_000)
            self?.activeReactions.removeAll { $0.id == reactionId }
        }
    }

    // MARK: - Background Handling (Блок 1 — авто-восстановление сессии)

    private func setupBackgroundObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppBackground()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppForeground()
        }
    }

    private func removeBackgroundObservers() {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        endBackgroundTask()
    }

    /// При сворачивании: оставляем WS-соединение (background task),
    /// но отключаемся через 30 сек если пользователь не вернулся (экономия батареи).
    private func handleAppBackground() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PlinkRoomKeepalive") { [weak self] in
            self?.endBackgroundTask()
        }

        // Через 30 сек — отключаем WS если приложение всё ещё в фоне.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.backgroundTask != nil else { return }
            self.didDisconnectInBackground = true
            self.wsClient.disconnect()
        }
    }

    /// При возвращении в foreground: переподключаемся и запрашиваем resync.
    private func handleAppForeground() {
        endBackgroundTask()

        if didDisconnectInBackground {
            didDisconnectInBackground = false
            connectionStatus = .reconnecting
            // Переподключаемся к комнате.
            connect()
        }

        // Запрашиваем актуальный таймкод хоста (могли пропустить play/seek в фоне).
        onResyncRequested?()
    }

    private func endBackgroundTask() {
        if let task = backgroundTask, task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
        }
        backgroundTask = nil
    }

    // MARK: - Helpers

    private func sendCodable<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return }
        wsClient.send(string)
    }

    // MARK: - Connection Status

    enum ConnectionStatus: Equatable, Sendable {
        case connected
        case connecting
        case reconnecting
        case disconnected
    }
}

// MARK: - Ad Command Payload (WS — Блок 2)
struct AdCommandPayload: Codable, Sendable {
    let command: AdRoomCommand
    let roomID: String
}

// MARK: - WebSocketClientDelegate
extension RoomSyncManager: WebSocketClientDelegate {
    nonisolated func webSocketDidConnect(_ client: any WebSocketClientProtocol) {
        Task { @MainActor in
            connectionStatus = .connected
        }
    }

    nonisolated func webSocketDidDisconnect(_ client: any WebSocketClientProtocol, reason: String?) {
        Task { @MainActor in
            connectionStatus = .reconnecting
        }
    }

    nonisolated func webSocket(_ client: any WebSocketClientProtocol, didReceiveMessage message: String) {
        Task { @MainActor in
            handleRawMessage(message)
        }
    }

    nonisolated func webSocket(_ client: any WebSocketClientProtocol, didReceiveError error: Error) {
        Task { @MainActor in
            connectionStatus = .reconnecting
        }
    }
}
