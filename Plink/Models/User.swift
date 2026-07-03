import Foundation

// MARK: - User Model
struct User: Codable, Identifiable, Sendable {
    let id: String
    let username: String
    let email: String
    let avatarURL: String?
    let isOnline: Bool
    let isPremium: Bool
    let role: String?
    let createdAt: Date

    var initials: String {
        String(username.prefix(2).uppercased())
    }

    var displayName: String {
        username
    }

    /// True если пользователь имеет роль администратора
    var isAdmin: Bool {
        (role ?? "").uppercased() == "ADMIN"
    }

    /// 🔧 NEW: Short display ID — last 8 chars of the UUID, prefixed with #.
    /// Shown in small text under the username so users can find each other by ID.
    /// Example: id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890" → "#ef1234567890" (last 12 chars)
    var shortId: String {
        guard id.count >= 12 else { return "#\(id)" }
        let short = String(id.suffix(8))
        return "#\(short)"
    }

    /// 🔧 NEW: Full ID for copy-to-clipboard / share. Used in friend search.
    var fullId: String {
        id
    }

    static var preview: User {
        User(
            id: "user_001",
            username: "Alex",
            email: "alex@example.com",
            avatarURL: nil,
            isOnline: true,
            isPremium: false,
            role: nil,
            createdAt: Date()
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, avatarURL, isOnline, isPremium, role, createdAt
    }

    init(id: String, username: String, email: String, avatarURL: String?,
         isOnline: Bool, isPremium: Bool, role: String? = nil, createdAt: Date) {
        self.id = id
        self.username = username
        self.email = email
        self.avatarURL = avatarURL
        self.isOnline = isOnline
        self.isPremium = isPremium
        self.role = role
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? true
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        role = try container.decodeIfPresent(String.self, forKey: .role)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Minimal User (for room participants list)
struct UserPreview: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool

    static var preview: UserPreview {
        UserPreview(id: "user_002", username: "Jordan", avatarURL: nil, isOnline: true)
    }
}
