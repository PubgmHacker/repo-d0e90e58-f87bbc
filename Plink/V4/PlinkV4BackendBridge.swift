// Plink/V4/PlinkV4BackendBridge.swift — P0 Roadmap
// Connects V4 pixel-perfect views to real RoomService/FriendManager/AuthService/MediaService.
// NO placeholders, NO fake data.

import SwiftUI
import Observation

// MARK: - V4 Rooms Store (P0.2)

@MainActor
@Observable
final class V4RoomsStore {
    enum LoadState: Sendable { case idle, loading, loaded, empty, failed(String) }
    private(set) var state: LoadState = .idle
    private(set) var rooms: [Room] = []
    private(set) var myRooms: [Room] = []
    private let roomService: RoomService

    init(roomService: RoomService) { self.roomService = roomService }

    func load() async {
        state = .loading
        do {
            let active = try await roomService.fetchActiveRooms()
            rooms = active
            state = active.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMyRooms() async {
        do { myRooms = try await roomService.fetchMyRooms() } catch {}
    }

    func join(code: String, password: String? = nil) async throws -> Room {
        try await roomService.joinRoom(code: code, password: password)
    }

    func joinByID(_ room: Room) async throws -> Room {
        try await roomService.fetchRoom(id: room.id)
    }

    var heroRoom: Room? { rooms.first }
    var railRooms: [Room] { Array(rooms.dropFirst().prefix(6)) }
}

// MARK: - V4 Search Store (P0.3)

@MainActor
@Observable
final class V4SearchStore {
    enum SearchState: Sendable { case idle, loading, loaded([V4SearchResult]), empty, failed(String) }
    private(set) var state: SearchState = .idle
    private(set) var trending: [V4SearchResult] = []
    private var searchTask: Task<Void, Never>?
    private let apiBase = "https://plink-backend-production-ef31.up.railway.app"

    func loadTrending() async {
        guard let url = URL(string: "\(apiBase)/api/media/trending?regionCode=RU&maxResults=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            trending = resp.results.map(V4SearchResult.init)
        } catch {}
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { state = .idle; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        state = .loading
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(apiBase)/api/media/search?q=\(encoded)&limit=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            let results = resp.results.map(V4SearchResult.init)
            state = results.isEmpty ? .empty : .loaded(results)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct V4SearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let duration: String?
    let isSelectable: Bool

    init(from v: YouTubeVideoSummary) {
        id = v.videoId
        title = v.title
        subtitle = v.channelTitle
        artworkURL = v.thumbnailURLString.flatMap(URL.init(string:))
        let secs = v.durationSeconds ?? v.duration ?? 0
        if secs > 0 {
            let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
            duration = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        } else { duration = nil }
        isSelectable = v.isEmbeddable
    }
}

// MARK: - V4 Friends Store (P1.1)

@MainActor
@Observable
final class V4FriendsStore {
    enum LoadState: Sendable { case idle, loading, loaded, empty, failed(String) }
    private(set) var state: LoadState = .idle
    private(set) var friends: [Friend] = []
    private(set) var requests: [FriendRequest] = []
    private let friendManager: FriendManager

    init(friendManager: FriendManager) { self.friendManager = friendManager }

    func load() async {
        state = .loading
        await friendManager.loadAll()
        friends = friendManager.friends
        requests = friendManager.incomingRequests
        state = friends.isEmpty && requests.isEmpty ? .empty : .loaded
    }

    func invite(userID: String, username: String) async {
        await friendManager.sendRequest(to: userID, username: username)
    }

    func accept(_ request: FriendRequest) async {
        await friendManager.acceptRequest(request)
        await load()
    }
}

// MARK: - V4 AI Store (P0.4)

@MainActor
@Observable
final class V4AIStore {
    struct Message: Identifiable, Hashable {
        let id = UUID()
        let isOwn: Bool
        let text: String
        let isBot: Bool
        var proposedAction: AIProposedAction?
    }

    private(set) var messages: [Message] = [
        Message(isOwn: false, text: "Привет! Я Plink AI. Спроси про фильмы, попроси создать комнату или узнать что смотрят друзья.", isBot: true)
    ]
    private(set) var state: String = "Готов помочь"
    private let apiBase = "https://plink-backend-production-ef31.up.railway.app"

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(Message(isOwn: true, text: trimmed, isBot: false))
        state = "Думаю…"

        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // Send full conversation history — not just the latest message.
            // Backend sends ALL messages to OpenRouter for context memory.
            let conversationMessages: [[String: String]] = messages.map { msg in
                [
                    "role": msg.isBot ? "assistant" : "user",
                    "content": msg.text
                ]
            } + [["role": "user", "content": trimmed]]
            let body: [String: Any] = [
                "messages": conversationMessages,
                "context": ["roomId": NSNull()],
                "mode": "assistant"
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let resp = try JSONDecoder().decode(AIChatResponse.self, from: data)
            messages.append(Message(
                isOwn: false,
                text: resp.message,
                isBot: true,
                proposedAction: resp.proposedAction
            ))
            state = "Готов помочь"
        } catch {
            messages.append(Message(isOwn: false, text: "Не удалось ответить. Попробуйте снова.", isBot: true))
            state = "Ошибка"
        }
    }

    /// P0.4: Confirm a proposed AI action. Returns the created Room if successful.
    func confirmAction(_ action: AIProposedAction) async -> Room? {
        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/confirm-action")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "confirmationId": action.confirmationId,
                "idempotencyKey": UUID().uuidString
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let resp = try JSONDecoder().decode(ConfirmActionResponse.self, from: data)
            return resp.room
        } catch {
            return nil
        }
    }
}

struct AIChatResponse: Decodable {
    let message: String
    let suggestions: [String]?
    let proposedAction: AIProposedAction?
}

struct ConfirmActionResponse: Decodable {
    let success: Bool
    let room: Room?
}

struct AIProposedAction: Decodable, Hashable {
    let type: String
    let confirmationId: String
    let expiresAt: String?
    let payloadPreview: AIPayloadPreview?
}

struct AIPayloadPreview: Decodable, Hashable {
    let title: String?
    let privacy: String?
    let queueCount: Int?
}

// MARK: - V4 Profile Store (P1.3)

@MainActor
@Observable
final class V4ProfileStore {
    private(set) var displayName: String = "Загрузка…"
    private(set) var username: String = ""
    private(set) var email: String = ""
    private(set) var avatarURL: URL?
    private(set) var isPremium: Bool = false
    private(set) var premiumUntil: Date?
    private(set) var isAdmin: Bool = false
    private(set) var selectedTheme: V4Theme = .electric
    private let authService: AuthService
    private let defaults = UserDefaults.standard

    init(authService: AuthService) {
        self.authService = authService
        if let saved = defaults.string(forKey: "v4_theme") {
            selectedTheme = V4Theme(rawValue: saved) ?? .electric
        }
        loadSavedAvatar()
    }

    func load() async {
        let user = await authService.currentUser()
        if let user {
            displayName = user.displayName ?? user.username
            username = user.username
            email = user.email
            avatarURL = user.avatarURL.flatMap(URL.init(string:))
            isPremium = user.isPremium
            isAdmin = (user.role == "ADMIN" || user.role == "FOUNDER")
        }
    }

    func selectTheme(_ theme: V4Theme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: "v4_theme")
    }

    /// Update avatarURL after upload (called by AvatarPickerSheet).
    func updateAvatarURL(_ url: URL) {
        self.avatarURL = url
        // Persist to UserDefaults so it survives reloads
        defaults.set(url.absoluteString, forKey: "plink_user_avatar_url")
    }

    /// Load saved avatar from UserDefaults (called on init)
    func loadSavedAvatar() {
        if let saved = defaults.string(forKey: "plink_user_avatar_url") {
            self.avatarURL = URL(string: saved)
        }
    }
}
