import Foundation
import WebKit

// MARK: - YouTubeExtractor (Regex DOM Scraper — MP4 for AVPlayer)
//
// 🔧 v60 (Gemini): Reverted to v51.8-style Regex DOM Scraper, but tuned to
// search for direct MP4 (itag 22 = 720p, itag 18 = 360p) instead of HLS.
// The v59 API Interceptor was too clever — its hooks fired too early
// (.atDocumentStart before page rendered), and YouTube's player code never
// made the /youtubei/v1/player call for many videos, so we timed out.
//
// The Regex DOM Scraper is simpler and more reliable: it waits for the
// page to load, then polls every 500ms for ytInitialPlayerResponse. When
// found, it extracts the muxed MP4 URL. For videos where YouTube doesn't
// embed the data (DRM, age-restricted, premium), it fails — but we have
// the graceful WebView fallback (v52) so the user still watches the video.
//
// Returns a clean .mp4 URL (itag 22 or 18) that AVPlayer plays natively
// (no -11850 DASH errors).

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

        print("📺 YouTubeExtractor v60: extracting \(videoId) (Regex DOM Scraper — MP4)")

        let streamURL = try await HybridHookExtractor.extract(videoId: videoId)

        print("✅ YouTubeExtractor v60: got stream URL, prefix=\(streamURL.prefix(80))")

        let info = StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: streamURL,
            duration: 0,
            isLive: false,
            extractor: "regex-dom-scraper-mp4"
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

// MARK: - Hybrid Hook Extractor (v60: Regex DOM Scraper — MP4)
//
// Loads youtube.com/watch?v=ID in invisible WKWebView with Desktop Mac Safari
// UA. Polls every 500ms for ytInitialPlayerResponse. When found, extracts
// muxed MP4 URL (itag 22 or 18) and posts to Swift.
//
// injectionTime: .atDocumentEnd — script starts AFTER page has loaded once,
// so ytInitialPlayerResponse is more likely to be present.

@MainActor
private final class HybridHookExtractor: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var isFinished = false
    private var selfRetain: HybridHookExtractor?
    private var timeoutTask: Task<Void, Never>?

    static func extract(videoId: String) async throws -> String {
        let extractor = HybridHookExtractor()
        return try await withCheckedThrowingContinuation { continuation in
            extractor.continuation = continuation
            extractor.selfRetain = extractor
            extractor.start(videoId: videoId)
        }
    }

    private func start(videoId: String) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 🔧 v60 (Gemini): Regex DOM Scraper — polls for ytInitialPlayerResponse,
        // extracts muxed MP4 (itag 22/18) for AVPlayer.
        //
        // injectionTime: .atDocumentEnd — script runs after the page has loaded
        // once, so ytInitialPlayerResponse is more likely to be present.
        let scraperScript = WKUserScript(source: """
        // 🔧 v60: Spoof Page Visibility API (helps page render faster)
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
        Object.defineProperty(document, 'hidden', { get: () => false });

        var scraperInterval = setInterval(function() {
            try {
                // Auto-click consent banner or play button
                var consentBtn = document.querySelector('button[aria-label="Accept all"]')
                              || document.querySelector('button[aria-label="Accept the use of cookies"]')
                              || document.querySelector('button[aria-label="I agree"]')
                              || document.querySelector('.ytp-large-play-button');
                if (consentBtn) consentBtn.click();

                var sd = null;

                // Method 1: Direct access to global variable (desktop sometimes works)
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                    sd = window.ytInitialPlayerResponse.streamingData;
                }

                // Method 2: Hardcoded regex parse of HTML (most reliable on desktop)
                // Searches all <script> tags for 'ytInitialPlayerResponse = {...};'
                if (!sd) {
                    var scripts = document.getElementsByTagName('script');
                    for (var i = 0; i < scripts.length; i++) {
                        if (scripts[i].innerHTML.indexOf('ytInitialPlayerResponse = ') !== -1) {
                            var match = scripts[i].innerHTML.match(/ytInitialPlayerResponse = ({.*?});/);
                            if (match && match[1]) {
                                var data = JSON.parse(match[1]);
                                if (data.streamingData) sd = data.streamingData;
                            }
                        }
                    }
                }

                // Method 3: ytplayer.config fallback (older player)
                if (!sd && window.ytplayer && window.ytplayer.config) {
                    var raw = window.ytplayer.config.args.raw_player_response;
                    if (raw) {
                        var parsed = JSON.parse(raw);
                        if (parsed.streamingData) sd = parsed.streamingData;
                    }
                }

                if (sd) {
                    var targetUrl = null;

                    // 🔧 v60: Priority A — muxed MP4 formats (itag 22=720p, 18=360p)
                    // These have audio + video in one file → AVPlayer plays natively.
                    if (sd.formats && sd.formats.length > 0) {
                        var bestFormat = sd.formats.find(function(f) { return f.itag === 22; })
                                       || sd.formats.find(function(f) { return f.itag === 18; })
                                       || sd.formats[0];
                        if (bestFormat) targetUrl = bestFormat.url;
                    }

                    // 🔧 v60: Priority B — HLS Manifest (fallback if no muxed MP4)
                    // AVPlayer handles .m3u8 too, though buffer management is different.
                    if (!targetUrl && sd.hlsManifestUrl) {
                        targetUrl = sd.hlsManifestUrl;
                    }

                    if (targetUrl) {
                        clearInterval(scraperInterval);
                        window.webkit.messageHandlers.hook.postMessage(targetUrl);
                    }
                }
            } catch(e) {}
        }, 500);
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        config.userContentController.addUserScript(scraperScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        // 🔧 v60: Desktop Mac Safari UA — YouTube returns formats[] (muxed MP4
        // with audio+video) for desktop clients, not adaptiveFormats (DASH
        // audio/video split which AVPlayer can't play → -11850 error).
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        print("📺 HybridHookExtractor v60: loading watch page for \(videoId)")
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))

        // Internal timeout — guarantees continuation.resume
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            print("⏰ HybridHookExtractor v60: 15s timeout — finishing with error")
            self?.finish(with: .failure(YouTubeExtractorError.timedOut))
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isFinished else { return }

        // 🔧 v60: Accept googlevideo.com (muxed MP4) OR .m3u8 (HLS manifest)
        if let url = message.body as? String,
           url.contains("googlevideo.com") || url.contains(".m3u8") {
            print("🎯 HybridHookExtractor v60: SCRAPER found URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 HybridHookExtractor v60: watch page loaded, polling for ytInitialPlayerResponse...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v60: navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v60: provisional navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    // MARK: - Cleanup

    private func finish(with result: Result<String, Error>) {
        guard !isFinished else { return }
        isFinished = true

        timeoutTask?.cancel()
        timeoutTask = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "hook")
        webView?.configuration.userContentController.removeAllUserScripts()
        webView = nil

        continuation?.resume(with: result)
        continuation = nil

        selfRetain = nil
    }

    nonisolated deinit {}
}

// MARK: - Models & Errors

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
