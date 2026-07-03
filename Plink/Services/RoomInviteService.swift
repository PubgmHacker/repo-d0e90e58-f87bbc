import Foundation
import SwiftUI

// MARK: - Room Invite Service
/// 🔧 NEW: Manages room invitations from friends.
/// When a friend invites you to a room:
///   1. A push notification is sent (via server FCM)
///   2. An in-app invite appears in the "Запросы" section of the Rooms tab
///   3. A red badge appears on the Rooms tab icon showing the count
@MainActor
final class RoomInviteService: ObservableObject {
    static let shared = RoomInviteService()

    @Published var pendingInvites: [RoomInvite] = []

    private init() {
        loadInvites()
    }

    // MARK: - Add Invite

    /// Called when a room invite is received (via WS push or FCM notification).
    func addInvite(_ invite: RoomInvite) {
        // Don't add duplicates
        guard !pendingInvites.contains(where: { $0.id == invite.id }) else { return }
        pendingInvites.insert(invite, at: 0)
        saveInvites()
        HapticManager.impact(.medium)
    }

    // MARK: - Accept / Decline

    func acceptInvite(_ invite: RoomInvite) async -> Room? {
        // Join the room via code
        do {
            let room = try await RoomService(api: APIClient()).joinRoom(code: invite.roomCode, password: nil)
            removeInvite(invite)
            return room
        } catch {
            return nil
        }
    }

    func declineInvite(_ invite: RoomInvite) {
        removeInvite(invite)
    }

    func removeInvite(_ invite: RoomInvite) {
        pendingInvites.removeAll { $0.id == invite.id }
        saveInvites()
    }

    var inviteCount: Int {
        pendingInvites.count
    }

    // MARK: - Persistence

    private func saveInvites() {
        let data = try? JSONEncoder().encode(pendingInvites)
        UserDefaults.standard.set(data, forKey: "room_invites")
    }

    private func loadInvites() {
        guard let data = UserDefaults.standard.data(forKey: "room_invites"),
              let invites = try? JSONDecoder().decode([RoomInvite].self, from: data) else { return }
        pendingInvites = invites
    }
}

// MARK: - Room Invite Model

struct RoomInvite: Codable, Identifiable, Sendable {
    let id: String
    let roomID: String
    let roomCode: String
    let roomName: String
    let fromUserID: String
    let fromUsername: String
    let fromAvatarURL: String?
    let timestamp: Date

    init(id: String = UUID().uuidString,
         roomID: String,
         roomCode: String,
         roomName: String,
         fromUserID: String,
         fromUsername: String,
         fromAvatarURL: String? = nil,
         timestamp: Date = Date()) {
        self.id = id
        self.roomID = roomID
        self.roomCode = roomCode
        self.roomName = roomName
        self.fromUserID = fromUserID
        self.fromUsername = fromUsername
        self.fromAvatarURL = fromAvatarURL
        self.timestamp = timestamp
    }
}
