import Foundation

// MARK: - YouTube Extractor (iOS-side)
//
// 🔧 v46.1: WebView-only approach. Extraction is handled by the WKWebView
// loading m.youtube.com directly. No XCDYouTubeKit, no backend extraction.
//
// The YouTubeExtractor now just validates the video ID and returns the
// embed URL. The actual playback happens through WKWebView (WebVideoView)
// which loads m.youtube.com and injects CSS/JS to control the player.
//
// The reload-on-fullscreen issue is fixed by REMOVING the needsFullReload
// logic in VideoContainerView. The WKWebView stays stable during rotation
// because the view tree doesn't change (unified layout).

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()

    private init() {}

    /// Extract stream info — returns embed URL for WebView playback.
    /// No actual extraction needed — WKWebView handles YouTube natively.
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
