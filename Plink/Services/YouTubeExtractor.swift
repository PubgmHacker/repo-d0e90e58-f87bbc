import Foundation

// MARK: - YouTube Extractor (iOS-side)
//
// 🔧 v45: YouTube extraction moved from backend to iOS.
//
// PROBLEM: Backend (Railway) IP is blocked by YouTube — all extraction
// methods fail:
//   - yt-dlp: "Sign in to confirm you're not a bot" / "Requested format not available"
//   - YouTube Internal API (all clients): LOGIN_REQUIRED
//   - CORS proxies: 403/400 (don't support POST to youtubei)
//   - Invidious (7 instances): 401/403/404/fetch failed
//   - Piped (4 instances): fetch failed / Cloudflare HTML
//
// SOLUTION: Extract on iOS side. iPhone has RESIDENTIAL IP that YouTube
// doesn't block. The YouTube Internal API (youtubei.googleapis.com) works
// perfectly from iOS devices.
//
// This bypasses the backend entirely for YouTube — no Railway dependency.
// The extracted googlevideo.com URL is then played by AVPlayer directly.

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private let session: URLSession
    private let decoder = JSONDecoder()

    // Cache extracted streams (videoId → StreamInfo) for 30 minutes
    private var cache: [String: (info: StreamInfo, expires: Date)] = [:]
    private let cacheTTL: TimeInterval = 30 * 60  // 30 minutes

    /// 🔧 v45.1: Track whether we've fetched YouTube cookies.
    /// YouTube requires CONSENT + SAPISID cookies for some videos.
    /// We fetch them once from the watch page and the URLSession stores
    /// them automatically for subsequent requests.
    private var cookiesFetched = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        // 🔧 v45.1: enable cookie storage so YouTube cookies persist
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }

    /// 🔧 v45.1: Fetch YouTube watch page to get CONSENT + SAPISID cookies.
    /// These cookies are required for YouTube Internal API to return
    /// playable streams instead of UNPLAYABLE status.
    private func fetchYouTubeCookies() async {
        guard let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        do {
            let (_, _) = try await session.data(for: request)
            print("📺 YouTubeExtractor: fetched YouTube cookies")
        } catch {
            print("⚠️ YouTubeExtractor: cookie fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    /// Extract a direct stream URL from a YouTube video ID.
    /// Uses YouTube's Internal API (youtubei.googleapis.com) which works
    /// from iOS devices (residential IP, not blocked).
    ///
    /// - Parameter videoId: 11-character YouTube video ID
    /// - Returns: StreamInfo with direct googlevideo.com URL or HLS manifest URL
    func extract(videoId: String) async throws -> StreamInfo {
        // Check cache
        if let cached = cache[videoId], cached.expires > Date() {
            print("📺 YouTubeExtractor: cache hit for \(videoId)")
            return cached.info
        }

        // 🔧 v45.3: Primary method — scrape the watch page HTML.
        // The watch page contains ytInitialPlayerResponse JSON with
        // streamingData (formats + hlsManifestUrl). This is what yt-dlp
        // and NewPipe do — it's the most reliable method.
        do {
            print("📺 YouTubeExtractor: scraping watch page for \(videoId)")
            let info = try await extractFromWatchPage(videoId: videoId)
            cache[videoId] = (info, Date().addingTimeInterval(cacheTTL))
            print("✅ YouTubeExtractor: watch page extraction succeeded, extractor=\(info.extractor)")
            return info
        } catch {
            print("⚠️ YouTubeExtractor: watch page scraping failed: \(error.localizedDescription)")
        }

        // 🔧 v45.3: Fallback — YouTube Internal API (youtubei.googleapis.com)
        // Try multiple client types — different clients have different
        // format availability and bot detection.
        let clients: [(name: String, clientName: String, clientVersion: String, userAgent: String)] = [
            ("WEB", "WEB", "2.20240101.0.0",
             "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
            ("MWEB", "MWEB", "2.20240101.0.0",
             "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
            ("TVHTML5", "TVHTML5", "7.20240101.0.0",
             "Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"),
            ("ANDROID", "ANDROID", "19.09.37",
             "com.google.android.youtube/19.09.37 (Linux; U; Android 14; SM-S918B) gzip"),
            ("IOS", "IOS", "19.09.3",
             "com.google.ios.youtube/19.09.3 (iPhone15,3; U; CPU iOS 17_0 like Mac OS X)"),
        ]

        var lastError: String?

        for client in clients {
            do {
                print("📺 YouTubeExtractor: trying \(client.name) client for \(videoId)")
                let info = try await extractWithClient(
                    videoId: videoId,
                    clientName: client.clientName,
                    clientVersion: client.clientVersion,
                    userAgent: client.userAgent
                )

                // Cache successful result
                cache[videoId] = (info, Date().addingTimeInterval(cacheTTL))
                print("✅ YouTubeExtractor: \(client.name) succeeded, extractor=\(info.extractor)")
                return info
            } catch {
                lastError = "\(client.name): \(error.localizedDescription)"
                print("⚠️ YouTubeExtractor: \(client.name) failed — \(error.localizedDescription)")
            }
        }

        throw YouTubeExtractorError.allClientsFailed(lastError ?? "unknown")
    }

    /// 🔧 v45.3: Extract stream info by scraping the YouTube watch page HTML.
    /// The watch page contains `ytInitialPlayerResponse` JSON which has
    /// streamingData (formats[] + hlsManifestUrl).
    /// This is the same method yt-dlp and NewPipe use.
    private func extractFromWatchPage(videoId: String) async throws -> StreamInfo {
        // 🔧 v45.4: Try embed page first — it doesn't require CONSENT cookie
        // and always contains ytInitialPlayerResponse.
        // Watch page may redirect to consent page in EU/Russia.
        let embedUrl = URL(string: "https://www.youtube.com/embed/\(videoId)")!
        var request = URLRequest(url: embedUrl)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // 🔧 v45.4: Set CONSENT cookie to bypass EU consent page
        request.setValue("CONSENT=YES+cb.20210328-17-p0.en+FX+978", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            print("📺 YouTubeExtractor: embed page returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw YouTubeExtractorError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw YouTubeExtractorError.invalidJSON
        }

        print("📺 YouTubeExtractor: embed page fetched, \(html.count) chars, has ytInitialPlayerResponse: \(html.contains("ytInitialPlayerResponse"))")

        // Extract ytInitialPlayerResponse JSON from the HTML
        guard let playerResponseJson = extractJsonFromHtml(html, key: "ytInitialPlayerResponse") else {
            // Log first 300 chars to see what YouTube returned
            print("📺 YouTubeExtractor: HTML preview: \(html.prefix(300))")
            throw YouTubeExtractorError.invalidJSON
        }

        guard let playerData = playerResponseJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: playerData) as? [String: Any] else {
            throw YouTubeExtractorError.invalidJSON
        }

        let playabilityStatus = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
        let streamingData = json["streamingData"] as? [String: Any]
        let videoDetails = json["videoDetails"] as? [String: Any]

        print("📺 YouTubeExtractor: watch page playability=\(playabilityStatus), hasStreamingData=\(streamingData != nil)")

        guard playabilityStatus == "OK" || playabilityStatus == "LIVE_STREAM_OFFLINE" else {
            throw YouTubeExtractorError.playabilityError(playabilityStatus)
        }

        guard let streamingData = streamingData else {
            throw YouTubeExtractorError.noStreamingData
        }

        // Priority 1: HLS manifest (best for AVPlayer — adaptive quality)
        if let hlsUrl = streamingData["hlsManifestUrl"] as? String, !hlsUrl.isEmpty {
            print("📺 YouTubeExtractor: using HLS manifest from watch page")
            return StreamInfo(
                id: videoId,
                title: videoDetails?["title"] as? String ?? "Unknown",
                author: videoDetails?["author"] as? String ?? "Unknown",
                thumbnailURL: extractThumbnail(videoDetails: videoDetails, videoId: videoId),
                streamURL: hlsUrl,
                duration: Double(videoDetails?["lengthSeconds"] as? String ?? "0") ?? 0,
                isLive: videoDetails?["isLive"] as? Bool ?? false,
                extractor: "watchpage-hls"
            )
        }

        // Priority 2: muxed formats (formats[] array)
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
                print("📺 YouTubeExtractor: using muxed format itag=\(itag) from watch page")
                return StreamInfo(
                    id: videoId,
                    title: videoDetails?["title"] as? String ?? "Unknown",
                    author: videoDetails?["author"] as? String ?? "Unknown",
                    thumbnailURL: extractThumbnail(videoDetails: videoDetails, videoId: videoId),
                    streamURL: url,
                    duration: Double(videoDetails?["lengthSeconds"] as? String ?? "0") ?? 0,
                    isLive: videoDetails?["isLive"] as? Bool ?? false,
                    extractor: "watchpage"
                )
            }
        }

        throw YouTubeExtractorError.noFormats
    }

    /// Extract a JSON object from HTML by searching for `var key = {...};`
    /// or `key = {...};` pattern.
    private func extractJsonFromHtml(_ html: String, key: String) -> String? {
        // Search for: var ytInitialPlayerResponse = { ... };
        // or: ytInitialPlayerResponse = { ... };
        let patterns = [
            "var \(key) = ",
            "\(key) = ",
        ]

        for pattern in patterns {
            guard let range = html.range(of: pattern) else { continue }
            let jsonStart = html[range.upperBound...]

            // Find the matching closing brace by counting { and }
            var depth = 0
            var inString = false
            var escape = false
            var jsonEnd: String.Index?

            for (i, ch) in jsonStart.enumerated() {
                if escape {
                    escape = false
                    continue
                }
                if ch == "\\" {
                    escape = true
                    continue
                }
                if ch == "\"" {
                    inString.toggle()
                    continue
                }
                if inString { continue }

                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = jsonStart.index(jsonStart.startIndex, offsetBy: i)
                        break
                    }
                }
            }

            if let end = jsonEnd {
                return String(jsonStart[jsonStart.startIndex...end])
            }
        }

        return nil
    }

    /// Extract video ID from any YouTube URL format.
    static func extractVideoId(from url: String) -> String? {
        // youtu.be/ID
        if let match = url.range(of: #"/([\w-]{11})(?:\?|$|/)"#, options: .regularExpression) {
            return String(url[match]).trimmingCharacters(in: CharacterSet(charactersIn: "/?"))
        }
        // watch?v=ID
        if let components = URLComponents(string: url),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        // embed/ID or shorts/ID
        if let match = url.range(of: #"(?:embed|shorts)/([\w-]{11})"#, options: .regularExpression) {
            let substring = String(url[match])
            return substring.split(separator: "/").last.map(String.init)
        }
        return nil
    }

    // MARK: - Private

    private func extractWithClient(
        videoId: String,
        clientName: String,
        clientVersion: String,
        userAgent: String
    ) async throws -> StreamInfo {

        let apiUrl = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // 🔧 v45.1: Add Origin + Referer headers — YouTube requires these
        // to return playable streams. Without Origin, YouTube returns
        // UNPLAYABLE status (playability check fails).
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
        // 🔧 v45.1: Use YouTube's public API key — this is the same key
        // that youtube.com uses in the browser. It's not secret.
        request.setValue("AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", forHTTPHeaderField: "X-YouTube-Client-Key")

        // 🔧 v45.1: First fetch the YouTube watch page to get cookies.
        // YouTube requires CONSENT cookie + SAPISID for some videos.
        // We do this only once and cache the cookies in the session.
        if !cookiesFetched {
            await fetchYouTubeCookies()
            cookiesFetched = true
        }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": clientName,
                    "clientVersion": clientVersion,
                    "hl": "en",
                    "gl": "US",
                ]
            ],
            "videoId": videoId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw YouTubeExtractorError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw YouTubeExtractorError.httpError(http.statusCode)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeExtractorError.invalidJSON
        }

        let playabilityStatus = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
        let streamingData = json["streamingData"] as? [String: Any]
        let videoDetails = json["videoDetails"] as? [String: Any]

        print("📺 YouTubeExtractor: \(clientName) playability=\(playabilityStatus), hasStreamingData=\(streamingData != nil)")

        guard playabilityStatus == "OK" || playabilityStatus == "LIVE_STREAM_OFFLINE" else {
            throw YouTubeExtractorError.playabilityError(playabilityStatus)
        }

        guard let streamingData = streamingData else {
            throw YouTubeExtractorError.noStreamingData
        }

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
                extractor: "youtubei-hls"
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
                    extractor: "youtubei"
                )
            }
        }

        throw YouTubeExtractorError.noFormats
    }

    private func extractThumbnail(videoDetails: [String: Any]?, videoId: String) -> String {
        // Try to get thumbnail from videoDetails
        if let thumbnails = videoDetails?["thumbnail"] as? [String: Any],
           let thumbsArray = thumbnails["thumbnails"] as? [[String: Any]],
           let last = thumbsArray.last,
           let url = last["url"] as? String {
            return url
        }
        // Fallback: YouTube provides thumbnails at predictable URLs
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
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
    case allClientsFailed(String)
    case invalidResponse
    case httpError(Int)
    case invalidJSON
    case playabilityError(String)
    case noStreamingData
    case noFormats

    var errorDescription: String? {
        switch self {
        case .allClientsFailed:
            return "All YouTube clients failed"
        case .invalidResponse:
            return "Invalid response from YouTube"
        case .httpError:
            return "YouTube returned HTTP error"
        case .invalidJSON:
            return "Invalid JSON from YouTube"
        case .playabilityError:
            return "YouTube playability error"
        case .noStreamingData:
            return "No streaming data in response"
        case .noFormats:
            return "No playable formats found"
        }
    }
}
