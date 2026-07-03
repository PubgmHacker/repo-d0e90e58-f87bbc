import Foundation
import Combine

// MARK: - Friend Manager v2 (Real API)
/// Менеджер друзей через реальный бэкенд Railway.
/// Все методы делают HTTP-запросы к /api/friends/*.
@MainActor
final class FriendManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var outgoingRequests: [FriendRequest] = []
    @Published private(set) var searchResults: [UserPreview] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Callbacks

    var onIncomingRequest: ((FriendRequest) -> Void)?
    var onFriendAdded: ((Friend) -> Void)?

    // MARK: - API

    private let api = APIClient()

    init() {
        // Загружаем данные при создании (если есть токен)
        Task { await loadAll() }
    }

    // MARK: - Load All

    func loadAll() async {
        await loadFriends()
        await loadRequests()
    }

    // MARK: - Load Friends (GET /api/friends)

    func loadFriends() async {
        guard api.authToken != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let dtos: [FriendDTO] = try await api.request("friends")
            friends = dtos.map { $0.toFriend() }
        } catch {
            print("[Friends] loadFriends error: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Requests (GET /api/friends/requests/incoming)

    func loadRequests() async {
        guard api.authToken != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let dtos: [FriendRequestDTO] = try await api.request("friends/requests/incoming")
            incomingRequests = dtos.map { $0.toFriendRequest() }
        } catch {
            print("[Friends] loadRequests error: \(error.localizedDescription)")
        }
    }

    // MARK: - Send Request (POST /api/friends/request)

    func sendRequest(to userId: String, username: String) async {
        struct Body: Encodable { let friendId: String }

        do {
            let _: FriendRequestDTO = try await api.request("friends/request", method: .post, body: Body(friendId: userId))
            // Обновляем список после отправки
            await loadRequests()
        } catch {
            errorMessage = error.localizedDescription
            print("[Friends] sendRequest error: \(error.localizedDescription)")
        }
    }

    // MARK: - Accept Request (PUT /api/friends/requests/:id)

    func acceptRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }

        do {
            let _: SuccessDTO = try await api.request("friends/requests/\(request.id)", method: .put, body: Body(status: "accepted"))
            incomingRequests.removeAll { $0.id == request.id }

            let newFriend = Friend(
                id: request.fromUser.id,
                username: request.fromUser.username,
                avatarURL: request.fromUser.avatarURL,
                isOnline: request.fromUser.isOnline,
                friendsSince: Date()
            )
            friends.append(newFriend)
            onFriendAdded?(newFriend)
        } catch {
            errorMessage = error.localizedDescription
            print("[Friends] acceptRequest error: \(error.localizedDescription)")
        }
    }

    // MARK: - Decline Request (PUT /api/friends/requests/:id)

    func declineRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }

        do {
            let _: SuccessDTO = try await api.request("friends/requests/\(request.id)", method: .put, body: Body(status: "rejected"))
            incomingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
            print("[Friends] declineRequest error: \(error.localizedDescription)")
        }
    }

    // MARK: - Remove Friend (DELETE /api/friends/:friendId)

    func removeFriend(_ friend: Friend) async {
        do {
            try await api.requestNoBody("friends/\(friend.id)", method: .delete)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
            print("[Friends] removeFriend error: \(error.localizedDescription)")
        }
    }

    // MARK: - Search (GET /api/friends/search?q=)

    func searchUsers(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        guard api.authToken != nil else {
            searchResults = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let dtos: [UserPreviewDTO] = try await api.request("friends/search", query: ["q": trimmed])
            searchResults = dtos.map { $0.toUserPreview() }
        } catch {
            print("[Friends] search error: \(error.localizedDescription)")
            searchResults = []
        }
    }

    // MARK: - Helpers

    func isFriend(_ userId: String) -> Bool {
        friends.contains { $0.id == userId }
    }

    func hasOutgoingRequest(to userId: String) -> Bool {
        outgoingRequests.contains { $0.toUser.id == userId }
    }

    // MARK: - Invite Link

    func generateInviteLink(userId: String) -> URL {
        URL(string: "\(ShareManager.shareBaseURL)/u/\(userId)")!
    }
}

// MARK: - DTO Models (server response)

private struct FriendDTO: Decodable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool?
    let lastSeen: Date?
    let friendsSince: Date?

    func toFriend() -> Friend {
        Friend(
            id: id,
            username: username,
            avatarURL: avatarURL,
            isOnline: isOnline ?? false,
            friendsSince: friendsSince ?? Date()
        )
    }
}

private struct FriendRequestDTO: Decodable {
    let id: String
    let fromUser: UserPreviewDTO
    let status: String
    let createdAt: Date?

    func toFriendRequest() -> FriendRequest {
        FriendRequest(
            id: id,
            fromUser: fromUser.toUserPreview(),
            toUser: UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true),
            status: .pending,
            createdAt: createdAt ?? Date()
        )
    }
}

private struct UserPreviewDTO: Decodable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool?

    func toUserPreview() -> UserPreview {
        UserPreview(id: id, username: username, avatarURL: avatarURL, isOnline: isOnline ?? false)
    }
}

private struct SuccessDTO: Decodable {
    let success: Bool?
}
