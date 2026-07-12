import Foundation

public enum V4Tab: String, CaseIterable, Identifiable, Sendable {
    case home, rooms, ai, friends, profile
    public var id: Self { self }

    public var title: String {
        switch self {
        case .home: "Главная"
        case .rooms: "Комнаты"
        case .ai: "ИИ"
        case .friends: "Друзья"
        case .profile: "Профиль"
        }
    }

    public var icon: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "play.rectangle.on.rectangle.fill"
        case .ai: "sparkles"
        case .friends: "person.2.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

public struct V4User: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let avatarURL: URL?
    public let subtitle: String
    public let isOnline: Bool
}

public struct V4Room: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    public let participantCount: Int
    public let isLive: Bool
}

public struct V4MediaCard: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    public let duration: String?
    public let isSelectable: Bool
}

public enum V4ServiceKind: String, Hashable, Sendable {
    case youtube, rutube, vkVideo, kinopoisk, ivi, okko, wink, premier, start, kion, moreTV, vimeo, twitch, directLink, external
}

public struct V4VideoService: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: V4ServiceKind
    public let name: String
    public let subtitle: String
    public let symbol: String
    public let categoryID: String
    public let isAvailable: Bool
}

public struct V4ServiceCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
}

public enum V4MediaSelection: Hashable, Sendable {
    case youtube(V4MediaCard)
    case provider(serviceID: String, item: V4MediaCard)
    case directLink(validatedToken: String, title: String)
}

public enum V4RoomPrivacy: String, CaseIterable, Sendable {
    case inviteOnly, publicRoom, password

    public var title: String {
        switch self {
        case .inviteOnly: "По приглашению"
        case .publicRoom: "Публичная"
        case .password: "С паролем"
        }
    }
}

public struct V4RoomDraft: Sendable {
    public var serviceID: String?
    public var media: V4MediaSelection?
    public var title = ""
    public var privacy: V4RoomPrivacy = .inviteOnly
    public var password = ""
    public var themeID = V4ThemeCatalog.defaultID
    public var aiEnabled = true

    public var isValid: Bool {
        serviceID != nil && media != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum V4AISender: Hashable, Sendable {
    case user(id: String, name: String)
    case plinkAI
    case system

    public var displayName: String {
        switch self {
        case .user(_, let name): name
        case .plinkAI: "Plink AI"
        case .system: "Plink"
        }
    }

    public var isVerified: Bool {
        switch self {
        case .plinkAI, .system: true
        case .user: false
        }
    }
}

public struct V4ChatMessage: Identifiable, Hashable, Sendable {
    public let id: String
    public let sender: V4AISender
    public let text: String
    public let isOwn: Bool
    public let moderation: V4ModerationPresentation?
}

public enum V4ModerationPresentation: Hashable, Sendable {
    case warning(reason: String)
    case hidden(reason: String, appealable: Bool)
    case quarantined(reason: String)
}

public enum V4AIState: String, Sendable {
    case idle, listening, thinking, speaking, moderating, offline, failed
}

@MainActor
public protocol V4AppAdapter: AnyObject {
    var currentUser: V4User { get }
    var liveRooms: [V4Room] { get }
    var trending: [V4MediaCard] { get }
    var friends: [V4User] { get }
    var services: [V4VideoService] { get }
    var serviceCategories: [V4ServiceCategory] { get }

    func bootstrap() async
    func refreshHome() async
    func openRoom(id: String)
    func openDM(userID: String)
    func invite(userID: String)
    func searchYouTube(query: String, pageToken: String?) async throws -> ([V4MediaCard], String?)
    func browse(serviceID: String) async throws -> [V4MediaCard]
    func validateDirectLink(_ value: String) async throws -> (token: String, title: String)
    func createRoom(draft: V4RoomDraft) async throws -> String
    func sendAI(_ text: String) async throws -> String
    func confirmAITool(token: String) async throws
    func signOut() async
    func deleteAccount() async throws
}
