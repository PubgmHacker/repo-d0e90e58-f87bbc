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
            return AnyView(Text("Legacy room view retired"))
        }
    }

    /// Derive PlaybackSource from room.mediaItem
    private static func mediaSourceFromRoom(_ room: Room) -> PlaybackSource? {
        guard let mediaItem = room.mediaItem else { return nil }
        // YouTube videoId → embedded player (App Store compliant)
        if let videoId = mediaItem.videoId, !videoId.isEmpty {
            return .youtube(videoId)
        }
        // PATCH 22: extract YouTube video ID from streamURL when videoId is nil.
        // YouTube URLs: youtu.be/ID, youtube.com/watch?v=ID, youtube.com/embed/ID
        if let ytId = extractYouTubeVideoId(from: mediaItem.streamURL) {
            return .youtube(ytId)
        }
        // Rutube (P0) — wire embed to sync controller
        if let rtId = extractRutubeVideoId(from: mediaItem.streamURL) {
            return .rutube(rtId)
        }
        // VK Video (P0)
        if let vkId = extractVKVideoId(from: mediaItem.streamURL) {
            return .vk(vkId)
        }
        // Cinema / generic web embeds (Kinopoisk, Ivi, Okko, browser, custom pages)
        if let embedURL = makeEmbedURL(from: mediaItem) {
            return .embed(embedURL)
        }
        // Direct stream URL → native AVPlayer
        let urlString = mediaItem.streamURL
        if let url = URL(string: urlString) {
            if urlString.contains(".m3u8") {
                return .hls(url, headers: [:])
            }
            if urlString.contains(".mp4") || urlString.hasSuffix(".mov") {
                return .mp4(url, headers: [:])
            }
            // Don't return .mp4 for non-video URLs (e.g. youtube.com pages).
        }
        return nil
    }

    /// PATCH 22: extract 11-char YouTube video ID from various URL formats.
    /// - https://youtu.be/VIDEO_ID
    /// - https://www.youtube.com/watch?v=VIDEO_ID
    /// - https://www.youtube.com/embed/VIDEO_ID
    /// - https://youtube.com/shorts/VIDEO_ID
    private static func extractYouTubeVideoId(from url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return nil }

        // youtu.be/VIDEO_ID
        if lower.contains("youtu.be/") {
            let parts = url.split(separator: "/")
            if let last = parts.last {
                let id = String(last).split(separator: "?").first.map(String.init) ?? String(last)
                if id.count == 11 { return id }
            }
        }

        // youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(string: url) {
            if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
                if vParam.count == 11 { return vParam }
            }
        }

        // youtube.com/embed/VIDEO_ID or youtube.com/shorts/VIDEO_ID
        if lower.contains("/embed/") || lower.contains("/shorts/") {
            let parts = url.split(separator: "/")
            if let last = parts.last {
                let id = String(last).split(separator: "?").first.map(String.init) ?? String(last)
                if id.count == 11 { return id }
            }
        }

        return nil
    }

    /// P1: Cinema & generic embed support.
    /// Returns a URL suitable for loading in EmbedPlaybackController when the item
    /// is a cinema service page, browser page, or any non-direct web content.
    private static func makeEmbedURL(from mediaItem: MediaItem) -> URL? {
        let urlString = mediaItem.streamURL
        guard let url = URL(string: urlString) else { return nil }

        let lower = urlString.lowercased()

        // Explicit cinema services or known patterns
        let cinemaHosts = ["kinopoisk", "ivi", "okko", "wink", "start", "premier", "smotrim", "kion", "netflix", "disney"]
        let isCinema = cinemaHosts.contains { lower.contains($0) } || mediaItem.source.rawValue == "url" && !isDirectStream(urlString)

        // Browser / custom pages that are not direct media files
        let isBrowserOrCustom = lower.contains("browser") || mediaItem.source == .url && !isDirectStream(urlString)

        if isCinema || isBrowserOrCustom || lower.contains("http") {
            // Prefer the original page URL for cinema (user sees the real player + chrome)
            return url
        }
        return nil
    }

    private static func isDirectStream(_ url: String) -> Bool {
        let l = url.lowercased()
        return l.hasSuffix(".mp4") || l.hasSuffix(".m3u8") || l.contains(".m3u8?") || l.contains("googlevideo")
    }

    /// P0: extract VK id from video_ext or video URL.
    private static func extractVKVideoId(from url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("vk.com") || lower.contains("vk.ru") else { return nil }
        if lower.contains("video_ext.php") {
            // keep query as the id
            if let q = url.split(separator: "?").last { return String(q) }
        }
        // vk.com/video-123_456 or /video/123_456
        if let range = lower.range(of: "/video") {
            let tail = url[range.upperBound...]
            let idPart = tail.split(separator: "/").first.map(String.init) ?? ""
            if idPart.contains("_") || idPart.count > 3 { return idPart }
        }
        return nil
    }

    /// PATCH P0: extract Rutube video ID from embed or public URL.
    /// Supports /play/embed/ID/ and /video/ID/
    private static func extractRutubeVideoId(from url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("rutube") else { return nil }

        // /play/embed/VIDEO_ID/
        if let range = lower.range(of: "/play/embed/") {
            let after = url[range.upperBound...]
            let id = after.split(separator: "/").first.map(String.init) ?? ""
            if id.count >= 8 { return id } // accept variable length ids
        }
        // /video/VIDEO_ID/
        if let range = lower.range(of: "/video/") {
            let after = url[range.upperBound...]
            let id = after.split(separator: "/").first.map(String.init) ?? ""
            if id.count >= 8 { return id }
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

// MARK: - Feature flags (P1-56/P1-59: remote config with cached fallback)

public enum FeatureFlags {
    private static let cacheKey = "plink.feature_flags_cache"
    private static let cacheTTL: TimeInterval = 300  // 5 minutes

    /// P0-37: master switch for v2 realtime + playback path.
    /// P1-56: checks remote config first (cached), falls back to UserDefaults.
    public static var realtimeProtocolV2: Bool {
        // P1-56: UserDefaults is DEBUG override only
        if UserDefaults.standard.bool(forKey: "plink.realtime_protocol_v2_debug") {
            return true
        }
        // P1-59: check cached remote config
        return true  // P1-56: temporarily forced TRUE for v2 testing
    }

    /// P1-56: cached remote flags fetched from backend
    private static var cachedRemoteFlags: [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(RemoteFlagCache.self, from: data),
              Date().timeIntervalSince(cache.fetchedAt) < cacheTTL else {
            return [:]
        }
        return cache.flags
    }

    /// P1-56: fetch remote flags from backend — call on app launch
    public static func fetchRemoteFlags(apiBaseURL: URL, authToken: String) async {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/feature-flags"))
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode([RemoteFlagDTO].self, from: data)
            var flags: [String: Bool] = [:]
            for flag in decoded {
                flags[flag.key] = (flag.value.lowercased() == "true")
            }
            let cache = RemoteFlagCache(flags: flags, fetchedAt: Date())
            if let cacheData = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(cacheData, forKey: cacheKey)
            }
        } catch {
            // Network error — keep using cached/UserDefaults
        }
    }
}

