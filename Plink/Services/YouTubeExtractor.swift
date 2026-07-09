import Foundation

// MARK: - YouTube Extractor (iOS-side)
//
// 🔧 v47.1: WebView approach. No third-party libraries needed.
// Extraction returns embed URL — WKWebView handles YouTube playback.
// The reload-on-fullscreen is fixed by the unified layout (v46.1)
// which keeps the view tree stable during rotation.

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private init() {}

    func extract(videoId: String) async throws -> StreamInfo {
        print("📺 YouTubeExtractor: returning embed URL for \(videoId)")

        let embedURL = "https://www.youtube.com/embed/\(videoId)?playsinline=1&rel=0"

        return StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: embedURL,
            duration: 0,
            isLive: false,
            extractor: "webview"
        )
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
