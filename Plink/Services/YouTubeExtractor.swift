import Foundation
import WebKit

// MARK: - YouTubeExtractor (DOM Scraper — instant extraction)
//
// 🔧 v51.6: DOM Scraping approach — no network hooks, no autoplay needed.
// Scrapes ytInitialPlayerResponse.streamingData.hlsManifestUrl directly.
// Works in 0.5-1 second, no dependency on autoplay or Page Visibility.

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

        print("📺 YouTubeExtractor v51.6: extracting \(videoId) (DOM Scraper)")

        let streamURL = try await HybridHookExtractor.extract(videoId: videoId)

        print("✅ YouTubeExtractor v51.6: got stream URL, prefix=\(streamURL.prefix(60))")

        let info = StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: streamURL,
            duration: 0,
            isLive: false,
            extractor: "dom-scraper"
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

// MARK: - Hybrid Hook Extractor (DOM Scraper)

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

        // 🔧 v51.6 (Gemini): DOM Scraper — scrapes ytInitialPlayerResponse directly.
        // No fetch/XHR hooks needed. Just read the JSON that YouTube embeds in the page.
        let scraperScript = WKUserScript(source: """
        // 🔧 v51.6 (Gemini): Spoof Page Visibility API (helps page render faster)
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
        Object.defineProperty(document, 'hidden', { get: () => false });

        var scraperInterval = setInterval(function() {
            try {
                // Auto-click consent banner or play button
                var consentBtn = document.querySelector('button[aria-label="Accept all"]') || document.querySelector('.ytp-large-play-button');
                if (consentBtn) consentBtn.click();

                var sd = null;

                // Method 1: Direct access (desktop sometimes works)
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                    sd = window.ytInitialPlayerResponse.streamingData;
                }

                // Method 2: Hardcoded regex parse of HTML (always works on desktop)
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

                // Method 3: ytplayer.config fallback
                if (!sd && window.ytplayer && window.ytplayer.config) {
                    var raw = window.ytplayer.config.args.raw_player_response;
                    if (raw) {
                        var parsed = JSON.parse(raw);
                        if (parsed.streamingData) sd = parsed.streamingData;
                    }
                }

                if (sd) {
                    var targetUrl = null;

                    // Priority A: HLS Manifest
                    if (sd.hlsManifestUrl) {
                        targetUrl = sd.hlsManifestUrl;
                    } else if (sd.formats && sd.formats.length > 0) {
                        // Priority B: Direct MP4 (itag 22=720p, 18=360p)
                        var bestFormat = sd.formats.find(function(f) { return f.itag === 22 || f.itag === 18; }) || sd.formats[0];
                        if (bestFormat) targetUrl = bestFormat.url;
                    }

                    if (targetUrl) {
                        clearInterval(scraperInterval);
                        window.webkit.messageHandlers.hook.postMessage(targetUrl);
                    }
                }
            } catch(e) {}
        }, 500);
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        config.userContentController.addUserScript(scraperScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        // 🔧 v51.8 (Gemini): Desktop Mac Safari UA — always embeds ytInitialPlayerResponse
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        print("📺 HybridHookExtractor: loading watch page for \(videoId)")
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))

        // Internal timeout — guarantees continuation.resume
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            print("⏰ HybridHookExtractor: 15s timeout — finishing with error")
            self?.finish(with: .failure(YouTubeExtractorError.timedOut))
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isFinished else { return }

        // 🔧 v51.7 (Gemini): Accept HLS (.m3u8) OR direct MP4 (videoplayback)
        if let url = message.body as? String,
           url.contains(".m3u8") || url.contains("videoplayback") {
            print("🎯 HybridHookExtractor: SCRAPER found URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 HybridHookExtractor: watch page loaded, scraping for HLS URL...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor: navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor: provisional navigation failed: \(error.localizedDescription)")
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
