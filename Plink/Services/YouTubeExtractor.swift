import Foundation
import WebKit

// MARK: - YouTubeExtractor (API Interceptor — direct MP4 for AVPlayer)
//
// 🔧 v58 (Gemini): API Interceptor approach — intercepts YouTube's internal
// fetch/XHR to /youtubei/v1/player, extracts muxed MP4 (itag 22/18) for AVPlayer.
// Falls back to ytInitialPlayerResponse fast path if data is still in HTML.
//
// Why v58 replaces v51.6 DOM Scraper:
// YouTube stopped embedding ytInitialPlayerResponse in HTML for some videos
// (loads it dynamically via AJAX). The DOM scraper hit 15s timeout because
// it was waiting for data that never appeared in the page.
// v58 hooks window.fetch + XMLHttpRequest to catch the AJAX response directly.
// Returns a clean .mp4 URL that AVPlayer plays natively (no -11850 DASH errors).

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

        print("📺 YouTubeExtractor v58: extracting \(videoId) (API Interceptor)")

        let streamURL = try await HybridHookExtractor.extract(videoId: videoId)

        print("✅ YouTubeExtractor v58: got stream URL, prefix=\(streamURL.prefix(80))")

        let info = StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: streamURL,
            duration: 0,
            isLive: false,
            extractor: "api-interceptor"
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

// MARK: - Hybrid Hook Extractor (v58: API Interceptor)
//
// Hooks window.fetch + XMLHttpRequest at documentStart. When YouTube's player
// code calls /youtubei/v1/player to fetch streaming data, we intercept the
// JSON response and extract the muxed MP4 URL (itag 22 = 720p, itag 18 = 360p).
//
// Also keeps the ytInitialPlayerResponse fast path as a fallback for videos
// where YouTube still embeds the data in HTML.

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

        // 🔧 v58 (Gemini): API Interceptor — hooks fetch + XHR for /youtubei/v1/player
        // + keeps ytInitialPlayerResponse fast path as fallback.
        let interceptorScript = WKUserScript(source: """
        // ═══════════════════════════════════════════════════════════════
        // v58 API Interceptor (Gemini spec)
        // ═══════════════════════════════════════════════════════════════

        // Spoof Page Visibility API (helps YouTube serve full player response)
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
        Object.defineProperty(document, 'hidden', { get: () => false });

        var plinkDone = false;

        // Helper: extract best muxed MP4 URL from streamingData
        function plinkExtractMP4(sd) {
            if (!sd) return null;
            // Priority: itag 22 (720p MP4 with audio) > itag 18 (360p MP4 with audio) > first
            var formats = sd.formats || [];
            var best = formats.find(function(f) { return f.itag === 22; })
                       || formats.find(function(f) { return f.itag === 18; })
                       || formats[0];
            return best ? best.url : null;
        }

        // Helper: post URL to Swift (only if it's a real googlevideo URL or HLS)
        function plinkPostURL(url) {
            if (plinkDone || !url) return false;
            if (url.indexOf('googlevideo.com') !== -1 || url.indexOf('.m3u8') !== -1) {
                plinkDone = true;
                try { window.webkit.messageHandlers.hook.postMessage(url); } catch(e) {}
                return true;
            }
            return false;
        }

        // ─── Fast Path: ytInitialPlayerResponse (instant if data is in HTML) ───
        function plinkTryFastPath() {
            if (plinkDone) return true;
            try {
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                    var sd = window.ytInitialPlayerResponse.streamingData;
                    var mp4 = plinkExtractMP4(sd);
                    if (mp4 && plinkPostURL(mp4)) return true;
                    // Fallback to HLS manifest if no muxed MP4
                    if (sd.hlsManifestUrl && plinkPostURL(sd.hlsManifestUrl)) return true;
                }
            } catch(e) {}
            return false;
        }

        // ─── Intercept window.fetch ───
        var originalFetch = window.fetch;
        window.fetch = async function() {
            var response = await originalFetch.apply(this, arguments);
            if (plinkDone) return response;
            try {
                var url = '';
                if (typeof arguments[0] === 'string') url = arguments[0];
                else if (arguments[0] && arguments[0].url) url = arguments[0].url;

                if (url.indexOf('/youtubei/v1/player') !== -1) {
                    var clone = response.clone();
                    var data = await clone.json();
                    if (data && data.streamingData) {
                        var mp4 = plinkExtractMP4(data.streamingData);
                        if (mp4 && plinkPostURL(mp4)) {
                            clearInterval(plinkScraperInterval);
                        }
                    }
                }
            } catch(e) {}
            return response;
        };

        // ─── Intercept XMLHttpRequest (YouTube may use XHR instead of fetch) ───
        var origXhrOpen = XMLHttpRequest.prototype.open;
        var origXhrSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
            this._plinkUrl = url;
            return origXhrOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
            var xhr = this;
            var origOnLoad = xhr.onload;
            xhr.onload = function() {
                if (!plinkDone && xhr._plinkUrl && xhr._plinkUrl.indexOf('/youtubei/v1/player') !== -1) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data && data.streamingData) {
                            var mp4 = plinkExtractMP4(data.streamingData);
                            if (mp4 && plinkPostURL(mp4)) {
                                clearInterval(plinkScraperInterval);
                            }
                        }
                    } catch(e) {}
                }
                if (origOnLoad) origOnLoad.apply(xhr, arguments);
            };
            return origXhrSend.apply(this, arguments);
        };

        // ─── Periodic fast-path check + consent banner auto-click ───
        var plinkScraperInterval = setInterval(function() {
            // Auto-click consent banner (EU/CA users get cookie dialog)
            var consentBtn = document.querySelector('button[aria-label="Accept all"]')
                          || document.querySelector('button[aria-label="Accept the use of cookies"]')
                          || document.querySelector('button[aria-label="I agree"]')
                          || document.querySelector('.ytp-large-play-button');
            if (consentBtn) consentBtn.click();

            plinkTryFastPath();
        }, 500);
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        config.userContentController.addUserScript(interceptorScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        // 🔧 v58: Desktop Mac Safari UA — YouTube returns formats[] (muxed MP4)
        // for desktop clients, not adaptiveFormats (DASH audio/video split).
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        print("📺 HybridHookExtractor v58: loading watch page for \(videoId)")
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))

        // Internal timeout — guarantees continuation.resume
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            print("⏰ HybridHookExtractor v58: 15s timeout — finishing with error")
            self?.finish(with: .failure(YouTubeExtractorError.timedOut))
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isFinished else { return }

        // 🔧 v58: Accept googlevideo.com (muxed MP4) OR .m3u8 (HLS manifest)
        if let url = message.body as? String,
           url.contains("googlevideo.com") || url.contains(".m3u8") {
            print("🎯 HybridHookExtractor v58: INTERCEPTOR found URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 HybridHookExtractor v58: watch page loaded, waiting for /youtubei/v1/player API call...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v58: navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v58: provisional navigation failed: \(error.localizedDescription)")
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
