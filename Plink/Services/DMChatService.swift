import Foundation
import Combine

// MARK: - DM Chat Service v3 (Real API + live poll)
/// Личные сообщения через реальный бэкенд.
/// Отправка: POST /api/messages/dm
/// История: GET /api/messages/dm/:friendId
@MainActor
final class DMChatService: ObservableObject {

    @Published private(set) var conversations: [String: [DirectMessage]] = [:]
    @Published private(set) var lastMessages: [Conversation] = []
    /// Bumps on every successful history load so SwiftUI re-renders even if count is stable.
    @Published private(set) var historyEpoch: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Prefer lightweight UserDefaults key (always written on login), then AuthService, then full user blob.
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

    // MARK: - Load History (GET /api/messages/dm/:friendId)

    func loadHistory(friendId: String, friendName: String, friendAvatarURL: String? = nil, quiet: Bool = false) async {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
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
                    isRead: dto.receiverID == me,
                    senderAvatarURL: isOwn ? nil : friendAvatarURL
                )
            }
            // Always replace + bump epoch so open chat reflects new remote messages
            conversations[convID] = messages
            historyEpoch &+= 1
            print("[DM] history \(messages.count) msgs with \(friendId) epoch=\(historyEpoch)")
        } catch {
            print("[DM] loadHistory error: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Messages

    func messages(for friendID: String) -> [DirectMessage] {
        let convID = conversationID(with: friendID)
        return conversations[convID] ?? []
    }

    // MARK: - Send Message (POST /api/messages/dm)

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
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        struct Body: Encodable { let receiverId: String; let content: String }
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
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
                // Pull full history so both sides stay aligned
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

    // MARK: - Receive (через WebSocket)

    func receiveMessage(_ message: DirectMessage, from friend: Friend) {
        let convID = conversationID(with: friend.id)
        if conversations[convID] == nil { conversations[convID] = [] }
        if conversations[convID]?.contains(where: { $0.id == message.id }) == true { return }
        conversations[convID]?.append(message)
        historyEpoch &+= 1
        updateLastMessage(conversationID: convID, friend: friend, message: message)
    }

    // MARK: - Helpers

    func conversationID(with friendID: String) -> String {
        let me = currentUserId ?? "me"
        let ids = [me, friendID].sorted()
        return "dm_\(ids.joined(separator: "_"))"
    }

    private func updateLastMessage(conversationID: String, friend: Friend, message: DirectMessage) {
        let conv = Conversation(
            id: conversationID,
            participant: UserPreview(id: friend.id, username: friend.username, avatarURL: friend.avatarURL, isOnline: friend.isOnline),
            lastMessage: message,
            unreadCount: 0,
            updatedAt: message.timestamp
        )
        lastMessages.removeAll { $0.id == conversationID }
        lastMessages.insert(conv, at: 0)
    }
}

// MARK: - DTO

private struct DMMessageDTO: Decodable {
    let id: String
    let senderID: String
    let receiverID: String
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt
        case senderID
        case receiverID
        case senderId
        case receiverId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
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
