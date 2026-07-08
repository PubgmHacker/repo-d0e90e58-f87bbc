import Foundation

// MARK: - Media Service
/// Bridges the iOS client to the backend's YouTube extractor endpoint.
/// Accepts a plain YouTube URL, calls POST /api/media/extract, and returns
/// a direct stream URL (.mp4 / .m3u8) ready for AVPlayer.
///
/// ┌──────────────────────────────────────────────────────┐
/// │  iOS Client         Backend (yt-dlp)        YouTube   │
/// │     │                    │                      │     │
/// │     │── POST extract ───▶│                      │     │
/// │     │   { url }          │── exec yt-dlp ─────▶│     │
/// │     │                    │◀── stream URL ──────│     │
/// │     │◀── { streamURL } ──│                      │     │
/// │     │                    │                      │     │
/// │     │── AVPlayer(url) ─────────────────────────────▶ │
/// └──────────────────────────────────────────────────────┘
///
/// Error handling covers:
/// - Network failures (retry with backoff)
/// - Video unavailable / private / age-restricted
/// - Rate limited by backend
/// - Invalid response shape

@MainActor
final class MediaService {

    // MARK: - Configuration

    private let apiBaseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Simple in-memory cache to avoid re-extracting the same video
    private var cache: [String: ExtractedMedia] = [:]

