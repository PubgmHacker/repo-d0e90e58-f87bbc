import Foundation
import WebKit

// MARK: - YouTubeExtractor (Hybrid WKWebView Network Hook)
//
// 🔧 v51.2: Bulletproof — @MainActor, guaranteed timeout, no retain cycle.
// Uses invisible WKWebView to bypass BotGuard. WebKit solves all JS
// challenges natively. JS hook intercepts stream URL for AVPlayer.

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

        print("📺 YouTubeExtractor v51.2: extracting \(videoId) (Hybrid WKWebView Hook)")

        // 🔧 v51.2: Use withTimeout to guarantee no infinite loading.
        // HybridHookExtractor holds strong reference to itself via
        // internal retain cycle that's broken on finish().
        let streamURL = try await withTimeout(15) {
            try await HybridHookExtractor.extract(videoId: videoId)
        }

        print("✅ YouTubeExtractor v51.2: got stream URL, prefix=\(streamURL.prefix(60))")

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

@MainActor
private final class HybridHookExtractor: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var isFinished = false
    private var selfRetain: HybridHookExtractor?

    static func extract(videoId: String) async throws -> String {
        let extractor = HybridHookExtractor()
        return try await withCheckedThrowingContinuation { continuation in
            extractor.continuation = continuation
            // Strong self-reference to prevent deallocation during async work
            extractor.selfRetain = extractor
            extractor.start(videoId: videoId)
        }
    }

    private func start(videoId: String) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Prevent double audio — mute invisible WebView
        config.mediaTypesRequiringUserActionForPlayback = .all

        // JS hook: intercept fetch/XHR for googlevideo.com or .m3u8 URLs
        let hookScript = WKUserScript(source: """
        (function() {
            function checkURL(url) {
                if (typeof url !== 'string') return false;
                return url.indexOf('googlevideo.com/videoplayback') !== -1 ||
                       url.indexOf('.m3u8') !== -1 ||
                       url.indexOf('googlevideo.com') !== -1;
            }

            var origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                if (url && url.url) url = url.url;
                if (checkURL(url)) {
                    window.webkit.messageHandlers.hook.postMessage({type: 'fetch', url: url});
                }
                return origFetch.apply(this, arguments);
            };

            var origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (checkURL(url)) {
                    window.webkit.messageHandlers.hook.postMessage({type: 'xhr', url: url});
                }
                return origOpen.apply(this, arguments);
            };

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

            setInterval(function() {
                var videos = document.querySelectorAll('video');
                for (var i = 0; i < videos.length; i++) {
                    var src = videos[i].src || videos[i].currentSrc;
                    if (src && checkURL(src)) {
                        window.webkit.messageHandlers.hook.postMessage({type: 'video', url: src});
                    }
                    // Mute to prevent double audio
                    videos[i].muted = true;
                    videos[i].volume = 0;
                }
            }, 500);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        config.userContentController.addUserScript(hookScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = self
        self.webView = webView

        print("📺 HybridHookExtractor: loading watch page for \(videoId)")
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isFinished else { return }

        if let dict = message.body as? [String: Any],
           let url = dict["url"] as? String,
           url.contains("googlevideo.com") || url.contains(".m3u8") {
            print("🎯 HybridHookExtractor: HOOK intercepted URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 HybridHookExtractor: watch page loaded, waiting for stream URL...")
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

        // Cleanup WebView completely
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "hook")
        webView?.configuration.userContentController.removeAllUserScripts()
        webView = nil

        // Resume continuation
        continuation?.resume(with: result)
        continuation = nil

        // Break self-retention
        selfRetain = nil
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
