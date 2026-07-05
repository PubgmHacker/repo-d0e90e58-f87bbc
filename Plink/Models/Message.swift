import Foundation

// MARK: - Chat Message
struct ChatMessage: Codable, Identifiable, Sendable {
    let id: String
    let roomID: String
    let senderID: String
    let senderName: String
    let text: String
    let timestamp: Date
    var isRead: Bool
    var senderAvatarURL: String?
    /// 🔧 Pack v3: Role of sender (USER/MODERATOR/ADMIN/FOUNDER) — для подсветки админов
    var senderRole: String?

    /// 🔧 FIX: Custom CodingKeys — backend sends camelCase, but some fields
    /// might come as snake_case from older code. Also handle missing isRead
    /// (backend doesn't send it — default to false).
    enum CodingKeys: String, CodingKey {
        case id, roomID, senderID, senderName, text, timestamp
        case isRead = "is_read"  // backend doesn't send this — decodeIfPresent
        case senderAvatarURL, senderRole
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        roomID = try c.decode(String.self, forKey: .roomID)
        senderID = try c.decode(String.self, forKey: .senderID)
        senderName = try c.decode(String.self, forKey: .senderName)
        text = try c.decode(String.self, forKey: .text)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        senderAvatarURL = try c.decodeIfPresent(String.self, forKey: .senderAvatarURL)
        senderRole = try c.decodeIfPresent(String.self, forKey: .senderRole)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roomID, forKey: .roomID)
        try c.encode(senderID, forKey: .senderID)
        try c.encode(senderName, forKey: .senderName)
        try c.encode(text, forKey: .text)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(isRead, forKey: .isRead)
        try c.encodeIfPresent(senderAvatarURL, forKey: .senderAvatarURL)
        try c.encodeIfPresent(senderRole, forKey: .senderRole)
    }

    // 🔧 Direct init for local messages
    init(id: String, roomID: String, senderID: String, senderName: String,
         text: String, timestamp: Date, isRead: Bool,
         senderAvatarURL: String?, senderRole: String? = nil) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        self.senderAvatarURL = senderAvatarURL
        self.senderRole = senderRole
    }

    /// 🔧 Pack v3: True если отправитель — админ
    var isSenderAdmin: Bool {
        (senderRole ?? "").uppercased() == "ADMIN" || (senderRole ?? "").uppercased() == "FOUNDER"
    }

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }

    /// Первые инициалы имени для fallback-аватарки
    var initials: String {
        let parts = senderName.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return letters.map { String($0).uppercased() }.joined()
    }

    static var preview: ChatMessage {
        ChatMessage(
            id: "msg_001",
            roomID: "room_001",
            senderID: "user_001",
            senderName: "Alex",
            text: "This is awesome! 🎬",
            timestamp: .now.addingTimeInterval(-120),
            isRead: true,
            senderAvatarURL: nil
        )
    }
}

// MARK: - System Message (join/leave notifications)
struct SystemMessage: Identifiable, Sendable {
    let id = UUID().uuidString
    let roomID: String
    let text: String
    let timestamp: Date

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }
}

// MARK: - Chat Payload (WebSocket outbound)
/// Сетевая структура для отправки текстовых сообщений через WebSocket.
/// JSON-схема совпадает с бэкенд-типом `ChatPayload` (server/src/types/index.ts):
///   { type, roomID, senderID, senderName, text }
struct ChatPayload: Codable, Sendable {
    let type: String          // всегда "chat"
    let roomID: String
    let senderID: String
    let senderName: String
    let text: String
}
