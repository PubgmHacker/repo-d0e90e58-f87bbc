import Foundation
import WebKit

// MARK: - YouTubeExtractor (v61: WebView-first, no extraction)
//
// 🔧 v61 (Gemini): WebView-first architecture. We no longer attempt YouTube
// URL extraction. YouTube updates its BotGuard signatures every ~48 hours,
// breaking extractors. The embed URL via WKWebView is stable, passes Google's
// checks automatically, and works for all videos including DRM/age-restricted.
//
// This file now only provides the static extractVideoId(from:) helper used
// by RoomCreationView to prewarm the WKWebView. The actual playback happens
// via WKWebView in WebVideoView (VideoContainerView.swift).
//
// Architecture:
//   1. User selects YouTube video in RoomCreationView
//   2. YouTubeExtractor.extractVideoId(from: url) parses the video ID
//   3. WebViewControl.shared.prewarm(videoId:) starts loading m.youtube.com
//   4. User taps "Create Room" → RoomSetupView builds embed URL
//   5. RoomView.makeUIView consumes the prewarmed WKWebView → instant playback

@MainActor
final class YouTubeExtractor {

    static let shared = YouTubeExtractor()
    private init() {}

    /// Extract YouTube video ID from any URL format.
    /// Used by RoomCreationView to prewarm the WKWebView.
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

// MARK: - Models (kept for compatibility — may be used elsewhere)

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
    case timedOut
    case noStreamFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .timedOut: return "Превышено время ожидания (15 сек)"
        case .noStreamFound: return "Не удалось извлечь URL видеопотока"
        case .invalidResponse: return "Неверный ответ от YouTube"
        }
    }
}
