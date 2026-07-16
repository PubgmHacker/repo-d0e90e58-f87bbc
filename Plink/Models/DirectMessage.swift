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

    /// Own vs other — prefer lightweight id key (always set on login).
    /// Uses only UserDefaults so this stays nonisolated / Sendable-safe.
    var isOwnMessage: Bool {
        if let id = UserDefaults.standard.string(forKey: "plink_current_user_id"), !id.isEmpty {
            return senderID == id
        }
        guard let data = UserDefaults.standard.data(forKey: "rave_saved_user"),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return false
        }
        return senderID == user.id
    }

    /// Премиум-статус отправителя — true для своих сообщений,
    /// когда текущий юзер премиум (проверяется через PremiumStatusManager).
    /// 🔧 FIX N3 (NEW): Replaced MainActor.assumeIsolated with a thread-safe check.
    @MainActor
    var isOwnPremium: Bool {
        guard isOwnMessage else { return false }
        return PremiumStatusManager.shared.isPremium
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
