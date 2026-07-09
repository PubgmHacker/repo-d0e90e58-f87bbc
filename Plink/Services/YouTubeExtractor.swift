import Foundation
import WebKit

// MARK: - YouTubeExtractor (Ultra API Interceptor — direct MP4 for AVPlayer)
//
// 🔧 v59 (Gemini): Ultra API Interceptor — Fetch + XHR (addEventListener) +
// Active player request + ytcfg hook + inspect ALL responses.
//
// Why v59 replaces v58:
// v58 used `xhr.onload = ...` which gets clobbered if YouTube sets onload
// AFTER our hook, or uses addEventListener itself. v59 uses addEventListener
// which never conflicts. v59 ALSO makes an active POST request to
// /youtubei/v1/player ourselves — for videos where YouTube never calls that
// endpoint, our active request forces the response.
//
// Returns a clean .mp4 URL (itag 22 = 720p or itag 18 = 360p) that AVPlayer
// plays natively (no -11850 DASH errors).

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

        print("📺 YouTubeExtractor v59: extracting \(videoId) (Ultra API Interceptor — Fetch + XHR + Active)")

        let streamURL = try await HybridHookExtractor.extract(videoId: videoId)

        print("✅ YouTubeExtractor v59: got stream URL, prefix=\(streamURL.prefix(80))")

        let info = StreamInfo(
            id: videoId,
            title: "YouTube Video",
            author: "Unknown",
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            streamURL: streamURL,
            duration: 0,
            isLive: false,
            extractor: "ultra-api-interceptor"
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

// MARK: - Hybrid Hook Extractor (v59: Ultra API Interceptor)
//
// Hooks window.fetch + XMLHttpRequest (addEventListener) at documentStart.
// Captures ytcfg.set to grab INNERTUBE_CONTEXT + INNERTUBE_API_KEY. Then
// ACTIVELY calls /youtubei/v1/player ourselves at 1s/3s/6s/9s intervals —
// this is the killer feature that catches videos where YouTube never makes
// the player API call itself.

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

        // 🔧 v59 (Gemini): Ultra API Interceptor — Fetch + XHR (addEventListener)
        // + Active player request + ytcfg hook + inspect ALL responses.
        //
        // Why v59 replaces v58:
        // v58 used `xhr.onload = ...` which gets clobbered if YouTube sets
        // onload AFTER our hook, or if YouTube uses addEventListener instead.
        // v59 uses addEventListener('load', ...) which never conflicts.
        //
        // v59 also adds ACTIVE request to /youtubei/v1/player ourselves.
        // For some videos, YouTube's watch page NEVER calls /youtubei/v1/player
        // (uses Service Worker or embeds data differently). We capture
        // INNERTUBE_CONTEXT + INNERTUBE_API_KEY from ytcfg, then make the
        // request ourselves. This is the most reliable approach.
        let interceptorScript = WKUserScript(source: """
        // ═══════════════════════════════════════════════════════════════
        // v59 Ultra API Interceptor (Gemini spec — Fetch + XHR + Active)
        // ═══════════════════════════════════════════════════════════════

        // Spoof Page Visibility API (helps YouTube serve full player response)
        Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
        Object.defineProperty(document, 'hidden', { get: () => false });

        var plinkDone = false;
        var plinkInnertubeContext = null;
        var plinkInnertubeApiKey = null;
        var plinkVideoId = null;

        // Extract videoId from URL (?v=ID)
        try {
            var urlMatch = window.location.href.match(/[?&]v=([\\w-]{11})/);
            if (urlMatch) plinkVideoId = urlMatch[1];
        } catch(e) {}

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

        // Helper: extract best muxed MP4 URL from any data object containing streamingData
        function plinkTryExtract(data) {
            if (plinkDone || !data) return;
            try {
                var sd = data.streamingData;
                if (!sd) return;
                var formats = sd.formats || [];
                // Priority: itag 22 (720p MP4 with audio) > itag 18 (360p MP4 with audio) > first
                var best = formats.find(function(f) { return f.itag === 22; })
                           || formats.find(function(f) { return f.itag === 18; })
                           || formats[0];
                if (best && best.url) {
                    plinkPostURL(best.url);
                } else if (sd.hlsManifestUrl) {
                    plinkPostURL(sd.hlsManifestUrl);
                }
            } catch(e) {}
        }

        // ─── Hook ytcfg.set to capture INNERTUBE_CONTEXT + INNERTUBE_API_KEY ───
        // YouTube's player config is stored in ytcfg. We hook the setter to
        // capture the context + API key needed for our active request.
        if (window.ytcfg) {
            var origYtcfgSet = window.ytcfg.set;
            window.ytcfg.set = function() {
                try {
                    if (arguments.length === 2) {
                        if (arguments[0] === 'INNERTUBE_CONTEXT') plinkInnertubeContext = arguments[1];
                        if (arguments[0] === 'INNERTUBE_API_KEY') plinkInnertubeApiKey = arguments[1];
                    }
                } catch(e) {}
                return origYtcfgSet.apply(this, arguments);
            };
        }
        // Also try direct get (in case ytcfg was populated before our hook)
        try {
            if (window.ytcfg && window.ytcfg.get) {
                plinkInnertubeContext = plinkInnertubeContext || window.ytcfg.get('INNERTUBE_CONTEXT');
                plinkInnertubeApiKey = plinkInnertubeApiKey || window.ytcfg.get('INNERTUBE_API_KEY');
            }
        } catch(e) {}

        // ─── Fast Path: ytInitialPlayerResponse (instant if data is in HTML) ───
        function plinkTryFastPath() {
            if (plinkDone) return;
            try {
                if (window.ytInitialPlayerResponse) {
                    plinkTryExtract(window.ytInitialPlayerResponse);
                }
            } catch(e) {}
        }

        // ─── Intercept window.fetch (modern) ───
        var origFetch = window.fetch;
        window.fetch = async function() {
            var response = await origFetch.apply(this, arguments);
            if (plinkDone) return response;
            try {
                var url = '';
                if (typeof arguments[0] === 'string') url = arguments[0];
                else if (arguments[0] && arguments[0].url) url = arguments[0].url;

                // Broad match: any youtubei endpoint OR any URL containing 'player'
                if (url.indexOf('youtubei') !== -1 || url.indexOf('/player') !== -1) {
                    var clone = response.clone();
                    clone.json().then(function(data) {
                        plinkTryExtract(data);
                    }).catch(function() {});
                }
            } catch(e) {}
            return response;
        };

        // ─── Intercept XMLHttpRequest (classic) — uses addEventListener! ───
        // v59 fix: addEventListener is non-destructive. YouTube can set onload
        // freely without clobbering our hook.
        var origXhrOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            this._plinkUrl = url;
            return origXhrOpen.apply(this, arguments);
        };
        var origXhrSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function() {
            var xhr = this;
            xhr.addEventListener('load', function() {
                if (plinkDone) return;
                try {
                    var reqUrl = xhr._plinkUrl || '';
                    // Broad match: any youtubei endpoint OR any URL containing 'player'
                    if (reqUrl.indexOf('youtubei') !== -1 || reqUrl.indexOf('/player') !== -1) {
                        var data = JSON.parse(xhr.responseText);
                        plinkTryExtract(data);
                    }
                } catch(e) {}
            });
            return origXhrSend.apply(this, arguments);
        };

        // ─── ACTIVE request: call /youtubei/v1/player ourselves ───
        // For some videos, YouTube's watch page NEVER calls /youtubei/v1/player.
        // We capture INNERTUBE_CONTEXT + INNERTUBE_API_KEY from ytcfg, then
        // make the POST request ourselves. This is the most reliable approach.
        function plinkActivePlayerRequest() {
            if (plinkDone) return;
            if (!plinkInnertubeContext || !plinkInnertubeApiKey || !plinkVideoId) {
                // Retry ytcfg.get in case it wasn't ready at script init
                try {
                    if (window.ytcfg && window.ytcfg.get) {
                        plinkInnertubeContext = plinkInnertubeContext || window.ytcfg.get('INNERTUBE_CONTEXT');
                        plinkInnertubeApiKey = plinkInnertubeApiKey || window.ytcfg.get('INNERTUBE_API_KEY');
                    }
                } catch(e) {}
            }
            if (plinkDone || !plinkInnertubeContext || !plinkInnertubeApiKey || !plinkVideoId) return;

            try {
                var body = JSON.stringify({
                    context: plinkInnertubeContext,
                    videoId: plinkVideoId
                });
                var apiUrl = 'https://www.youtube.com/youtubei/v1/player?key=' + plinkInnertubeApiKey;
                // Use original fetch (not our hooked one) to avoid infinite loop
                origFetch.call(window, apiUrl, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: body
                }).then(function(r) { return r.json(); })
                  .then(function(data) { plinkTryExtract(data); })
                  .catch(function(e) {
                    console.log('[Plink v59] Active player request failed: ' + e);
                  });
            } catch(e) {}
        }

        // ─── Schedule active requests at multiple intervals ───
        // ytcfg may not be ready immediately, so we retry at 1s, 3s, 6s, 9s
        setTimeout(plinkActivePlayerRequest, 1000);
        setTimeout(plinkActivePlayerRequest, 3000);
        setTimeout(plinkActivePlayerRequest, 6000);
        setTimeout(plinkActivePlayerRequest, 9000);

        // ─── Periodic fast-path check + consent banner auto-click ───
        var plinkScraperInterval = setInterval(function() {
            if (plinkDone) {
                clearInterval(plinkScraperInterval);
                return;
            }
            // Auto-click consent banner (EU/CA users get cookie dialog)
            var consentBtn = document.querySelector('button[aria-label="Accept all"]')
                          || document.querySelector('button[aria-label="Accept the use of cookies"]')
                          || document.querySelector('button[aria-label="I agree"]')
                          || document.querySelector('.ytp-large-play-button');
            if (consentBtn) consentBtn.click();

            // Refresh ytcfg data (may have been set after script init)
            try {
                if (window.ytcfg && window.ytcfg.get) {
                    plinkInnertubeContext = plinkInnertubeContext || window.ytcfg.get('INNERTUBE_CONTEXT');
                    plinkInnertubeApiKey = plinkInnertubeApiKey || window.ytcfg.get('INNERTUBE_API_KEY');
                }
            } catch(e) {}

            plinkTryFastPath();
        }, 500);
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        config.userContentController.addUserScript(interceptorScript)
        config.userContentController.add(self, name: "hook")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        // 🔧 v59: Desktop Mac Safari UA — YouTube returns formats[] (muxed MP4)
        // for desktop clients, not adaptiveFormats (DASH audio/video split).
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        print("📺 HybridHookExtractor v59: loading watch page for \(videoId)")
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))

        // Internal timeout — guarantees continuation.resume
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            print("⏰ HybridHookExtractor v59: 15s timeout — finishing with error")
            self?.finish(with: .failure(YouTubeExtractorError.timedOut))
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isFinished else { return }

        // 🔧 v59: Accept googlevideo.com (muxed MP4) OR .m3u8 (HLS manifest)
        if let url = message.body as? String,
           url.contains("googlevideo.com") || url.contains(".m3u8") {
            print("🎯 HybridHookExtractor v59: INTERCEPTOR found URL: \(url.prefix(80))")
            finish(with: .success(url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("📺 HybridHookExtractor v59: watch page loaded, waiting for /youtubei/v1/player API call...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v59: navigation failed: \(error.localizedDescription)")
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isFinished else { return }
        print("❌ HybridHookExtractor v59: provisional navigation failed: \(error.localizedDescription)")
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
