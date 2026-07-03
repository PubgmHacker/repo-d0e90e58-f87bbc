import Foundation

// MARK: - Direct Message (личное сообщение между друзьями)
struct DirectMessage: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let senderName: String
    let text: String
    let timestamp: Date
    var isRead: Bool
    var senderAvatarURL: String?

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }

    var isOwnMessage: Bool {
        senderID == "current_user"
    }

    /// Премиум-статус отправителя — true для своих сообщений,
    /// когда текущий юзер премиум (проверяется через PremiumStatusManager).
    var isOwnPremium: Bool {
        guard isOwnMessage else { return false }
        return MainActor.assumeIsolated { PremiumStatusManager.shared.isPremium }
    }

    var initials: String {
        let parts = senderName.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return letters.map { String($0).uppercased() }.joined()
    }

    static func == (lhs: DirectMessage, rhs: DirectMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Conversation (личная переписка)
struct Conversation: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let participant: UserPreview
    let lastMessage: DirectMessage?
    let unreadCount: Int
    let updatedAt: Date

    var displayName: String {
        participant.username
    }

    var displayAvatar: String? {
        participant.avatarURL
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DM Payload (WebSocket outbound)
struct DMPayload: Codable, Sendable {
    let type: String             // "dm"
    let conversationID: String
    let senderID: String
    let recipientID: String
    let senderName: String
    let text: String
}
