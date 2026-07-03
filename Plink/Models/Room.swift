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
    /// 🔧 NEW: Privacy level — public (visible to all), friends (friends only), private (link only)
    var privacy: RoomPrivacy

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
         maxParticipants: Int, hostIsPremium: Bool, createdAt: Date,
         privacy: RoomPrivacy = .publicRoom) {
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
        self.privacy = privacy
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
        privacy = try c.decodeIfPresent(RoomPrivacy.self, forKey: .privacy) ?? .publicRoom
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
        try c.encode(privacy, forKey: .privacy)
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

    // MARK: - Mock Rooms
    // 🔧 FIX L2: mockRooms removed from production. Was misleading — if the server
    // returned empty/401, users saw fake "active" rooms with fake participant counts.
    // Now the UI must handle the empty state explicitly (HomeView shows a friendly
    // empty state instead of fake content).
    #if DEBUG
    /// Mock rooms for SwiftUI previews and unit tests only.
    static var previewMockRooms: [Room] {
        let mkItem: (String, MediaItem.MediaType) -> MediaItem = { title, type in
            MediaItem(id: UUID().uuidString, title: title, artist: nil,
                      thumbnailURL: nil, streamURL: "", duration: 5400,
                      mediaType: type, source: .url)
        }
        return [
            Room(id: "preview1", name: "Preview Room", hostID: "preview_host",
                 hostName: "Preview", code: "PREV01",
                 participants: [], mediaItem: mkItem("Preview", .video),
                 isActive: true, maxParticipants: 10, hostIsPremium: false,
                 createdAt: .now),
        ]
    }
    #endif

    enum CodingKeys: String, CodingKey {
        case id, name, hostID, hostName, code
        case participants, mediaItem, isActive
        case maxParticipants, hostIsPremium, createdAt, privacy
    }
}

// MARK: - Create Room Request
struct CreateRoomRequest: Codable, Sendable {
    let name: String
    let maxParticipants: Int
    let mediaItem: MediaItem?
    /// 🔧 NEW: Privacy level for the room
    let privacy: RoomPrivacy
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
