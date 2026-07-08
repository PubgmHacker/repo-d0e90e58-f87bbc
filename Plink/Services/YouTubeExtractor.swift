import Foundation
import YouTubeKit

// MARK: - YouTube Extractor (iOS-side)
//
// 🔧 v47: Uses YouTubeKit (bclewaer) — modern Swift library with SPM support.
// XCDYouTubeKit failed SPM integration (Obj-C, old, package graph error).
// YouTubeKit is pure Swift, handles YouTube extraction for AVPlayer.

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private var cache: [String: (info: StreamInfo, expires: Date)] = [:]
    private let cacheTTL: TimeInterval = 30 * 60

    private init() {}

    func extract(videoId: String) async throws -> StreamInfo {
        if let cached = cache[videoId], cached.expires > Date() {
            print("📺 YouTubeExtractor: cache hit for \(videoId)")
            return cached.info
        }

        print("📺 YouTubeExtractor: extracting with YouTubeKit for \(videoId)")

        // YouTubeKit extracts video info including stream URLs
        let video = try await YouTubeKit.videoInfo(for: videoId)

        // Get best muxed stream URL (video+audio combined)
        // YouTubeKit provides streamURLs sorted by quality
        let streamURLs = video.streamURLs

        guard let bestStream = streamURLs
            .sorted(by: { $0.key > $1.key })
            .first else {
            print("❌ YouTubeExtractor: no stream URLs found")
            throw YouTubeExtractorError.noFormats
        }

        let url = bestStream.value
        let quality = bestStream.key

        print("✅ YouTubeExtractor: succeeded, quality=\(quality)p")

        let info = StreamInfo(
            id: videoId,
            title: video.title ?? "Unknown",
            author: video.author ?? "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: url.absoluteString,
            duration: video.lengthSeconds,
            isLive: false,
            extractor: "youtubekit"
        )

        cache[videoId] = (info, Date().addingTimeInterval(cacheTTL))
        return info
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
    case noFormats
    var errorDescription: String? {
        switch self {
        case .noFormats: return "No playable formats found"
        }
    }
}
