import Foundation
import WebKit

// MARK: - ExtractionBridge (v101 — Async IOS Innertube Fetch in WebView)
//
// 🔧 v90 (Gemini): Separate invisible WKWebView that ONLY extracts stream URL.
// 🔧 v98: Switched priority to HLS-first. MP4 formats (itag 18/22) are
//         IP-bound — their sparams include `ip`, so backend's v97 transparent
//         proxy can't strip `ip` without invalidating the signature → 403.
// 🔧 v99: Tried IOS innertube API via sync XHR — BLOCKED in WKWebView,
//         silently fell through to MP4 fallback → same 403.
// 🔧 v100: Tried backend-side IOS innertube extraction — Railway IP fully
//         blocked by YouTube ("Precondition check failed" +
//         "Sign in to confirm you're not a bot"). Cookies don't help.
// 🔧 v101: Async fetch in WebView to call /youtubei/v1/player with IOS client.
//         Runs on iPhone IP (not blocked). YouTube returns hlsManifestUrl.
//         Backend pipes manifest bytes only; AVPlayer fetches segments
//         DIRECTLY from iPhone IP → IP matches → 200 OK.
//
// Strategy:
//   1. Load m.youtube.com/watch?v=ID with iOS Safari UA
//   2. Poll for ytInitialPlayerResponse (HTML/window/ytplayer.config)
//   3. Priority A: hlsManifestUrl from MWEB (sometimes present)
//   4. Priority B: async fetch /youtubei/v1/player {clientName:'IOS'} → HLS
//   5. Priority C: MP4 itag 22/18 (LAST resort, IP-bound, will 403)
//   6. Return StreamInfo to caller (NativePlayerEngine)
//   7. Release WKWebView
//
// Why this avoids ban:
//   - IP = iPhone (residential, not blocked)
//   - UA = iOS Safari (YouTube trusts mobile browsers)
//   - IOS innertube API request runs in-page (same origin) — no CORS, no BotGuard
//   - Cookies + INNERTUBE_API_KEY already in WebView session
//   - Async fetch works reliably in WKWebView (sync XHR does NOT)

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
        didReloadAfterTerminate = false  // v94.8: reset reload flag
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

            // 🔧 v94.10: Create WKWebView on main thread + add to view hierarchy.
            // "Could not create a sandbox extension" error happens when WKWebView
            // is created off-main-thread or not attached to any UIView hierarchy.
            // iOS kills WKWebView that aren't in the view tree.
            let wv = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                configuration: config
            )
            // iOS Safari UA — YouTube trusts this and serves full HTML
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) " +
                                 "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 " +
                                 "Mobile/15E148 Safari/604.1"
            wv.navigationDelegate = self
            wv.isHidden = false  // must be visible (even if 1x1 pixel)
            wv.alpha = 0.01      // nearly invisible but still in hierarchy
            self.webView = wv

            // 🔧 v94.10: Add to a hidden window's view hierarchy.
            // iOS requires WKWebView to be in a UIView tree to avoid sandbox errors.
            // We add it to the key window's root VC view, 1x1 pixel, alpha 0.01.
            if let keyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .windows.first(where: { $0.isKeyWindow }) {
                keyWindow.addSubview(wv)
                print("🔍 v94.10: ExtractionBridge — WKWebView added to key window hierarchy")
            } else {
                // Fallback: create a temporary window
                let tempWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
                tempWindow.windowLevel = .init(rawValue: -1)  // below everything
                tempWindow.isHidden = false
                tempWindow.rootViewController = UIViewController()
                tempWindow.rootViewController?.view.addSubview(wv)
                print("🔍 v94.10: ExtractionBridge — WKWebView added to temp window")
            }

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
            // Accept googlevideo.com (MP4 or HLS manifest) or .m3u8 (HLS)
            if url.contains("googlevideo.com") || url.contains(".m3u8") {
                let source: String
                if url.contains("/manifest/hls/") || url.contains(".m3u8") {
                    source = "HLS manifest"
                } else {
                    source = "MP4 (IP-bound, may 403 through proxy)"
                }
                print("✅ v101: ExtractionBridge — found \(source): \(url.prefix(80))")

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

    // 🔧 v94.8: Handle WebContent process termination (iOS kills background WKWebView).
    // Instead of giving up, reload the page ONCE and let the scraper continue.
    private var didReloadAfterTerminate = false

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !isFinished else { return }

        if !didReloadAfterTerminate {
            didReloadAfterTerminate = true
            print("🔄 v94.8: ExtractionBridge — WebContent process terminated, reloading ONCE...")
            // Reload the page — scraper script will re-inject at documentEnd
            if let url = webView.url {
                webView.load(URLRequest(url: url))
            }
        } else {
            print("❌ v94.8: ExtractionBridge — WebContent terminated again, giving up")
            finish(with: .failure(ExtractionError.invalidResponse))
        }
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
        webView?.removeFromSuperview()  // 🔧 v94.10: remove from view hierarchy
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
                var videoId = null;

                // Method 1: Direct access to global variable
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                    sd = window.ytInitialPlayerResponse.streamingData;
                    videoId = window.ytInitialPlayerResponse.videoDetails?.videoId;
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
                                    videoId = data.videoDetails?.videoId;
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
                        if (parsed.streamingData) {
                            sd = parsed.streamingData;
                            videoId = parsed.videoDetails?.videoId;
                        }
                    }
                }

                // Fallback: extract videoId from URL
                if (!videoId) {
                    var urlMatch = location.href.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
                    if (urlMatch) videoId = urlMatch[1];
                }

                if (sd) {
                    var targetUrl = null;

                    // v101 Priority A — HLS from MWEB (sometimes present for live/recent).
                    if (sd.hlsManifestUrl) {
                        targetUrl = sd.hlsManifestUrl;
                    }

                    // v101 Priority B — IOS innertube API via ASYNC fetch.
                    // v99 used sync XHR which gets blocked/silently fails in WKWebView.
                    // v101 uses async fetch — works reliably in WKWebView.
                    //
                    // MWEB client typically does NOT include hlsManifestUrl in
                    // streamingData. The IOS client DOES. We POST to /youtubei/v1/player
                    // with clientName=IOS — YouTube responds with hlsManifestUrl.
                    // Cookies + API key are already in the WebView session (same-origin).
                    //
                    // IMPORTANT: this runs on iPhone IP, so hlsManifestUrl is bound to
                    // iPhone IP. Backend pipes the manifest bytes only; AVPlayer then
                    // fetches segments DIRECTLY from iPhone IP → IP matches → 200 OK.
                    // (Railway IP is fully blocked by YouTube — v100 proved this with
                    //  "Precondition check failed" + "Sign in to confirm you're not a bot")
                    if (!targetUrl && videoId && !window.__plinkIosFetchStarted) {
                        window.__plinkIosFetchStarted = true; // one-shot guard

                        var apiKey = window.ytcfg?.get?.('INNERTUBE_API_KEY') || 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
                        var clientVersion = window.ytcfg?.get?.('INNERTUBE_CONTEXT_CLIENT_VERSION') || '17.31.4';

                        fetch('https://www.youtube.com/youtubei/v1/player?key=' + apiKey + '&prettyPrint=false', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                context: {
                                    client: {
                                        clientName: 'IOS',
                                        clientVersion: clientVersion,
                                        hl: 'en',
                                        gl: 'US'
                                    }
                                },
                                videoId: videoId
                            })
                        })
                        .then(function(r) { return r.json(); })
                        .then(function(data) {
                            if (data && data.streamingData && data.streamingData.hlsManifestUrl) {
                                clearInterval(interval);
                                window.webkit.messageHandlers.extractor.postMessage(data.streamingData.hlsManifestUrl);
                            }
                            // If no hlsManifestUrl, fall through to MP4 on next interval tick.
                            // Reset guard so we don't retry innertube forever.
                            window.__plinkIosFetchStarted = false;
                        })
                        .catch(function(e) {
                            // Reset guard on failure so we can retry on next poll cycle.
                            window.__plinkIosFetchStarted = false;
                        });
                    }

                    // v101 Priority C — muxed MP4 (LAST resort, IP-bound, will 403 through proxy).
                    // Only used as fallback if IOS innertube fetch fails AND no HLS available.
                    // We give innertube fetch 3 attempts (1.5s) to complete before falling back.
                    if (!targetUrl && attempts > 6 && !window.__plinkIosFetchStarted) {
                        var formats = sd.formats || [];
                        var best = formats.find(function(f) { return f.itag === 22; })
                                   || formats.find(function(f) { return f.itag === 18; })
                                   || formats[0];
                        if (best && best.url) {
                            targetUrl = best.url;
                        }
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
