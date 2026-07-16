import Foundation
import Combine

// MARK: - Friend Manager v3 (Real API + search/request/accept)
/// HTTP → /api/friends/*
@MainActor
final class FriendManager: ObservableObject {

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var outgoingRequests: [FriendRequest] = []
    @Published private(set) var searchResults: [UserPreview] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastSuccessMessage: String?

    var onIncomingRequest: ((FriendRequest) -> Void)?
    var onFriendAdded: ((Friend) -> Void)?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load All

    func loadAll() async {
        ensureToken()
        // Sequential on MainActor — avoid racing @Published arrays
        await loadFriends()
        await loadIncomingRequests()
        await loadOutgoingRequests()
        // Drop outgoing that are now friends (accepted on the other device)
        let friendIds = Set(friends.map(\.id))
        outgoingRequests.removeAll { friendIds.contains($0.toUser.id) }
    }

    private func ensureToken() {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
    }

    func loadFriends() async {
        ensureToken()
        guard api.authToken != nil else {
            print("[Friends] loadFriends: no auth token")
            return
        }
        do {
            let dtos: [FriendDTO] = try await api.request("friends")
            friends = dtos.map { $0.toFriend() }
            print("[Friends] loaded \(friends.count) friends")
        } catch {
            print("[Friends] loadFriends error: \(error.localizedDescription)")
        }
    }

    func loadIncomingRequests() async {
        guard api.authToken != nil else { return }
        do {
            let dtos: [IncomingRequestDTO] = try await api.request("friends/requests/incoming")
            incomingRequests = dtos.map { $0.toFriendRequest() }
        } catch {
            print("[Friends] loadIncoming error: \(error.localizedDescription)")
        }
    }

    func loadOutgoingRequests() async {
        guard api.authToken != nil else { return }
        do {
            let dtos: [OutgoingRequestDTO] = try await api.request("friends/requests/outgoing")
            outgoingRequests = dtos.map { $0.toFriendRequest() }
        } catch {
            // Older backends without outgoing endpoint — keep local list
            print("[Friends] loadOutgoing error: \(error.localizedDescription)")
        }
    }

    /// Alias used by older call sites
    func loadRequests() async {
        await loadIncomingRequests()
        await loadOutgoingRequests()
    }

    // MARK: - Send Request

    @discardableResult
    func sendRequest(to userId: String, username: String) async -> Bool {
        struct Body: Encodable { let friendId: String }
        do {
            let resp: SendRequestResponse = try await api.request(
                "friends/request",
                method: .post,
                body: Body(friendId: userId)
            )
            if resp.autoAccepted == true {
                lastSuccessMessage = "\(username) теперь у вас в друзьях"
                await loadAll()
                return true
            }
            lastSuccessMessage = "Заявка отправлена"
            // Optimistic outgoing
            let preview = UserPreview(id: userId, username: username, avatarURL: nil, isOnline: false)
            let me = UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true)
            let req = FriendRequest(
                id: resp.id ?? UUID().uuidString,
                fromUser: me,
                toUser: preview,
                status: .pending,
                createdAt: Date()
            )
            if !outgoingRequests.contains(where: { $0.toUser.id == userId }) {
                outgoingRequests.insert(req, at: 0)
            }
            await loadOutgoingRequests()
            return true
        } catch {
            errorMessage = friendlyError(error)
            print("[Friends] sendRequest error: \(error.localizedDescription)")
            return false
        }
    }

    /// Search by @username and send in one step
    @discardableResult
    func sendRequestByUsername(_ username: String) async -> Bool {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty else {
            errorMessage = "Введите @username"
            return false
        }
        struct Body: Encodable { let username: String }
        do {
            let resp: SendRequestResponse = try await api.request(
                "friends/request",
                method: .post,
                body: Body(username: clean)
            )
            if resp.autoAccepted == true {
                lastSuccessMessage = "@\(clean) теперь у вас в друзьях"
            } else {
                lastSuccessMessage = "Заявка отправлена"
            }
            await loadAll()
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    // MARK: - Accept / Decline

    func acceptRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }
        do {
            let _: SuccessDTO = try await api.request(
                "friends/requests/\(request.id)",
                method: .put,
                body: Body(status: "accepted")
            )
            incomingRequests.removeAll { $0.id == request.id }
            let newFriend = Friend(
                id: request.fromUser.id,
                username: request.fromUser.username,
                avatarURL: request.fromUser.avatarURL,
                isOnline: request.fromUser.isOnline,
                friendsSince: Date(),
                displayName: nil,
                lastSeenAt: nil
            )
            if !friends.contains(where: { $0.id == newFriend.id }) {
                friends.append(newFriend)
            }
            onFriendAdded?(newFriend)
            lastSuccessMessage = "\(request.fromUser.username) добавлен в друзья"
            await loadFriends()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func declineRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }
        do {
            let _: SuccessDTO = try await api.request(
                "friends/requests/\(request.id)",
                method: .put,
                body: Body(status: "rejected")
            )
            incomingRequests.removeAll { $0.id == request.id }
            lastSuccessMessage = "Заявка отклонена"
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func removeFriend(_ friend: Friend) async {
        do {
            try await api.requestNoBody("friends/\(friend.id)", method: .delete)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Search

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
        let cleanedQuery = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos: [UserPreviewDTO] = try await api.request("friends/search", query: ["q": cleanedQuery])
            searchResults = dtos.map { $0.toUserPreview() }
        } catch {
            print("[Friends] search error: \(error.localizedDescription)")
            searchResults = []
            errorMessage = friendlyError(error)
        }
    }

    func isFriend(_ userId: String) -> Bool {
        friends.contains { $0.id == userId }
    }

    func hasOutgoingRequest(to userId: String) -> Bool {
        outgoingRequests.contains { $0.toUser.id == userId }
    }

    func generateInviteLink(userId: String) -> URL {
        URL(string: "\(ShareManager.shareBaseURL)/u/\(userId)")!
    }

    private func friendlyError(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .conflict(let message):
                if message.lowercased().contains("already") { return "Уже друзья или заявка отправлена" }
                return message
            case .notFound:
                return "Пользователь не найден"
            case .serverError(_, let message):
                return message ?? "Ошибка сервера"
            case .unauthorized:
                return "Войдите в аккаунт"
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - DTOs

private struct FriendDTO: Decodable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool?
    let friendsSince: Date?
    let displayName: String?
    let lastSeenAt: Date?

    func toFriend() -> Friend {
        Friend(
            id: id,
            username: username,
            avatarURL: avatarURL,
            isOnline: isOnline ?? false,
            friendsSince: friendsSince ?? Date(),
            displayName: displayName,
            lastSeenAt: lastSeenAt
        )
    }
}

private struct IncomingRequestDTO: Decodable {
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

private struct OutgoingRequestDTO: Decodable {
    let id: String
    let toUser: UserPreviewDTO
    let status: String
    let createdAt: Date?

    func toFriendRequest() -> FriendRequest {
        FriendRequest(
            id: id,
            fromUser: UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true),
            toUser: toUser.toUserPreview(),
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
    let displayName: String?

    func toUserPreview() -> UserPreview {
        UserPreview(id: id, username: username, avatarURL: avatarURL, isOnline: isOnline ?? false)
    }
}

private struct SendRequestResponse: Decodable {
    let success: Bool?
    let id: String?
    let status: String?
    let friendId: String?
    let autoAccepted: Bool?
}

private struct SuccessDTO: Decodable {
    let success: Bool?
}
