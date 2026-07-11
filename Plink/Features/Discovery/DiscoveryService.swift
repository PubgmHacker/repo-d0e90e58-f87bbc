// Plink/Features/Discovery/DiscoveryService.swift — Data service
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §3: Discovery data.
// Adapts existing HomeViewModel/API calls — does not hardcode movie data.

import Foundation

@MainActor
final class DiscoveryService {
    private let apiClient: APIClient
    private let roomService: RoomService

    init(apiClient: APIClient, roomService: RoomService) {
        self.apiClient = apiClient
        self.roomService = roomService
    }

    func featured() async throws -> [DiscoveryItem] {
        // Adapt from existing trending/featured rooms API.
        let rooms = try await roomService.fetchPublicRooms()
        return rooms.prefix(5).map { DiscoveryItem(from: $0) }
    }

    func continueTogether() async throws -> [ContinueItem] {
        // Adapt from watch history.
        let myRooms = try await roomService.fetchMyRooms()
        return myRooms.prefix(10).map { ContinueItem(from: $0) }
    }

    func liveRooms() async throws -> [Room] {
        try await roomService.fetchActiveRooms()
    }

    func collections() async throws -> [EditorialCollection] {
        // Static collections for now — can be backend-driven later.
        return [
            EditorialCollection(
                title: "Популярное сейчас",
                items: try await featured()
            )
        ]
    }
}

// MARK: - Data models

struct DiscoveryItem: Identifiable, Sendable {
    let id: String
    let title: String
    let eyebrow: String
    let metadata: String
    let backdropURL: String?
    let interestedFriends: [UserPreview]

    init(from room: Room) {
        self.id = room.id
        self.title = room.name
        self.eyebrow = room.hostIsPremium ? "Plink+" : "Комната"
        self.metadata = "\(room.participantCount) участников"
        self.backdropURL = room.mediaItem?.thumbnailURL
        self.interestedFriends = Array(room.participants.prefix(3))
    }
}

struct ContinueItem: Identifiable, Sendable {
    let id: String
    let title: String
    let thumbnailURL: String?
    let progress: Double

    init(from room: Room) {
        self.id = room.id
        self.title = room.name
        self.thumbnailURL = room.mediaItem?.thumbnailURL
        self.progress = 0.5  // Placeholder — wire to real watch history.
    }
}

struct EditorialCollection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let items: [DiscoveryItem]
}
