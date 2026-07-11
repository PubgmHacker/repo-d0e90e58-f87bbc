// Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift
// Composition root for v2 realtime + playback path (Brain Review 5 P0-37, 7 P0-48/P0-49)
//
// P0-48: wired into MainTabView via makeScreenForRoom(room:...)
// P0-49: real legacy fallback — returns actual RoomView, not placeholder
//
// This is the SINGLE entry point that decides whether to use v2 (WatchRoomScreen)
// or legacy (RoomView) path. Controlled by FeatureFlags.realtimeProtocolV2.

import SwiftUI

public enum WatchRoomCompositionRoot {
    /// P0-48: Creates the watch room screen for a Room model — v2 or legacy.
    /// Called from MainTabView's fullScreenCover.
    /// Not public — Room is internal type, method must match.
    @MainActor
    static func makeScreenForRoom(
        room: Room,
        userId: String,
        username: String,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String
    ) -> some View {
        if FeatureFlags.realtimeProtocolV2 {
            // Derive PlaybackSource from room.mediaItem
            let mediaSource = mediaSourceFromRoom(room)
            let mediaId = mediaIdFromRoom(room)
            let model = makeV2Model(
                roomId: room.id,
                userId: userId,
                username: username,
                mediaSource: mediaSource,
                mediaId: mediaId,
                apiBaseURL: apiBaseURL,
                wsBaseURL: wsBaseURL,
                authToken: authToken
            )
            return AnyView(WatchRoomScreen(model: model))
        } else {
            // P0-49: real legacy fallback — actual RoomView, not placeholder
            return AnyView(RoomView(room: room))
        }
    }

    /// Derive PlaybackSource from room.mediaItem
    private static func mediaSourceFromRoom(_ room: Room) -> PlaybackSource? {
        guard let mediaItem = room.mediaItem else { return nil }
        // YouTube videoId → embedded player (App Store compliant)
        if let videoId = mediaItem.videoId, !videoId.isEmpty {
            return .youtube(videoId)
        }
        // Direct stream URL → native AVPlayer
        let urlString = mediaItem.streamURL
        if let url = URL(string: urlString) {
            if urlString.contains(".m3u8") {
                return .hls(url, headers: [:])
            }
            return .mp4(url, headers: [:])
        }
        return nil
    }

    /// Derive mediaId from room.mediaItem
    private static func mediaIdFromRoom(_ room: Room) -> String? {
        guard let mediaItem = room.mediaItem else { return nil }
        return mediaItem.videoId ?? mediaItem.id
    }

    /// Creates the v2 WatchRoomModel with all dependencies wired.
    @MainActor
    private static func makeV2Model(
        roomId: String,
        userId: String,
        username: String,
        mediaSource: PlaybackSource?,
        mediaId: String?,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String
    ) -> WatchRoomModel {
        let catchupClient = RESTChatCatchupClient(
            baseURL: apiBaseURL,
            authToken: authToken
        )

        let ticketProvider: (String) async throws -> RealtimeTicket = { roomId in
            try await fetchTicket(
                apiBaseURL: apiBaseURL,
                authToken: authToken,
                roomId: roomId
            )
        }

        return WatchRoomModel(
            roomId: roomId,
            currentUserId: userId,
            currentUsername: username,
            baseEndpoint: wsBaseURL,
            ticketProvider: ticketProvider,
            mediaSource: mediaSource,
            mediaId: mediaId,
            chatCatchupClient: catchupClient
        )
    }

    /// Fetches a realtime ticket from POST /api/realtime/ticket
    private static func fetchTicket(
        apiBaseURL: URL,
        authToken: String,
        roomId: String
    ) async throws -> RealtimeTicket {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/realtime/ticket"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["roomId": roomId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TicketResponse.self, from: data)
        return RealtimeTicket(
            jwt: decoded.ticket,
            roomId: decoded.roomId ?? roomId,
            expiresInSec: decoded.expiresInSec
        )
    }
}

// MARK: - Feature flags (P1-56: production should use remote config)

public enum FeatureFlags {
    /// P0-37: master switch for v2 realtime + playback path.
    /// P1-56: UserDefaults is DEBUG override only.
    /// Production should use backend FeatureFlag service with cached fallback.
    public static var realtimeProtocolV2: Bool {
        UserDefaults.standard.bool(forKey: "plink.realtime_protocol_v2")
    }
}

// MARK: - REST chat catch-up client (P0-35)

public final class RESTChatCatchupClient: ChatCatchupClient, @unchecked Sendable {
    private let baseURL: URL
    private let authToken: String

    public init(baseURL: URL, authToken: String) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    public func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/rooms/\(roomId)/messages"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "limit", value: "100")]
        if let after = after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        return ChatCatchupResponse(
            messages: decoded.messages.map { m in
                ChatCatchupMessage(
                    messageId: m.messageId,
                    clientMessageId: m.clientMessageId,
                    senderId: m.senderId,
                    senderName: m.senderName,
                    text: m.text,
                    createdAtMs: m.createdAtMs
                )
            },
            hasMore: decoded.hasMore
        )
    }

    // P0-50: fetchParticipants — calls GET /api/rooms/:id/participants
    public func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot] {
        let url = baseURL.appendingPathComponent("api/rooms/\(roomId)/participants")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ParticipantsResponse.self, from: data)
        return decoded.participants.map { p in
            ParticipantSnapshot(userId: p.userId, username: p.username)
        }
    }
}

// MARK: - Decodable response models

private struct TicketResponse: Decodable {
    let ticket: String
    let roomId: String?
    let expiresInSec: Int
    let protocol_: [String]?

    enum CodingKeys: String, CodingKey {
        case ticket
        case roomId
        case expiresInSec
        case protocol_ = "protocol"
    }
}

private struct MessagesResponse: Decodable {
    let messages: [MessageDTO]
    let hasMore: Bool
}

// P0-50: participant snapshot response
private struct ParticipantsResponse: Decodable {
    let participants: [ParticipantDTO]
}

private struct ParticipantDTO: Decodable {
    let userId: String
    let username: String
}

private struct MessageDTO: Decodable {
    let messageId: String
    let clientMessageId: String?
    let senderId: String
    let senderName: String
    let text: String
    let createdAtMs: Int64
}
