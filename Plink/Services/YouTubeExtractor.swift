import Foundation
import XCDYouTubeKit

// MARK: - YouTube Extractor (iOS-side)
//
// 🔧 v46: Uses XCDYouTubeKit for reliable YouTube stream extraction.
// XCDYouTubeKit is a proven library (10+ years, used by many apps) that
// handles YouTube's complex extraction logic including:
//   - Bot detection bypass
//   - DASH format handling
//   - Age-restricted videos
//   - Format selection (muxed streams for AVPlayer)
//
// Previous approaches (v45) failed because:
//   - YouTube Internal API: UNPLAYABLE / LOGIN_REQUIRED
//   - Watch page scraping: ytInitialPlayerResponse not in HTML
//   - Backend yt-dlp: Railway IP blocked

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private var cache: [String: (info: StreamInfo, expires: Date)] = [:]
    private let cacheTTL: TimeInterval = 30 * 60

    private init() {}

    /// Extract a direct stream URL from a YouTube video ID using XCDYouTubeKit.
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

        let streamURLs = video.streamURLs ?? [:]
        let url = streamURLs[XCDYouTubeVideoQuality.HD720.rawValue]
                  ?? streamURLs[XCDYouTubeVideoQuality.medium360.rawValue]
                  ?? streamURLs[XCDYouTubeVideoQuality.small240.rawValue]
                  ?? streamURLs.values.first

        guard let streamURL = url else {
            print("❌ YouTubeExtractor: no stream URLs found. Available: \(streamURLs.keys)")
            throw YouTubeExtractorError.noFormats
        }

        let quality = streamURLs.first(where: { $0.value == streamURL })?.key ?? 0
        print("✅ YouTubeExtractor: XCDYouTubeKit succeeded, quality=\(quality)p")

        let info = StreamInfo(
            id: videoId,
            title: video.title ?? "Unknown",
            author: video.author ?? "Unknown",
            thumbnailURL: video.thumbnailURL?.absoluteString ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
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
            let substring = String(url[match])
            return substring.split(separator: "/").last.map(String.init)
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
        case .noFormats:
            return "No playable formats found"
        }
    }
}
