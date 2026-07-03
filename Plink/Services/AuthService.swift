import Foundation

// MARK: - Auth Service (Production — real server registration)
/// Настоящая авторизация через сервер: /api/auth/signup, /api/auth/signin.
/// Сервер создаёт пользователя в PostgreSQL, хеширует пароль (SHA-256),
/// выдаёт JWT. Токен сохраняется и прокидывается во все сервисы.
final class AuthService: AuthServiceProtocol {

    private let api: APIClient
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let savedUser = "rave_saved_user"
        static let authToken = "rave_auth_token"
        static let tokenExpiry = "rave_token_expiry"
        static let fcmToken = "rave_fcm_token"
    }

    // MARK: - Stored User + Token

    @MainActor private(set) var currentUser: User?
    private(set) var authToken: String?
    private(set) var tokenExpiry: TimeInterval = 0
    private(set) var fcmToken: String?

    // MARK: - Init

    init(api: APIClient) {
        self.api = api

        // Восстановление сохранённого юзера + токена при запуске
        if let data = defaults.data(forKey: Keys.savedUser),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            Task { @MainActor in self.currentUser = user }
        }
        self.authToken = defaults.string(forKey: Keys.authToken)
        self.tokenExpiry = defaults.double(forKey: Keys.tokenExpiry)
        self.fcmToken = defaults.string(forKey: Keys.fcmToken)

        api.authToken = authToken
    }

    // MARK: - Sign In (реальный запрос к серверу)

    func signIn(email: String, password: String) async throws -> User {
        let body = SignInRequest(email: email, password: password)
        let response: AuthResponse = try await api.request("auth/signin", method: .post, body: body)

        let user = User(
            id: response.user.id,
            username: response.user.username,
            email: response.user.email,
            avatarURL: response.user.avatarURL,
            isOnline: true,
            isPremium: response.user.isPremium ?? false,
            role: response.user.role,
            createdAt: response.user.createdAt ?? Date()
        )

        let expiry = Date().addingTimeInterval(86400).timeIntervalSince1970  // JWT ~24h
        await cacheToken(response.token, expiry: expiry)
        cacheUser(user)
        await registerFCMIfPresent()
        return user
    }

    // MARK: - Sign Up (реальная регистрация на сервере)

    func signUp(email: String, password: String, username: String) async throws -> User {
        let body = SignUpRequest(email: email, password: password, username: username)
        let response: AuthResponse = try await api.request("auth/signup", method: .post, body: body)

        let user = User(
            id: response.user.id,
            username: response.user.username,
            email: response.user.email,
            avatarURL: response.user.avatarURL,
            isOnline: true,
            isPremium: response.user.isPremium ?? false,
            role: response.user.role,
            createdAt: response.user.createdAt ?? Date()
        )

        let expiry = Date().addingTimeInterval(86400).timeIntervalSince1970
        await cacheToken(response.token, expiry: expiry)
        cacheUser(user)
        await registerFCMIfPresent()
        return user
    }

    // MARK: - Sign Out

    func signOut() async throws {
        defaults.removeObject(forKey: Keys.savedUser)
        defaults.removeObject(forKey: Keys.authToken)
        defaults.removeObject(forKey: Keys.tokenExpiry)
        authToken = nil
        tokenExpiry = 0
        api.authToken = nil
        await MainActor.run { self.currentUser = nil }
    }

    // MARK: - Current User

    func currentUser() async -> User? {
        await currentUser
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        // TODO: добавить DELETE /api/auth/me на сервере
        try await signOut()
    }

    // MARK: - Token Management

    func getFreshToken() async -> String? {
        let now = Date().timeIntervalSince1970
        if authToken == nil || now >= tokenExpiry - 300 {
            return authToken
        }
        return authToken
    }

    private func cacheToken(_ token: String, expiry: TimeInterval) async {
        authToken = token
        tokenExpiry = expiry
        api.authToken = token
        defaults.set(token, forKey: Keys.authToken)
        defaults.set(expiry, forKey: Keys.tokenExpiry)
    }

    // MARK: - FCM Token

    func setFCMToken(_ token: String) async {
        fcmToken = token
        defaults.set(token, forKey: Keys.fcmToken)
        await registerFCMToken(token)
    }

    private func registerFCMIfPresent() async {
        guard let fcmToken else { return }
        await registerFCMToken(fcmToken)
    }

    private func registerFCMToken(_ token: String) {
        struct FCMBody: Encodable { let token: String }
        let body = FCMBody(token: token)
        Task {
            do {
                try await api.requestNoBody("auth/fcm-token", method: .post, body: body)
            } catch {
                print("[Auth] FCM token registration failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func cacheUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: Keys.savedUser)
        }
        Task { @MainActor in self.currentUser = user }
    }
}

// MARK: - API Request/Response Models

struct SignInRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct SignUpRequest: Codable, Sendable {
    let email: String
    let password: String
    let username: String
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let user: AuthUser
}

struct AuthUser: Codable, Sendable {
    let id: String
    let username: String
    let email: String
    let avatarURL: String?
    let isOnline: Bool?
    let isPremium: Bool?
    let role: String?
    let createdAt: Date?
}
