import Foundation

// MARK: - NativeYouTubeExtractor (Pure Swift, TVHTML5 stateless)
//
// 🔧 v50.2: Stateless TVHTML5 client — no cookies, no visitorData, no watch page.
// Previous approaches failed:
//   - WEB client: UNPLAYABLE (requires BotGuard po_token)
//   - IOS client: FAILED_PRECONDITION (web cookies + mobile profile mismatch)
//   - TVHTML5 + web cookies: UNPLAYABLE "The page needs to be reloaded" (context mismatch)
//
// TVHTML5 works best when stateless — Smart TVs don't visit watch pages first.
// They just POST to youtubei/v1/player directly with their TV profile.

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
        // 🔧 v50.2: NO cookie storage — TVHTML5 is stateless
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func extract(videoId: String) async throws -> StreamInfo {
        if let cached = cache[videoId], cached.expires > Date() {
            print("📺 YouTubeExtractor: cache hit for \(videoId)")
            return cached.info
        }

        print("📺 YouTubeExtractor v50.2: extracting \(videoId) (Stateless TVHTML5)")

        // Single POST request — no watch page, no cookies, no visitorData
        let streamInfo = try await postPlayerAPI(videoId: videoId)

        cache[videoId] = (streamInfo, Date().addingTimeInterval(cacheTTL))
        print("✅ YouTubeExtractor v50.2: succeeded, extractor=\(streamInfo.extractor)")
        return streamInfo
    }

    // MARK: - POST to youtubei/v1/player (Stateless TVHTML5)

    private func postPlayerAPI(videoId: String) async throws -> StreamInfo {
        let apiUrl = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 🔧 v50.2: Smart TV User-Agent — no cookies, no Origin, no Referer
        request.setValue(
            "Mozilla/5.0 (SmartHub; SMART-TV; U; Linux/SmartTV) AppleWebKit/531.2+ (KHTML, like Gecko) WebBrowser/1.0 SmartTV Safari/531.2+",
            forHTTPHeaderField: "User-Agent"
        )

        // Generate cpn (Client Playback Nonce)
        let cpn = generateCPN()

        // 🔧 v50.2: Pure TVHTML5 payload — no visitorData, no cookies
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "TVHTML5",
                    "clientVersion": "7.20230407.00.00",
                    "deviceMake": "Samsung",
                    "deviceModel": "SmartTV",
                    "userAgent": "Mozilla/5.0 (SmartHub; SMART-TV; U; Linux/SmartTV) AppleWebKit/531.2+ (KHTML, like Gecko) WebBrowser/1.0 SmartTV Safari/531.2+",
                    "osName": "Tizen",
                    "osVersion": "4.0",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId,
            "playbackContext": [
                "contentPlaybackContext": [
                    "signatureTimestamp": 19900
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
            print("❌ YouTubeExtractor: no streamingData")
            throw YouTubeExtractorError.noStreamingData
        }

        let videoDetails = json["videoDetails"] as? [String: Any]

        // Priority 1: HLS manifest (best for AVPlayer)
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

        // Priority 2: muxed formats
        if let formats = streamingData["formats"] as? [[String: Any]], !formats.isEmpty {
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

        // Priority 3: adaptiveFormats — check if any have direct URL (no signatureCipher)
        if let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            let withUrl = adaptiveFormats.filter { ($0["url"] as? String)?.isEmpty == false }
            if let best = withUrl.first,
               let url = best["url"] as? String, !url.isEmpty {
                print("📺 YouTubeExtractor: using adaptive format (direct URL)")
                return StreamInfo(
                    id: videoId,
                    title: videoDetails?["title"] as? String ?? "Unknown",
                    author: videoDetails?["author"] as? String ?? "Unknown",
                    thumbnailURL: extractThumbnail(videoDetails: videoDetails, videoId: videoId),
                    streamURL: url,
                    duration: Double(videoDetails?["lengthSeconds"] as? String ?? "0") ?? 0,
                    isLive: videoDetails?["isLive"] as? Bool ?? false,
                    extractor: "native-adaptive"
                )
            }
        }

        print("❌ YouTubeExtractor: no playable formats found")
        throw YouTubeExtractorError.noFormats
    }

    // MARK: - Helpers

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

enum YouTubeExtractorError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidJSON
    case playabilityError(String)
    case noStreamingData
    case noFormats

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from YouTube"
        case .httpError(let code): return "YouTube returned HTTP \(code)"
        case .invalidJSON: return "Invalid JSON from YouTube"
        case .playabilityError(let reason): return "Video not playable: \(reason)"
        case .noStreamingData: return "No streaming data in response"
        case .noFormats: return "No playable formats found"
        }
    }
}
