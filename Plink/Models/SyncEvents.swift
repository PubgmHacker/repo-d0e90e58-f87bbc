import Foundation
import CoreGraphics

// MARK: - WebSocket Event Models (Блоки 2–5)
/// Дополнительные сетевые структуры для room-событий, которых нет в SyncState.swift:
/// реакции и универсальный конверт входящих WS-пакетов.
///
/// Для команд синхронизации плеера используются существующие типы
/// `SyncCommand` (enum) и `SyncMessage` (struct) из `SyncState.swift`.

// MARK: - Reaction Payload (Блок 3 — быстрые реакции)
/// Клиент → Сервер: { action: "send_reaction", emoji: "🔥", room_id: "X" }
struct ReactionPayload: Codable, Sendable {
    let action: String       // "send_reaction"
    let emoji: String
    let roomId: String
    let senderId: String?
    let senderName: String?

    init(emoji: String, roomId: String, senderId: String?, senderName: String?) {
        self.action = "send_reaction"
        self.emoji = emoji
        self.roomId = roomId
        self.senderId = senderId
        self.senderName = senderName
    }
}

// MARK: - Incoming Reaction Event (от любого пользователя)
/// Используется ReactionOverlay для запуска анимации.
struct ReactionEvent: Identifiable, Sendable {
    let id = UUID()
    let emoji: String
    let senderName: String?

    /// Случайное горизонтальное смещение (в pts) — каждое эмодзи летит своим путём.
    let horizontalOffset: CGFloat

    init(emoji: String, senderName: String?) {
        self.emoji = emoji
        self.senderName = senderName
        self.horizontalOffset = CGFloat.random(in: -80...80)
    }
}

// MARK: - Room Event Envelope (входящий WS-пакет)
/// Универсальный конверт для разбора входящих событий комнаты.
/// Не конфликтует с SyncMessage — это вспомогательная структура только для парсинга.
struct RoomEventEnvelope: Codable, Sendable {
    let type: String
    let roomId: String?
    let userId: String?
    let username: String?
    let avatarURL: String?
    let isOnline: Bool?
    let position: TimeInterval?
    let serverTimestamp: TimeInterval?
    let emoji: String?
    let senderId: String?
    let senderName: String?
    let text: String?
}
