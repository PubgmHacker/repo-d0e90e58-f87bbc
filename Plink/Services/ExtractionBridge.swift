import Foundation
import WebKit

// MARK: - ExtractionBridge (v90 — Headless WKWebView Scraper)
//
// 🔧 v90 (Gemini): Separate invisible WKWebView that ONLY extracts stream URL.
// Does NOT play video. After extraction, WKWebView is released.
//
// Strategy:
//   1. Load m.youtube.com/watch?v=ID with iOS Safari UA
//   2. Poll for ytInitialPlayerResponse (in HTML or window variable)
//   3. Extract itag 22 (720p MP4) or itag 18 (360p MP4) — AVPlayer plays natively
//   4. Fallback: hlsManifestUrl (.m3u8) — AVPlayer handles HLS too
//   5. Return StreamInfo to caller (NativePlayerEngine)
//   6. Release WKWebView (don't keep in memory — Gemini recommendation)
//
// Why this avoids ban:
//   - IP = iPhone (residential, not server)
//   - UA = iOS Safari (YouTube trusts mobile browsers)
//   - No API calls (no /youtubei/v1/player → no BotGuard check)
//   - Just HTML scrape (parses <script> tags)

@MainActor
final class ExtractionBridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    static let shared = ExtractionBridge()

    struct StreamInfo {
        let streamURL: String
        let title: String
        let duration: TimeInterval
        /// 🔧 v92: Cookies captured during extraction — needed by AVPlayer
        /// to avoid 403 Forbidden from YouTube.
        let cookies: [HTTPCookie]
    }

    enum ExtractionError: LocalizedError {
        case timeout
        case noStreamFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .timeout: return "Превышено время ожидания (30 сек)"
            case .noStreamFound: return "Не удалось извлечь URL видеопотока"
            case .invalidResponse: return "Неверный ответ от YouTube"
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<StreamInfo, Error>?
    private var isFinished = false
    private var timeoutTask: Task<Void, Never>?

    /// 🔧 v92: Last captured cookies — stored so RoomView can pass them
    /// to NativePlayerEngine when loading the stream URL.
    private(set) var lastCookies: [HTTPCookie] = []

    /// Extract direct stream URL from YouTube video.
    /// Creates a temporary headless WKWebView, scrapes HTML, returns StreamInfo.
    /// WKWebView is released after extraction (not kept as singleton).
    /// Also captures cookies for use by NativePlayerEngine's ResourceLoader.
    func extract(videoId: String) async throws -> StreamInfo {
        // Reset state
        isFinished = false
        webView?.stopLoading()
        webView = nil
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        // 🔧 v92: Use DEFAULT (persistent) data store so cookies are shared
        // with AVPlayer's URLSession. YouTube requires matching cookies
        // between extraction and playback — otherwise 403 Forbidden.
        let cookieStore = WKWebsiteDataStore.default()

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []

            // 🔧 v92: Use persistent store — cookies shared with AVPlayer
            config.websiteDataStore = cookieStore

            // Scraper script — injected at documentEnd
            let scraperScript = WKUserScript(
                source: Self.scraperJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(scraperScript)
            config.userContentController.add(self, name: "extractor")

            let wv = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                configuration: config
            )
            // iOS Safari UA — YouTube trusts this and serves full HTML
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
                                 "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
                                 "Mobile/15E148 Safari/604.1"
            wv.navigationDelegate = self
            self.webView = wv

            print("🔍 v90: ExtractionBridge — loading m.youtube.com/watch?v=\(videoId)")
            let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
            wv.load(URLRequest(url: url))

            // 30s timeout (v94.7: was 15s — not enough for VEVO/licensed content)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(ExtractionError.timeout))
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard !isFinished, message.name == "extractor" else { return }

        if let url = message.body as? String {
            // Accept googlevideo.com (MP4) or .m3u8 (HLS)
            if url.contains("googlevideo.com") || url.contains(".m3u8") {
                print("✅ v90: ExtractionBridge — found URL: \(url.prefix(80))")

                // 🔧 v92: Capture cookies before finishing.
                // YouTube requires matching cookies between extraction and playback.
                // Without cookies, AVPlayer gets 403 Forbidden.
                guard let webView = self.webView else {
                    finish(with: .success(StreamInfo(
                        streamURL: url, title: "", duration: 0, cookies: []
                    )))
                    return
                }

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self else { return }
                    print("🍪 v92: Captured \(cookies.count) cookies from YouTube")
                    self.lastCookies = cookies  // 🔧 v92: Store for NativePlayerEngine
                    self.finish(with: .success(StreamInfo(
                        streamURL: url,
                        title: "",
                        duration: 0,
                        cookies: cookies
                    )))
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🔍 v90: ExtractionBridge — page loaded, scraper running...")
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isFinished else { return }
        print("❌ v90: ExtractionBridge — navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isFinished else { return }
        print("❌ v90: ExtractionBridge — provisional nav failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    // MARK: - Cleanup

    private func finish(with result: Result<StreamInfo, Error>) {
        guard !isFinished else { return }
        isFinished = true

        timeoutTask?.cancel()
        timeoutTask = nil

        // Release WKWebView (Gemini recommendation: don't keep in memory)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "extractor")
        webView?.configuration.userContentController.removeAllUserScripts()
        webView = nil

        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: - Scraper JavaScript
    //
    // Polls every 500ms for ytInitialPlayerResponse. Uses 3 methods:
    // 1. Direct: window.ytInitialPlayerResponse.streamingData
    // 2. Regex: parse <script> tags for ytInitialPlayerResponse = {...};
    // 3. Fallback: ytplayer.config.args.raw_player_response
    //
    // Extracts: itag 22 (720p MP4) > itag 18 (360p MP4) > first format > hlsManifestUrl

    static let scraperJS = """
    (function() {
        var attempts = 0;
        var interval = setInterval(function() {
            attempts++;
            try {
                // Auto-click consent banner
                var consentBtn = document.querySelector('button[aria-label="Accept all"]')
                              || document.querySelector('button[aria-label="Accept the use of cookies"]')
                              || document.querySelector('.ytp-large-play-button');
                if (consentBtn) consentBtn.click();

                var sd = null;

                // Method 1: Direct access to global variable
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                    sd = window.ytInitialPlayerResponse.streamingData;
                }

                // Method 2: Regex parse <script> tags
                if (!sd) {
                    var scripts = document.getElementsByTagName('script');
                    for (var i = 0; i < scripts.length; i++) {
                        var html = scripts[i].innerHTML;
                        if (html.indexOf('ytInitialPlayerResponse') !== -1) {
                            var match = html.match(/ytInitialPlayerResponse\\s*=\\s*({.+?});/);
                            if (match && match[1]) {
                                var data = JSON.parse(match[1]);
                                if (data.streamingData) {
                                    sd = data.streamingData;
                                    break;
                                }
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

                    // Priority A: muxed MP4 formats (itag 22=720p, 18=360p)
                    var formats = sd.formats || [];
                    var best = formats.find(function(f) { return f.itag === 22; })
                               || formats.find(function(f) { return f.itag === 18; })
                               || formats[0];
                    if (best && best.url) {
                        targetUrl = best.url;
                    }

                    // Priority B: HLS Manifest
                    if (!targetUrl && sd.hlsManifestUrl) {
                        targetUrl = sd.hlsManifestUrl;
                    }

                    if (targetUrl) {
                        clearInterval(interval);
                        window.webkit.messageHandlers.extractor.postMessage(targetUrl);
                    }
                }
            } catch(e) {}
            if (attempts > 60) clearInterval(interval); // v94.7: 60 attempts × 500ms = 30s
        }, 500);
    })();
    """
}
