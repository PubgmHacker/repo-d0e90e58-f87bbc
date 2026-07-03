import Foundation

// MARK: - Auth Service (Production — real server registration)
/// Настоящая авторизация через сервер: /api/auth/signup, /api/auth/signin.
/// Сервер создаёт пользователя в PostgreSQL, хеширует пароль (SHA-256),
/// выдаёт JWT. Токен сохраняется и прокидывается во все сервисы.
///
/// 🔧 FIX C2: JWT now stored in Keychain (not UserDefaults) via KeychainHelper.
/// 🔧 FIX C3: getFreshToken() now actually refreshes via /auth/refresh.
/// 🔧 FIX H14: AuthService is @MainActor — currentUser restore is synchronous.
@MainActor
final class AuthService: AuthServiceProtocol {

    private let api: APIClient
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let savedUser = "rave_saved_user"           // ← non-secret profile, OK in UserDefaults
        static let authToken = "rave_auth_token"            // ← Keychain
        static let tokenExpiry = "rave_token_expiry"        // ← Keychain (string)
        static let refreshToken = "rave_refresh_token"      // ← Keychain
        static let fcmToken = "rave_fcm_token"              // ← non-secret, OK in UserDefaults
    }

    // MARK: - Stored User + Token

    private(set) var currentUser: User?
    private(set) var authToken: String?
    private(set) var tokenExpiry: TimeInterval = 0
    private(set) var refreshToken: String?
    private(set) var fcmToken: String?

    // MARK: - Init

    init(api: APIClient) {
        self.api = api

        // 🔧 FIX H14: Synchronous restore — AuthService is now @MainActor,
        // so currentUser is populated before RaveCloneApp.checkAuth reads it.
        // No more login-screen flash on cold launch with valid session.
        if let data = defaults.data(forKey: Keys.savedUser),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = user
        }

        // 🔧 FIX C2: Read JWT + expiry + refresh token from Keychain (not UserDefaults)
        self.authToken = KeychainHelper.read(for: Keys.authToken)
        if let expiryStr = KeychainHelper.read(for: Keys.tokenExpiry),
           let expiry = TimeInterval(expiryStr) {
            self.tokenExpiry = expiry
        }
        self.refreshToken = KeychainHelper.read(for: Keys.refreshToken)
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
        await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken)
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
        await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken)
        cacheUser(user)
        await registerFCMIfPresent()
        return user
    }

    // MARK: - Sign Out

    func signOut() async throws {
        // 🔧 FIX C2: Clear Keychain entries too
        KeychainHelper.delete(for: Keys.authToken)
        KeychainHelper.delete(for: Keys.tokenExpiry)
        KeychainHelper.delete(for: Keys.refreshToken)
        defaults.removeObject(forKey: Keys.savedUser)

        authToken = nil
        tokenExpiry = 0
        refreshToken = nil
        api.authToken = nil
        currentUser = nil
    }

    // MARK: - Current User

    func currentUser() async -> User? {
        currentUser
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        // TODO: добавить DELETE /api/auth/me на сервере
        try await signOut()
    }

    // MARK: - Token Management

    /// 🔧 FIX C3: Actually refreshes the JWT via /auth/refresh when within 5 min of expiry.
    /// Falls back to the existing token if no refresh token is available.
    func getFreshToken() async -> String? {
        guard let token = authToken else { return nil }
        let now = Date().timeIntervalSince1970

        // Refresh if within 5 min of expiry (or past it)
        if now >= tokenExpiry - 300 {
            return await refreshJWT() ?? token
        }
        return token
    }

    /// 🔧 FIX C3: Real refresh — POST /auth/refresh with the refresh token.
    private func refreshJWT() async -> String? {
        guard let refreshToken else { return nil }

        struct RefreshBody: Encodable { let refreshToken: String }
        do {
            let response: AuthResponse = try await api.request(
                "auth/refresh",
                method: .post,
                body: RefreshBody(refreshToken: refreshToken)
            )
            let expiry = Date().addingTimeInterval(86400).timeIntervalSince1970
            await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken ?? refreshToken)
            return response.token
        } catch {
            Logger.api.error("Token refresh failed: \(error.localizedDescription)")
            // If refresh fails (refresh token expired), force sign-out
            try? await signOut()
            return nil
        }
    }

    private func cacheToken(_ token: String, expiry: TimeInterval, refreshToken: String?) async {
        authToken = token
        tokenExpiry = expiry
        self.refreshToken = refreshToken
        api.authToken = token

        // 🔧 FIX C2: Persist to Keychain (was: defaults.set)
        KeychainHelper.save(token, for: Keys.authToken)
        KeychainHelper.save(String(expiry), for: Keys.tokenExpiry)
        if let refreshToken {
            KeychainHelper.save(refreshToken, for: Keys.refreshToken)
        }
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
        self.currentUser = user
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
    /// 🔧 FIX C3: Server may also return a long-lived refresh token.
    let refreshToken: String?
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
