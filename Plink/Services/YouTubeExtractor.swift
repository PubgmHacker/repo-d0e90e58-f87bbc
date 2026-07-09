import Foundation

// MARK: - NativeYouTubeExtractor (Pure Swift, no XCDYouTubeKit)
//
// 🔧 v50: Complete rewrite based on Gemini's BotGuard bypass strategy.
// XCDYouTubeKit (Obj-C, 10 years old) cannot bypass modern YouTube BotGuard.
// This pure Swift extractor implements a two-step process:
//   1. GET watch page → extract visitorData + cookies
//   2. POST youtubei/v1/player with IOS client + visitorData + cpn
//
// This mimics a real iOS YouTube app session and bypasses BotGuard.

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private let session: URLSession
    private var cache: [String: (info: StreamInfo, expires: Date)] = [:]
    private let cacheTTL: TimeInterval = 30 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func extract(videoId: String) async throws -> StreamInfo {
        // Check cache
        if let cached = cache[videoId], cached.expires > Date() {
            print("📺 YouTubeExtractor: cache hit for \(videoId)")
            return cached.info
        }

        print("📺 YouTubeExtractor v50: extracting \(videoId) (Pure Swift, BotGuard bypass)")

        // Step 1: Fetch watch page to get visitorData + cookies
        let sessionData = try await fetchWatchPage(videoId: videoId)
        print("📺 YouTubeExtractor: got visitorData=\(sessionData.visitorData?.prefix(20) ?? "nil"), cookies=\(sessionData.cookies.count)")

        // Step 2: POST to youtubei/v1/player with full session context
        let streamInfo = try await postPlayerAPI(
            videoId: videoId,
            visitorData: sessionData.visitorData,
            cookies: sessionData.cookies
        )

        // Cache successful result
        cache[videoId] = (streamInfo, Date().addingTimeInterval(cacheTTL))
        print("✅ YouTubeExtractor v50: succeeded, extractor=\(streamInfo.extractor)")
        return streamInfo
    }

    // MARK: - Step 1: Fetch Watch Page

    private struct SessionData {
        let visitorData: String?
        let cookies: [HTTPCookie]
    }

    private func fetchWatchPage(videoId: String) async throws -> SessionData {
        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        var request = URLRequest(url: watchURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (_, response) = try await session.data(for: request)

        // Extract cookies from response
        let cookies = HTTPCookieStorage.shared.cookies(for: watchURL) ?? []
        print("📺 YouTubeExtractor: cookies from watch page: \(cookies.map { $0.name }.joined(separator: ", "))")

        // Extract visitorData from HTML
        let visitorData = try await extractVisitorData(from: watchURL)
        print("📺 YouTubeExtractor: visitorData extracted: \(visitorData != nil)")

        return SessionData(visitorData: visitorData, cookies: cookies)
    }

    private func extractVisitorData(from url: URL) async throws -> String? {
        // Re-fetch as string to parse HTML
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // Try to find "visitorData":"..." in HTML
        if let range = html.range(of: "\"visitorData\":\"") {
            let start = range.upperBound
            let endRange = html[start...].range(of: "\"")
            if let end = endRange {
                return String(html[start..<end.lowerBound])
            }
        }

        // Also try ytcfg.set({ visitorData: ... })
        if let range = html.range(of: "visitorData: '") {
            let start = range.upperBound
            let endRange = html[start...].range(of: "'")
            if let end = endRange {
                return String(html[start..<end.lowerBound])
            }
        }

        // Also try "VISITOR_DATA":"..."
        if let range = html.range(of: "\"VISITOR_DATA\":\"") {
            let start = range.upperBound
            let endRange = html[start...].range(of: "\"")
            if let end = endRange {
                return String(html[start..<end.lowerBound])
            }
        }

        return nil
    }

    // MARK: - Step 2: POST to youtubei/v1/player

    private func postPlayerAPI(
        videoId: String,
        visitorData: String?,
        cookies: [HTTPCookie]
    ) async throws -> StreamInfo {

        let apiUrl = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "com.google.ios.youtube/19.29.1 (iPhone15,3; U; CPU iOS 17_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/watch?v=\(videoId)", forHTTPHeaderField: "Referer")

        // Generate cpn (Client Playback Nonce) — 16 random alphanumeric chars
        let cpn = generateCPN()

        // Build payload with IOS client + visitorData + cpn
        var clientDict: [String: Any] = [
            "clientName": "IOS",
            "clientVersion": "19.29.1",
            "deviceMake": "Apple",
            "deviceModel": "iPhone15,3",
            "hl": "en",
            "gl": "US",
            "osName": "iOS",
            "osVersion": "17.5.1"
        ]
        if let visitorData = visitorData {
            clientDict["visitorData"] = visitorData
        }

        let body: [String: Any] = [
            "context": ["client": clientDict],
            "videoId": videoId,
            "playbackContext": [
                "contentPlaybackContext": [
                    "signatureTimestamp": 20100
                ]
            ],
            "cpn": cpn
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw YouTubeExtractorError.invalidResponse
        }

        print("📺 YouTubeExtractor: player API HTTP \(http.statusCode), data=\(data.count) bytes")

        guard http.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("❌ YouTubeExtractor: HTTP \(http.statusCode): \(errorBody.prefix(300))")
            throw YouTubeExtractorError.httpError(http.statusCode)
        }

        // Parse JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeExtractorError.invalidJSON
        }

        let playabilityStatus = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "UNKNOWN"
        print("📺 YouTubeExtractor: playability=\(playabilityStatus)")

        guard playabilityStatus == "OK" || playabilityStatus == "LIVE_STREAM_OFFLINE" else {
            let reason = (json["playabilityStatus"] as? [String: Any])?["reason"] as? String ?? playabilityStatus
            print("❌ YouTubeExtractor: not playable: \(reason)")
            throw YouTubeExtractorError.playabilityError(reason)
        }

        guard let streamingData = json["streamingData"] as? [String: Any] else {
            throw YouTubeExtractorError.noStreamingData
        }

        let videoDetails = json["videoDetails"] as? [String: Any]

        // Priority 1: HLS manifest (best for AVPlayer — adaptive quality)
        if let hlsUrl = streamingData["hlsManifestUrl"] as? String, !hlsUrl.isEmpty {
            print("📺 YouTubeExtractor: using HLS manifest")
            return StreamInfo(
                id: videoId,
                title: videoDetails?["title"] as? String ?? "Unknown",
                author: videoDetails?["author"] as? String ?? "Unknown",
                thumbnailURL: extractThumbnail(videoDetails: videoDetails, videoId: videoId),
                streamURL: hlsUrl,
                duration: Double(videoDetails?["lengthSeconds"] as? String ?? "0") ?? 0,
                isLive: videoDetails?["isLive"] as? Bool ?? false,
                extractor: "native-hls"
            )
        }

        // Priority 2: muxed formats (formats[] array)
        if let formats = streamingData["formats"] as? [[String: Any]], !formats.isEmpty {
            // Sort by quality (itag 22=720p best, 18=360p fallback)
            let sorted = formats.sorted { a, b in
                let itagA = a["itag"] as? Int ?? 0
                let itagB = b["itag"] as? Int ?? 0
                let qualityOrder: [Int: Int] = [22: 720, 18: 360, 43: 360, 36: 240, 17: 144]
                let qa = qualityOrder[itagA] ?? 0
                let qb = qualityOrder[itagB] ?? 0
                return qa > qb
            }

            if let best = sorted.first,
               let url = best["url"] as? String, !url.isEmpty {
                let itag = best["itag"] as? Int ?? 0
                print("📺 YouTubeExtractor: using muxed format itag=\(itag)")
                return StreamInfo(
                    id: videoId,
                    title: videoDetails?["title"] as? String ?? "Unknown",
                    author: videoDetails?["author"] as? String ?? "Unknown",
                    thumbnailURL: extractThumbnail(videoDetails: videoDetails, videoId: videoId),
                    streamURL: url,
                    duration: Double(videoDetails?["lengthSeconds"] as? String ?? "0") ?? 0,
                    isLive: videoDetails?["isLive"] as? Bool ?? false,
                    extractor: "native"
                )
            }
        }

        throw YouTubeExtractorError.noFormats
    }

    // MARK: - Helpers

    /// Generate Client Playback Nonce (16 random alphanumeric chars)
    private func generateCPN() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }

    private func extractThumbnail(videoDetails: [String: Any]?, videoId: String) -> String {
        if let thumbnails = videoDetails?["thumbnail"] as? [String: Any],
           let thumbsArray = thumbnails["thumbnails"] as? [[String: Any]],
           let last = thumbsArray.last,
           let url = last["url"] as? String {
            return url
        }
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    /// Extract video ID from any YouTube URL format.
    static func extractVideoId(from url: String) -> String? {
        if let match = url.range(of: #"/([\w-]{11})(?:\?|$|/)"#, options: .regularExpression) {
            return String(url[match]).trimmingCharacters(in: CharacterSet(charactersIn: "/?"))
        }
        if let components = URLComponents(string: url),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        if let match = url.range(of: #"(?:embed|shorts)/([\w-]{11})"#, options: .regularExpression) {
            return String(url[match]).split(separator: "/").last.map(String.init)
        }
        return nil
    }
}

// MARK: - Models

struct StreamInfo {
    let id: String
    let title: String
    let author: String
    let thumbnailURL: String
    let streamURL: String
    let duration: TimeInterval
    let isLive: Bool
    let extractor: String
}

// MARK: - Errors

enum YouTubeExtractorError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidJSON
    case playabilityError(String)
    case noStreamingData
    case noFormats

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from YouTube"
        case .httpError(let code):
            return "YouTube returned HTTP \(code)"
        case .invalidJSON:
            return "Invalid JSON from YouTube"
        case .playabilityError(let reason):
            return "Video not playable: \(reason)"
        case .noStreamingData:
            return "No streaming data in response"
        case .noFormats:
            return "No playable formats found"
        }
    }
}
