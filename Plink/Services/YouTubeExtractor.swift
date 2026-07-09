import Foundation
import WebKit

// MARK: - HybridYouTubeExtractor (WKWebView Network Hook)
//
// 🔧 v51: Final solution — uses WKWebView to bypass BotGuard.
// YouTube's BotGuard (2026) blocks all API-only approaches:
//   - WEB: UNPLAYABLE (needs po_token)
//   - IOS: FAILED_PRECONDITION
//   - TVHTML5: LOGIN_REQUIRED
//
// Hybrid approach: invisible WKWebView loads the watch page.
// WebKit solves BotGuard natively (it IS Safari). JS hook intercepts
// the stream URL (googlevideo.com or .m3u8) and sends it to Swift.
// Swift kills the WebView and feeds the URL to AVPlayer.

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

        print("📺 YouTubeExtractor v51: extracting \(videoId) (Hybrid WKWebView Hook)")

        let streamURL = try await withTimeout(15) {
            try await self.extractStreamURL(videoId: videoId)
        }

        print("✅ YouTubeExtractor v51: got stream URL, prefix=\(streamURL.prefix(60))")

        let info = StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: streamURL,
            duration: 0,
            isLive: false,
            extractor: "hybrid-webview"
        )

        cache[videoId] = (info, Date().addingTimeInterval(cacheTTL))
        return info
    }

    private func extractStreamURL(videoId: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            HybridHookExtractor.extract(videoId: videoId) { result in
                continuation.resume(with: result)
            }
        }
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

// MARK: - Hybrid Hook Extractor (WKWebView + JS Network Intercept)

private final class HybridHookExtractor: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    private weak var webView: WKWebView?
    private var continuation: (Result<String, Error>)?
    private var finished = false

    static func extract(videoId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let extractor = HybridHookExtractor()
        extractor.continuation = completion
        extractor.start(videoId: videoId)
    }

    private func start(videoId: String) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // JS hook: intercept fetch/XHR for googlevideo.com or .m3u8 URLs
        let hookScript = WKUserScript(source: """
        (function() {
            function checkURL(url) {
                if (typeof url !== 'string') return false;
                return url.indexOf('googlevideo.com/videoplayback') !== -1 ||
                       url.indexOf('.m3u8') !== -1 ||
                       url.indexOf('googlevideo.com') !== -1;
            }

            // Hook fetch
            var origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                if (url && url.url) url = url.url;
                if (checkURL(url)) {
                    window.webkit.messageHandlers.hook.postMessage({type: 'fetch', url: url});
                }
                return origFetch.apply(this, arguments);
            };

            // Hook XMLHttpRequest
            var origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (checkURL(url)) {
                    window.webkit.messageHandlers.hook.postMessage({type: 'xhr', url: url});
                }
                return origOpen.apply(this, arguments);
            };

            // Hook video src
            var origCreateElement = document.createElement;
            document.createElement = function(tag) {
                var el = origCreateElement.apply(this, arguments);
                if (tag.toLowerCase() === 'video') {
                    var observer = new MutationObserver(function(mutations) {
                        if (el.src && checkURL(el.src)) {
                            window.webkit.messageHandlers.hook.postMessage({type: 'video', url: el.src});
                        }
                    });
                    observer.observe(el, {attributes: true, attributeFilter: ['src']});
                }
                return el;
            };

            // Also check existing video elements
            setInterval(function() {
                var videos = document.querySelectorAll('video');
                for (var i = 0; i < videos.length; i++) {
                    var src = videos[i].src || videos[i].currentSrc;
                    if (src && checkURL(src)) {
                        window.webkit.messageHandlers.hook.postMessage({type: 'video', url: src});
                    }
                }
            }, 500);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        config.userContentController.addUserScript(hookScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: .zero, configuration: config)
        // iPad UA → YouTube returns HLS (.m3u8) instead of MSE (blob)
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = self
        self.webView = webView

        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !finished else { return }

        if let dict = message.body as? [String: Any],
           let url = dict["url"] as? String,
           url.contains("googlevideo.com") || url.contains(".m3u8") {
            print("🎯 YouTubeExtractor v51: HOOK intercepted URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 YouTubeExtractor v51: watch page loaded, waiting for stream URL...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !finished else { return }
        print("❌ YouTubeExtractor v51: navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    // MARK: - Cleanup

    private func finish(with result: Result<String, Error>) {
        guard !finished else { return }
        finished = true

        // Cleanup WebView
        DispatchQueue.main.async { [weak self] in
            self?.webView?.stopLoading()
            self?.webView?.navigationDelegate = nil
            self?.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "hook")
            self?.webView = nil
        }

        continuation?(result)
    }

    deinit {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
    }
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
        case .noStreamFound: return "Не удалось перехватить URL видеопотока"
        case .invalidResponse: return "Неверный ответ от YouTube"
        }
    }
}

// MARK: - Timeout helper

func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw YouTubeExtractorError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
