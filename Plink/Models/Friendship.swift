import Foundation

// MARK: - Friendship Models (Блок 3 — социальный слой)
/// Статусы дружбы между пользователями.
enum FriendshipStatus: String, Codable, Sendable {
    case pending      // Заявка отправлена, ждёт ответа
    case accepted     // Дружба подтверждена
    case declined     // Заявка отклонена
    case blocked      // Пользователь заблокирован
}

// MARK: - Friend
/// Полноценный друг (с подтверждённой дружбой).
struct Friend: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool
    let friendsSince: Date
    /// Optional Telegram-style display name (may be nil on older payloads).
    var displayName: String? = nil

    /// Конвертация в UserPreview для UI-компонентов.
    var asUserPreview: UserPreview {
        UserPreview(id: id, username: username, avatarURL: avatarURL, isOnline: isOnline)
    }

    /// Name shown in UI — displayName if set, else @username.
    var displayTitle: String {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        return username
    }

    /// Single letter for avatar fallback — never uses current user.
    var initials: String {
        PlinkAvatarURL.letter(from: displayTitle)
    }
}

// MARK: - Friend Request
/// Входящая или исходящая заявка в друзья.
struct FriendRequest: Codable, Identifiable, Sendable {
    let id: String              // ID заявки
    let fromUser: UserPreview   // Кто отправил
    let toUser: UserPreview     // Кому отправлено
    let status: FriendshipStatus
    let createdAt: Date

    var isIncoming: Bool {
        // Определяется контекстом (входящие vs исходящие списки).
        true
    }

    var formattedDate: String {
        createdAt.formatted(.relative(presentation: .named))
    }
}

// MARK: - Friendship Link Type (для Deep-Linking)
/// Тип ссылки-приглашения (Блок 3 — Universal Links).
enum DeepLinkType: Sendable, Equatable {
    case room(code: String)        // https://yourdomain.com/r/<code>
    case friendInvite(userId: String)  // https://yourdomain.com/u/<userId>
    case none
}
