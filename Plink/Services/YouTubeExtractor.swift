import Foundation

// MARK: - YouTube Extractor (iOS-side) — AVPlayer + XCDYouTubeKit
//
// 🔧 v48: IRONCLAD AVPlayer approach. No WKWebView, no reloads, no render death.
// XCDYouTubeKit source files are bundled directly (no SPM needed).
// Bridging header imports XCDYouTubeKit.h for Swift access.
//
// XCDYouTubeKit handles ALL YouTube complexity:
//   - Bot detection bypass
//   - Signature deciphering
//   - Format selection (muxed streams for AVPlayer)
//   - Age-restricted videos
//   - Cookie/auth handling

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private var cache: [String: (info: StreamInfo, expires: Date)] = [:]
    private let cacheTTL: TimeInterval = 30 * 60

    private init() {}

    /// Extract a direct stream URL from a YouTube video ID using XCDYouTubeKit.
    /// Returns googlevideo.com URL that AVPlayer can play natively.
    func extract(videoId: String) async throws -> StreamInfo {
        if let cached = cache[videoId], cached.expires > Date() {
            print("📺 YouTubeExtractor: cache hit for \(videoId)")
            return cached.info
        }

        print("📺 YouTubeExtractor: extracting with XCDYouTubeKit for \(videoId)")

        let video: XCDYouTubeVideo = try await withCheckedThrowingContinuation { continuation in
            XCDYouTubeClient.default().getVideoWithIdentifier(videoId) { video, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let video = video {
                    continuation.resume(returning: video)
                } else {
                    continuation.resume(throwing: YouTubeExtractorError.noFormats)
                }
            }
        }

        let streamURLs = video.streamURLs

        // Priority: HD720 > medium360 > small240
        // These are MUXED streams (video+audio combined) — AVPlayer plays them natively.
        let url = streamURLs[XCDYouTubeVideoQuality.HD720.rawValue]
                  ?? streamURLs[XCDYouTubeVideoQuality.medium360.rawValue]
                  ?? streamURLs[XCDYouTubeVideoQuality.small240.rawValue]
                  ?? streamURLs.values.first

        guard let streamURL = url else {
            print("❌ YouTubeExtractor: no stream URLs. Keys: \(streamURLs.keys)")
            throw YouTubeExtractorError.noFormats
        }

        let quality = streamURLs.first(where: { $0.value == streamURL })?.key as? Int ?? 0
        print("✅ YouTubeExtractor: succeeded, quality=\(quality)p, URL prefix=\(streamURL.absoluteString.prefix(60))")

        // thumbnailURL is deprecated, use thumbnailURLs if available
        let thumbnailString: String
        if let thumbURL = video.thumbnailURL {
            thumbnailString = thumbURL.absoluteString
        } else {
            thumbnailString = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        }

        let info = StreamInfo(
            id: videoId,
            title: video.title,
            author: video.author,
            thumbnailURL: thumbnailString,
            streamURL: streamURL.absoluteString,
            duration: video.duration,
            isLive: false,
            extractor: "xcdyoutubekit"
        )

        cache[videoId] = (info, Date().addingTimeInterval(cacheTTL))
        return info
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
    case noFormats
    var errorDescription: String? {
        switch self {
        case .noFormats: return "No playable formats found"
        }
    }
}
