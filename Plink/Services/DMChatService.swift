import Foundation
import Combine

// MARK: - DM Chat Service v2 (Real API)
/// Личные сообщения через реальный бэкенд.
/// Отправка: POST /api/messages/dm
/// История: GET /api/messages/dm/:friendId
///
/// 🔧 FIX C4: Now accepts an authenticated APIClient via init (was: own unauth client).
/// 🔧 FIX C11: isOwnMessage compares against real currentUserId (was: "current_user").
@MainActor
final class DMChatService: ObservableObject {

    @Published private(set) var conversations: [String: [DirectMessage]] = [:]
    @Published private(set) var lastMessages: [Conversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    /// 🔧 FIX C4: Inject shared APIClient from RaveCloneApp
    init(api: APIClient) {
        self.api = api
    }

    private var currentUserId: String? {
        // Получаем ID текущего юзера из сохранённого профиля (non-secret)
        UserDefaults.standard.data(forKey: "rave_saved_user")
            .flatMap { try? JSONDecoder().decode(User.self, from: $0) }?.id
    }

    // MARK: - Load History (GET /api/messages/dm/:friendId)

    func loadHistory(friendId: String, friendName: String) async {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        guard api.authToken != nil else {
            print("[DM] loadHistory: no token")
            return
        }
        let convID = conversationID(with: friendId)
        isLoading = true
        defer { isLoading = false }

        do {
            let dtos: [DMMessageDTO] = try await api.request("messages/dm/\(friendId)")
            let me = currentUserId ?? "me"
            let messages = dtos.map { dto in
                DirectMessage(
                    id: dto.id,
                    conversationID: convID,
                    senderID: dto.senderID,
                    recipientID: dto.receiverID,
                    senderName: dto.senderID == me ? "You" : friendName,
                    text: dto.content,
                    timestamp: dto.createdAt,
                    isRead: dto.receiverID == me,
                    senderAvatarURL: nil
                )
            }
            conversations[convID] = messages
            print("[DM] history \(messages.count) msgs with \(friendId)")
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

        // Оптимистичное обновление UI
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
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        // Реальная отправка
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
                // Replace optimistic id with server id if possible
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
                }
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
        conversations[convID]?.append(message)
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
}