private struct RemoteFlagCache: Codable {
    let flags: [String: Bool]
    let fetchedAt: Date
}

private struct RemoteFlagDTO: Decodable {
    let key: String
    let value: String
}

// MARK: - REST chat catch-up client (P0-35 + P1-55 auth refresh)

public final class RESTChatCatchupClient: ChatCatchupClient, @unchecked Sendable {
    private let baseURL: URL
    // P1-55: use AuthTokenProvider instead of fixed String
    private let tokenProvider: AuthTokenProvider?

    public init(baseURL: URL, authToken: String) {
        self.baseURL = baseURL
        self.tokenProvider = nil  // Legacy mode — fixed token
        self._fixedToken = authToken
    }

    // P1-55: init with token provider for refresh support
    public init(baseURL: URL, tokenProvider: AuthTokenProvider) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self._fixedToken = nil
    }

    private var _fixedToken: String?

    // P1-55: currentToken must hop to MainActor since AuthTokenProvider is @MainActor
    private func currentToken() async -> String? {
        if let provider = tokenProvider {
            return await MainActor.run { provider.currentToken }
        }
        return _fixedToken
    }

    // P1-55: refresh-on-401 helper
    private func refreshToken() async -> String? {
        if let provider = tokenProvider {
            return await provider.refreshToken()
        }
        return _fixedToken
    }

    // P1-55: make request with auth, retry on 401
    private func makeAuthenticatedRequest(url: URL) async throws -> (Data, HTTPURLResponse) {
        guard let token = await currentToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // P1-55: on 401, refresh token and retry once
        if http.statusCode == 401, let newToken = await refreshToken() {
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
            guard let http2 = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http2.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            if http2.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            return (data, http2)
        }

        if http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    public func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/rooms/\(roomId)/messages"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "limit", value: "100")]
        if let after = after {
            items.append(URLQueryItem(name: "cursor", value: after))
        }
        components.queryItems = items

        let (data, _) = try await makeAuthenticatedRequest(url: components.url!)
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
            hasMore: decoded.hasMore,
            nextCursor: decoded.nextCursor
        )
    }

    public func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot] {
        let url = baseURL.appendingPathComponent("api/rooms/\(roomId)/participants")
        let (data, _) = try await makeAuthenticatedRequest(url: url)
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
    let nextCursor: String?  // P0-59: opaque server cursor
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
