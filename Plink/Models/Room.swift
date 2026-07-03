import Foundation

// MARK: - Room Model
struct Room: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let hostID: String
    let hostName: String
    let code: String               // 6-char shareable code
    var participants: [UserPreview]
    let mediaItem: MediaItem?
    let isActive: Bool
    let maxParticipants: Int
    let hostIsPremium: Bool
    let createdAt: Date

    var participantCount: Int {
        participants.count
    }

    var isFull: Bool {
        participants.count >= maxParticipants
    }

    /// 🔧 FIX M8: Was a dead computed property that always returned false.
    /// Now takes the current user id as a parameter and actually checks.
    /// Usage: `room.isHost(userId: currentUserId)` instead of `room.isHost`.
    func isHost(userId: String) -> Bool {
        hostID == userId
    }

    var formattedDate: String {
        createdAt.formatted(.dateTime.month().day().hour().minute())
    }

    /// Кастомный init для backwards compatibility (hostIsPremium может отсутствовать в JSON).
    init(id: String, name: String, hostID: String, hostName: String, code: String,
         participants: [UserPreview], mediaItem: MediaItem?, isActive: Bool,
         maxParticipants: Int, hostIsPremium: Bool, createdAt: Date) {
        self.id = id
        self.name = name
        self.hostID = hostID
        self.hostName = hostName
        self.code = code
        self.participants = participants
        self.mediaItem = mediaItem
        self.isActive = isActive
        self.maxParticipants = maxParticipants
        self.hostIsPremium = hostIsPremium
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostID = try c.decode(String.self, forKey: .hostID)
        hostName = try c.decode(String.self, forKey: .hostName)
        code = try c.decode(String.self, forKey: .code)
        participants = try c.decode([UserPreview].self, forKey: .participants)
        mediaItem = try c.decodeIfPresent(MediaItem.self, forKey: .mediaItem)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        maxParticipants = try c.decodeIfPresent(Int.self, forKey: .maxParticipants) ?? 10
        hostIsPremium = try c.decodeIfPresent(Bool.self, forKey: .hostIsPremium) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(hostID, forKey: .hostID)
        try c.encode(hostName, forKey: .hostName)
        try c.encode(code, forKey: .code)
        try c.encode(participants, forKey: .participants)
        try c.encodeIfPresent(mediaItem, forKey: .mediaItem)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(maxParticipants, forKey: .maxParticipants)
        try c.encode(hostIsPremium, forKey: .hostIsPremium)
        try c.encode(createdAt, forKey: .createdAt)
    }

    static var preview: Room {
        Room(
            id: "room_001",
            name: "Movie Night 🍿",
            hostID: "user_001",
            hostName: "Alex",
            code: "ABC123",
            participants: [
                UserPreview(id: "user_001", username: "Alex", avatarURL: nil, isOnline: true),
                UserPreview(id: "user_002", username: "Jordan", avatarURL: nil, isOnline: true),
                UserPreview(id: "user_003", username: "Sam", avatarURL: nil, isOnline: false),
            ],
            mediaItem: MediaItem.preview,
            isActive: true,
            maxParticipants: 10,
            hostIsPremium: false,
            createdAt: .now.addingTimeInterval(-3600)
        )
    }

    // MARK: - Mock Rooms (fallback когда сервер 401 или пустой)

    /// Мок-комнаты для отображения трендов и лайв-сессий, когда сервер
    /// недоступен или требует авторизацию. Контент всегда виден.
    static var mockRooms: [Room] {
        let mkItem: (String, MediaItem.MediaType) -> MediaItem = { title, type in
            MediaItem(id: UUID().uuidString, title: title, artist: nil,
                      thumbnailURL: nil, streamURL: "", duration: 5400,
                      mediaType: type, source: .url)
        }

        return [
            Room(id: "m1", name: "Дюна 2 🎬", hostID: "h1", hostName: "Alex",
                 code: "DUNE24", participants: (0..<12).map { UserPreview(id: "p1_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("Дюна: Часть вторая", .movie), isActive: true,
                 maxParticipants: 20, hostIsPremium: true, createdAt: .now.addingTimeInterval(-1800)),

            Room(id: "m2", name: "Lo-Fi Chill 🎵", hostID: "h2", hostName: "Jordan",
                 code: "LOFI25", participants: (0..<8).map { UserPreview(id: "p2_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("Lo-Fi Beats to Relax", .music), isActive: true,
                 maxParticipants: 15, hostIsPremium: false, createdAt: .now.addingTimeInterval(-7200)),

            Room(id: "m3", name: "Witcher Marathon 🗡️", hostID: "h3", hostName: "Sam",
                 code: "WITCH3", participants: (0..<6).map { UserPreview(id: "p3_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("The Witcher S1", .series), isActive: true,
                 maxParticipants: 10, hostIsPremium: true, createdAt: .now.addingTimeInterval(-3600)),

            Room(id: "m4", name: "Stand Up Comedy 😂", hostID: "h4", hostName: "Taylor",
                 code: "COMED1", participants: (0..<15).map { UserPreview(id: "p4_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("Best Stand Up 2024", .video), isActive: true,
                 maxParticipants: 25, hostIsPremium: false, createdAt: .now.addingTimeInterval(-900)),

            Room(id: "m5", name: "Утреннее радио ☀️", hostID: "h5", hostName: "Casey",
                 code: "MORNIN", participants: (0..<4).map { UserPreview(id: "p5_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("Morning Hits", .music), isActive: true,
                 maxParticipants: 10, hostIsPremium: false, createdAt: .now.addingTimeInterval(-14400)),

            Room(id: "m6", name: "Игровой стрим 🎮", hostID: "h6", hostName: "Morgan",
                 code: "GAMER6", participants: (0..<20).map { UserPreview(id: "p6_\($0)", username: "User\($0)", avatarURL: nil, isOnline: true) },
                 mediaItem: mkItem("Cyberpunk 2077", .livestream), isActive: true,
                 maxParticipants: 30, hostIsPremium: true, createdAt: .now.addingTimeInterval(-5400)),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id, name, hostID, hostName, code
        case participants, mediaItem, isActive
        case maxParticipants, hostIsPremium, createdAt
    }
}

// MARK: - Create Room Request
struct CreateRoomRequest: Codable, Sendable {
    let name: String
    let maxParticipants: Int
    let mediaItem: MediaItem?
}

// MARK: - Join Room Request
struct JoinRoomRequest: Codable, Sendable {
    let code: String
}

// MARK: - Room Privacy Level (Блок 4 — Studio)
/// Режим приватности комнаты.
enum RoomPrivacy: String, CaseIterable, Identifiable, Codable, Sendable {
    case publicRoom = "public"      // Discovery Dashboard для всех
    case friendsOnly = "friends"    // только для друзей хоста
    case privateRoom = "private"    // строго по ссылке-приглашению

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicRoom: return "Публичная"
        case .friendsOnly: return "Только для друзей"
        case .privateRoom: return "Приватная"
        }
    }

    var subtitle: String {
        switch self {
        case .publicRoom: return "Видна всем в ленте"
        case .friendsOnly: return "Только ваши друзья"
        case .privateRoom: return "Только по ссылке"
        }
    }

    var icon: String {
        switch self {
        case .publicRoom: return "globe"
        case .friendsOnly: return "person.2"
        case .privateRoom: return "lock"
        }
    }
}