    init(apiBaseURL: String = "https://plink-backend-production-ef31.up.railway.app/api") {
        self.apiBaseURL = URL(string: apiBaseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45   // yt-dlp can take a while
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public API

    /// Extract a direct stream URL from a YouTube link.
    /// - Parameter youTubeURL: e.g. "https://youtube.com/watch?v=..." or
    ///   "https://www.youtube.com/embed/VIDEO_ID"
    /// - Returns: ExtractedMedia with a playable streamURL (.mp4 direct URL)
    ///
    /// 🔧 v44.1: backend endpoint is POST /api/media/extract (NOT /extract-url).
    /// Previous v8 comment said /extract-url but the actual backend route in
    /// media-v2.ts is /extract. This mismatch caused 500 errors.
    func extract(youTubeURL: String) async throws -> ExtractedMedia {
        // 0. Validate input (accept watch / youtu.be / embed / shorts URLs)
        guard isValidYouTubeURL(youTubeURL) else {
            throw MediaError.invalidURL
        }

        let videoID = extractVideoID(from: youTubeURL) ?? youTubeURL

        // 1. Cache hit?
        if let cached = cache[videoID] {
            return cached
        }

        // 2. Build request — POST /api/media/extract with {url}
        let endpoint = apiBaseURL.appendingPathComponent("media/extract")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Attach JWT if available
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 🔧 v8: backend extractStream expects a watch URL, not embed URL.
        // Convert embed → watch before sending.
        let urlToSend: String
        if youTubeURL.contains("youtube.com/embed/") {
            urlToSend = "https://www.youtube.com/watch?v=\(videoID)"
        } else {
            urlToSend = youTubeURL
        }

        let body = ExtractRequest(url: urlToSend)
        request.httpBody = try encoder.encode(body)

        // 3. Send (with one retry on transient failure)
        let data: Data
        do {
            data = try await performRequest(request)
        } catch {
            // Single retry for transient network blips
            data = try await performRequest(request)
        }

        // 4. Decode — backend /extract returns ExtractedMedia format:
        //    {sourceID, sourceName, mode, streamURL, title, thumbnailURL,
        //     duration, format, quality, requiresSubscription}
        // 🔧 v44.1: updated to match backend's actual response (mediaExtractor.ts).
        let response = try decoder.decode(ExtractResponse.self, from: data)

        // 5. Validate the stream URL is actually usable
        guard let streamURL = URL(string: response.streamURL),
              !response.streamURL.isEmpty else {
            throw MediaError.invalidStreamURL
        }

        let media = ExtractedMedia(
            id: response.sourceID ?? UUID().uuidString,
            title: response.title,
            artist: response.sourceName,
            thumbnailURL: response.thumbnailURL.flatMap(URL.init(string:)),
            streamURL: streamURL,
            duration: response.duration,
            format: response.format ?? "mp4",
            quality: response.quality ?? "unknown",
            isLive: false
        )

        // Cache it
        cache[videoID] = media
        return media
    }

    /// Validate a URL before committing to a full extraction (cheaper server call).
    func validate(url: String) async throws -> ValidationResult {
        let endpoint = apiBaseURL.appendingPathComponent("media/extract/validate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try encoder.encode(ValidateRequest(url: url))

        let data = try await performRequest(request)
        return try decoder.decode(ValidationResult.self, from: data)
    }

    /// Convert an ExtractedMedia into the app's MediaItem model for AVPlayer + sync.
    func makeMediaItem(from extracted: ExtractedMedia) -> MediaItem {
        MediaItem(
            id: extracted.id,
            title: extracted.title,
            artist: extracted.artist,
            thumbnailURL: extracted.thumbnailURL?.absoluteString,
            streamURL: extracted.streamURL.absoluteString,
            duration: extracted.duration,
            mediaType: extracted.isLive ? .livestream : .video,
            source: .youtube
        )
    }

    // MARK: - Auth

    /// JWT token — set after login. Required by the authenticated backend endpoint.
    private var authToken: String?

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Network

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MediaError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data

        case 401:
            throw MediaError.unauthorized

        case 404:
            throw MediaError.notFound

        case 422:
            // Backend says video unavailable / restricted
            let errBody = try? decoder.decode(ErrorBody.self, from: data)
            throw MediaError.videoUnavailable(errBody?.error ?? "Video unavailable")

        case 429:
            throw MediaError.rateLimited

        default:
            let errBody = try? decoder.decode(ErrorBody.self, from: data)
            throw MediaError.serverError(http.statusCode, errBody?.error)
        }
    }

    // MARK: - URL Validation

    private func isValidYouTubeURL(_ url: String) -> Bool {
        let patterns = [
            #"https?://(www\.)?youtube\.com/watch\?v=[\w-]+"#,
            #"https?://youtu\.be/[\w-]+"#,
            #"https?://(www\.)?youtube\.com/shorts/[\w-]+"#,
            #"https?://(www\.)?youtube\.com/embed/[\w-]+"#,
        ]
        return patterns.contains { pattern in
            url.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func extractVideoID(from url: String) -> String? {
        // youtu.be/<id>
        if let id = url.range(of: #"/([\w-]{11})(?:\?|$|/)"#, options: .regularExpression) {
            return String(url[id]).trimmingCharacters(in: CharacterSet(charactersIn: "/?"))
        }
        // watch?v=<id>
        if let components = URLComponents(string: url),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return nil
    }
}

// MARK: - DTOs

struct ExtractRequest: Codable {
    let url: String
}

struct ValidateRequest: Codable {
    let url: String
}

struct ExtractResponse: Codable {
    /// 🔧 v44.1: backend /extract returns ExtractedMedia (mediaExtractor.ts):
    /// { sourceID, sourceName, mode, streamURL, title, thumbnailURL,
    ///   duration, format, quality, requiresSubscription }
    /// All fields optional except streamURL + title — backend may omit others
    /// depending on the source.
    let sourceID: String?
    let sourceName: String?
    let mode: String?  // "native" | "webview"
    let streamURL: String
    let title: String
    let thumbnailURL: String?
    let duration: Double?
    let format: String?
    let quality: String?
    let requiresSubscription: Bool?
}

struct ExtractedMedia {
    let id: String
    let title: String
    let artist: String?
    let thumbnailURL: URL?
    let streamURL: URL
    let duration: Double?
    let format: String
    let quality: String
    let isLive: Bool
}

struct ValidationResult: Codable {
    let supported: Bool
    let type: String
    let message: String
}

private struct ErrorBody: Codable {
    let error: String
}

// MARK: - Errors

enum MediaError: LocalizedError {
    case invalidURL
    case invalidStreamURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case videoUnavailable(String)
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid YouTube link."
        case .invalidStreamURL:
            return "Couldn't get a playable stream from this video."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "The extraction endpoint was not found."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .videoUnavailable(let detail):
            return detail
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg ?? "unknown")"
        }
    }
}
