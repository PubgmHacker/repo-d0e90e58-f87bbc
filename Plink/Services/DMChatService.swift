import Foundation
import Combine

// MARK: - DM Chat Service v4 (history + unread badges)
/// Личные сообщения + счётчик непрочитанных для списка «Чаты».
@MainActor
final class DMChatService: ObservableObject {

    /// Shared instance so friends list badges and open chat share state.
    static let shared = DMChatService(api: APIClient.shared)

    @Published private(set) var conversations: [String: [DirectMessage]] = [:]
    @Published private(set) var lastMessages: [Conversation] = []
    /// friendId → unread count (only when user is NOT in that chat)
    @Published private(set) var unreadByFriend: [String: Int] = [:]
    /// friendId → last message preview (for list subtitle)
    @Published private(set) var lastPreviewByFriend: [String: String] = [:]
    @Published private(set) var historyEpoch: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Currently open DM friend id — unread for this id stays 0 while open.
    private(set) var openFriendId: String?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var currentUserId: String? {
        if let id = UserDefaults.standard.string(forKey: "plink_current_user_id"), !id.isEmpty {
            return id
        }
        if let id = AuthService.shared.currentUserValue?.id, !id.isEmpty {
            return id
        }
        return UserDefaults.standard.data(forKey: "rave_saved_user")
            .flatMap { try? JSONDecoder().decode(User.self, from: $0) }?.id
    }

    var totalUnread: Int {
        unreadByFriend.values.reduce(0, +)
    }

    func unreadCount(for friendId: String) -> Int {
        if openFriendId == friendId { return 0 }
        return unreadByFriend[friendId] ?? 0
    }

    // MARK: - Open / close chat (drives badge zeroing)

    func chatDidOpen(friendId: String) {
        openFriendId = friendId
        // Optimistic clear
        if unreadByFriend[friendId] != nil {
            unreadByFriend[friendId] = 0
            unreadByFriend = unreadByFriend.filter { $0.value > 0 }
        }
    }

    func chatDidClose(friendId: String) {
        if openFriendId == friendId {
            openFriendId = nil
        }
        Task { await refreshUnread() }
    }

    // MARK: - Unread summary (GET /messages/unread)

    func refreshUnread() async {
        ensureToken()
        guard api.authToken != nil else { return }
        do {
            let items: [UnreadDTO] = try await api.request("messages/unread")
            var counts: [String: Int] = [:]
            var previews: [String: String] = [:]
            for item in items {
                if openFriendId == item.friendId {
                    counts[item.friendId] = 0
                } else {
                    counts[item.friendId] = item.unreadCount
                }
                if let p = item.lastPreview, !p.isEmpty {
                    previews[item.friendId] = p
                }
            }
            unreadByFriend = counts.filter { $0.value > 0 }
            // Keep previews for friends with unread; merge
            for (k, v) in previews {
                lastPreviewByFriend[k] = v
            }
            print("[DM] unread total=\(totalUnread) friends=\(unreadByFriend.count)")
        } catch {
            print("[DM] refreshUnread error: \(error.localizedDescription)")
        }
    }

    // MARK: - Load History (GET /api/messages/dm/:friendId)

    func loadHistory(friendId: String, friendName: String, friendAvatarURL: String? = nil, quiet: Bool = false) async {
        ensureToken()
        guard api.authToken != nil else {
            print("[DM] loadHistory: no token")
            return
        }
        let convID = conversationID(with: friendId)
        if !quiet {
            isLoading = true
        }
        defer { if !quiet { isLoading = false } }

        do {
            let dtos: [DMMessageDTO] = try await api.request("messages/dm/\(friendId)")
            // Server marks inbound as read on this GET
            if openFriendId == friendId {
                unreadByFriend[friendId] = nil
                unreadByFriend = unreadByFriend.filter { $0.value > 0 }
            }
            let me = currentUserId ?? ""
            let messages = dtos.map { dto -> DirectMessage in
                let isOwn = !me.isEmpty && dto.senderID == me
                return DirectMessage(
                    id: dto.id,
                    conversationID: convID,
                    senderID: dto.senderID,
                    recipientID: dto.receiverID,
                    senderName: isOwn ? "You" : friendName,
                    text: dto.content,
                    timestamp: dto.createdAt,
                    isRead: dto.isRead ?? (dto.receiverID == me),
                    senderAvatarURL: isOwn ? nil : friendAvatarURL
                )
            }
            conversations[convID] = messages
            historyEpoch &+= 1
            if let last = messages.last {
                lastPreviewByFriend[friendId] = last.text
            }
            print("[DM] history \(messages.count) msgs with \(friendId)")
        } catch {
            print("[DM] loadHistory error: \(error.localizedDescription)")
        }
    }

