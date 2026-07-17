import Foundation

// MARK: - Direct Message (личное сообщение между друзьями)
/// Aggregated reaction chip on a DM (Telegram-style).
struct DMReactionChip: Codable, Sendable, Equatable, Hashable {
    let emoji: String
    let count: Int
    let includesMe: Bool
}

struct DirectMessage: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let senderName: String
    let text: String
    let timestamp: Date
    var isRead: Bool
    var senderAvatarURL: String?
    /// Sender's bubble style (synced via wire format). Renders for all viewers.
    var bubbleStyle: String?
    /// Telegram-style reaction chips.
    var reactions: [DMReactionChip]

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }

    init(
        id: String,
        conversationID: String,
        senderID: String,
        recipientID: String,
        senderName: String,
        text: String,
        timestamp: Date,
        isRead: Bool,
        senderAvatarURL: String? = nil,
        bubbleStyle: String? = nil,
        reactions: [DMReactionChip] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.recipientID = recipientID
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        self.senderAvatarURL = senderAvatarURL
        self.bubbleStyle = bubbleStyle
        self.reactions = reactions
    }

    /// Own vs other — prefer lightweight id key (always set on login).
    /// Uses only UserDefaults so this stays nonisolated / Sendable-safe.
    var isOwnMessage: Bool {
        isFromCurrentUser(currentUserId: nil)
    }

    /// Prefer explicit currentUserId from UI (more reliable than UD race).
    func isFromCurrentUser(currentUserId: String?) -> Bool {
        if let currentUserId, !currentUserId.isEmpty {
            return senderID == currentUserId
        }
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
        PlinkAvatarURL.letter(from: senderName)
    }

    static func == (lhs: DirectMessage, rhs: DirectMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.reactions == rhs.reactions
            && lhs.bubbleStyle == rhs.bubbleStyle
            && lhs.isRead == rhs.isRead
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
