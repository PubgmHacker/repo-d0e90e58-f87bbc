import Foundation
import SwiftUI

// MARK: - Room Invite Service
/// Invites are delivered as DMs containing `plink-invite:CODE|ROOMID|NAME`.
/// Host sends DM on create; friend polls GET /messages/invites.
@MainActor
final class RoomInviteService: ObservableObject {
    static let shared = RoomInviteService()

    @Published var pendingInvites: [RoomInvite] = []

    private init() {
        loadInvites()
    }

    // MARK: - Server poll

    func refreshFromServer() async {
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        guard APIClient.shared.authToken != nil else { return }
        do {
            let remote: [RemoteInviteDTO] = try await APIClient.shared.request("messages/invites")
            let mapped = remote.map { dto in
                RoomInvite(
                    id: dto.id,
                    roomID: dto.roomID,
                    roomCode: dto.roomCode,
                    roomName: dto.roomName,
                    fromUserID: dto.fromUserID,
                    fromUsername: dto.fromUsername,
                    fromAvatarURL: dto.fromAvatarURL,
                    timestamp: dto.timestamp ?? Date(),
                    mediaTitle: dto.mediaTitle,
                    service: nil
                )
            }
            // Merge: remote first, keep any local-only still pending
            var byId: [String: RoomInvite] = [:]
            for inv in mapped { byId[inv.id] = inv }
            for inv in pendingInvites where byId[inv.id] == nil {
                // drop stale local if code matches remote
                if !mapped.contains(where: { $0.roomCode == inv.roomCode }) {
                    byId[inv.id] = inv
                }
            }
            pendingInvites = Array(byId.values).sorted { $0.timestamp > $1.timestamp }
            saveInvites()
            print("[RoomInvite] pending=\(pendingInvites.count)")
        } catch {
            print("[RoomInvite] refresh error: \(error.localizedDescription)")
        }
    }

    // MARK: - Host: send invite after room create

    /// Sends DM with machine-readable invite token friend can accept.
    func sendInvite(to friend: Friend, room: Room, mediaTitle: String?) async {
        let code = room.code.uppercased()
        let name = room.name.replacingOccurrences(of: "|", with: " ")
        let shortName = String(name.prefix(40))
        let body = "🎬 Смотрим вместе «\(shortName)» · код \(code)\nplink-invite:\(code)|\(room.id)|\(shortName)"

        // Single send via shared DM service (optimistic + server)
        DMChatService.shared.sendMessage(body, to: friend)
        print("[RoomInvite] sent to \(friend.username) code=\(code)")
    }

    // MARK: - Add Invite (local / push)

    func addInvite(_ invite: RoomInvite) {
        guard !pendingInvites.contains(where: { $0.id == invite.id || $0.roomCode == invite.roomCode }) else { return }
        pendingInvites.insert(invite, at: 0)
        saveInvites()
        HapticManager.impact(.medium)
    }

    // MARK: - Accept / Decline

    func acceptInvite(_ invite: RoomInvite) async -> Room? {
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        do {
            let room = try await RoomService(api: APIClient.shared).joinRoom(code: invite.roomCode, password: nil)
            removeInvite(invite)
            // Mark invite DM read by opening history with that friend (best-effort)
            Task {
                await DMChatService.shared.loadHistory(
                    friendId: invite.fromUserID,
                    friendName: invite.fromUsername,
                    quiet: true
                )
            }
            return room
        } catch {
            print("[RoomInvite] accept failed: \(error.localizedDescription)")
            return nil
        }
    }

    func declineInvite(_ invite: RoomInvite) {
        removeInvite(invite)
    }

    func removeInvite(_ invite: RoomInvite) {
        pendingInvites.removeAll { $0.id == invite.id || $0.roomCode == invite.roomCode }
        saveInvites()
    }

    var inviteCount: Int {
        pendingInvites.count
    }

    // MARK: - Persistence

    private func saveInvites() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try? enc.encode(pendingInvites)
        UserDefaults.standard.set(data, forKey: "room_invites")
    }

    private func loadInvites() {
        guard let data = UserDefaults.standard.data(forKey: "room_invites") else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let invites = try? dec.decode([RoomInvite].self, from: data) {
            pendingInvites = invites
        }
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
    let mediaTitle: String?
    let service: VideoService?

    init(id: String = UUID().uuidString,
         roomID: String,
         roomCode: String,
         roomName: String,
         fromUserID: String,
         fromUsername: String,
         fromAvatarURL: String? = nil,
         timestamp: Date = Date(),
         mediaTitle: String? = nil,
         service: VideoService? = nil) {
        self.id = id
        self.roomID = roomID
        self.roomCode = roomCode
        self.roomName = roomName
        self.fromUserID = fromUserID
        self.fromUsername = fromUsername
        self.fromAvatarURL = fromAvatarURL
        self.timestamp = timestamp
        self.mediaTitle = mediaTitle
        self.service = service
    }

    enum CodingKeys: String, CodingKey {
        case id, roomID, roomCode, roomName, fromUserID, fromUsername, fromAvatarURL, timestamp, mediaTitle, service
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        roomID = try c.decode(String.self, forKey: .roomID)
        roomCode = try c.decode(String.self, forKey: .roomCode)
        roomName = try c.decode(String.self, forKey: .roomName)
        fromUserID = try c.decode(String.self, forKey: .fromUserID)
        fromUsername = try c.decode(String.self, forKey: .fromUsername)
        fromAvatarURL = try c.decodeIfPresent(String.self, forKey: .fromAvatarURL)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        mediaTitle = try c.decodeIfPresent(String.self, forKey: .mediaTitle)
        service = try c.decodeIfPresent(VideoService.self, forKey: .service)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roomID, forKey: .roomID)
        try c.encode(roomCode, forKey: .roomCode)
        try c.encode(roomName, forKey: .roomName)
        try c.encode(fromUserID, forKey: .fromUserID)
        try c.encode(fromUsername, forKey: .fromUsername)
        try c.encodeIfPresent(fromAvatarURL, forKey: .fromAvatarURL)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(mediaTitle, forKey: .mediaTitle)
        try c.encodeIfPresent(service, forKey: .service)
    }
}

// MARK: - DTOs

private struct RemoteInviteDTO: Decodable {
    let id: String
    let roomID: String
    let roomCode: String
    let roomName: String
    let fromUserID: String
    let fromUsername: String
    let fromAvatarURL: String?
    let mediaTitle: String?
    let timestamp: Date?
}