    func messages(for friendID: String) -> [DirectMessage] {
        let convID = conversationID(with: friendID)
        return conversations[convID] ?? []
    }

    // MARK: - Send

    func sendMessage(_ text: String, to friend: Friend) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let convID = conversationID(with: friend.id)
        let me = currentUserId ?? "me"

        let message = DirectMessage(
            id: UUID().uuidString,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: trimmed,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )

        if conversations[convID] == nil { conversations[convID] = [] }
        conversations[convID]?.append(message)
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = trimmed
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        struct Body: Encodable { let receiverId: String; let content: String }
        ensureToken()
        Task {
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm",
                    method: .post,
                    body: Body(receiverId: friend.id, content: trimmed)
                )
                if let idx = conversations[convID]?.firstIndex(where: { $0.id == message.id }) {
                    var list = conversations[convID] ?? []
                    list[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID,
                        recipientID: saved.receiverID,
                        senderName: "You",
                        text: saved.content,
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil
                    )
                    conversations[convID] = list
                    historyEpoch &+= 1
                }
                await loadHistory(
                    friendId: friend.id,
                    friendName: friend.username,
                    friendAvatarURL: friend.avatarURL,
                    quiet: true
                )
            } catch {
                errorMessage = error.localizedDescription
                print("[DM] sendMessage error: \(error.localizedDescription)")
            }
        }
    }

    func receiveMessage(_ message: DirectMessage, from friend: Friend) {
        let convID = conversationID(with: friend.id)
        if conversations[convID] == nil { conversations[convID] = [] }
        if conversations[convID]?.contains(where: { $0.id == message.id }) == true { return }
        conversations[convID]?.append(message)
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = message.text
        updateLastMessage(conversationID: convID, friend: friend, message: message)
        if openFriendId != friend.id, message.senderID != currentUserId {
            unreadByFriend[friend.id, default: 0] += 1
        }
    }

    // MARK: - Helpers

    func conversationID(with friendID: String) -> String {
        let me = currentUserId ?? "me"
        let ids = [me, friendID].sorted()
        return "dm_\(ids.joined(separator: "_"))"
    }

    private func ensureToken() {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
    }

    private func updateLastMessage(conversationID: String, friend: Friend, message: DirectMessage) {
        let conv = Conversation(
            id: conversationID,
            participant: UserPreview(id: friend.id, username: friend.username, avatarURL: friend.avatarURL, isOnline: friend.isOnline),
            lastMessage: message,
            unreadCount: unreadCount(for: friend.id),
            updatedAt: message.timestamp
        )
        lastMessages.removeAll { $0.id == conversationID }
        lastMessages.insert(conv, at: 0)
    }
}

// MARK: - DTOs

private struct UnreadDTO: Decodable {
    let friendId: String
    let unreadCount: Int
    let lastPreview: String?
    let lastAt: Date?
}

private struct DMMessageDTO: Decodable {
    let id: String
    let senderID: String
    let receiverID: String
    let content: String
    let createdAt: Date
    let isRead: Bool?

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, isRead
        case senderID, receiverID
        case senderId, receiverId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead)
        if let s = try c.decodeIfPresent(String.self, forKey: .senderID) {
            senderID = s
        } else {
            senderID = try c.decode(String.self, forKey: .senderId)
        }
        if let r = try c.decodeIfPresent(String.self, forKey: .receiverID) {
            receiverID = r
        } else {
            receiverID = try c.decode(String.self, forKey: .receiverId)
        }
    }
}
