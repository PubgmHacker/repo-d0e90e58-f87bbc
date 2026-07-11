// Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift
// Composition root for v2 realtime + playback path (Brain Review 5 P0-37)
//
// This is the SINGLE entry point that decides whether to use v2 (WatchRoomScreen)
// or legacy (RoomView) path. Controlled by FeatureFlag.realtime_protocol_v2.
//
// Callers (MainTabView, RoomCardView, etc.) call:
//   WatchRoomCompositionRoot.makeScreen(roomId:userId:username:mediaSource:)
// and get back a SwiftUI View — either WatchRoomScreen (v2) or legacy RoomView.
//
// IMPORTANT: only ONE path is active. No parallel WS sessions, no mixed
// RealtimeClient + WebSocketClient. Feature flag switches the WHOLE composition.

import SwiftUI

public enum WatchRoomCompositionRoot {
    /// Creates the watch room screen — v2 or legacy based on feature flag.
    /// P0-37: single composition root, no parallel paths.
    @MainActor
    public static func makeScreen(
        roomId: String,
        userId: String,
        username: String,
        mediaSource: PlaybackSource?,
        mediaId: String?,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String
    ) -> some View {
        if FeatureFlags.realtimeProtocolV2 {
            let model = makeV2Model(
                roomId: roomId,
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
            return AnyView(LegacyRoomViewWrapper(roomId: roomId, authToken: authToken))
        }
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
        // P0-35: REST client for chat catch-up + presence snapshot
        let catchupClient = RESTChatCatchupClient(
            baseURL: apiBaseURL,
            authToken: authToken
        )

        // Ticket provider — calls POST /api/realtime/ticket
        let ticketProvider: (String) async throws -> RealtimeTicket = { roomId in
            try await fetchTicket(
                apiBaseURL: apiBaseURL,
                authToken: authToken,
                roomId: roomId
            )
        }

        return WatchRoomModel(
            roomId: roomId,
            currentUserId: userId,        // P1-32: identity via init
            currentUsername: username,    // P1-32
            baseEndpoint: wsBaseURL,
            ticketProvider: ticketProvider,
            mediaSource: mediaSource,
            mediaId: mediaId,             // P1-33
            chatCatchupClient: catchupClient  // P0-35
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

// MARK: - Feature flags

public enum FeatureFlags {
    /// P0-37: master switch for v2 realtime + playback path.
    /// When true: WatchRoomScreen + RealtimeClient + OrderedSyncController.
    /// When false: legacy RoomView + WebSocketClient + SyncEngine.
    public static var realtimeProtocolV2: Bool {
        // Read from UserDefaults or remote config — default false for safety
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

    public func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot] {
        // TODO: GET /api/rooms/:id/participants — needs backend endpoint
        // For now, return empty — participant events will still arrive via WS
        return []
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

private struct MessageDTO: Decodable {
    let messageId: String
    let clientMessageId: String?
    let senderId: String
    let senderName: String
    let text: String
    let createdAtMs: Int64
}

// MARK: - Legacy wrapper (for rollback path)

/// Wrapper for legacy RoomView when feature flag is off.
/// Real RoomView is still in Plink/Views/Room/RoomView.swift.
private struct LegacyRoomViewWrapper: View {
    let roomId: String
    let authToken: String

    var body: some View {
        // Placeholder — real legacy RoomView would be here.
        // For now, show a message that legacy path is active.
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Legacy path active")
                .font(.headline)
            Text("Enable plink.realtime_protocol_v2 in UserDefaults to use v2.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
