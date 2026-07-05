import WebKit

// MARK: - PlinkPlayerManager (v20)
//
// Singleton WKWebView manager — the WebView is created ONCE and reused
// across all SwiftUI state changes. This prevents:
//   - Reload loops (SwiftUI calls makeUIView/updateUIView repeatedly)
//   - Sandbox crashes (OS kills WebContent process from too many reloads)
//   - DownloadFailed errors (OS blocks memory allocation)
//   - WebSocket disconnections (network process crashes from WebView spam)
//   - YouTube bot detection (broken TCP packets look like DDoS)
//
// The WebView accumulates cookies and session state over time → YouTube
// sees a legitimate long-running session, not a bot.

final class PlinkPlayerManager: NSObject {
    static let shared = PlinkPlayerManager()

    let webView: WKWebView
    private var currentVideoId: String? = nil

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        // Persistent cookies — YouTube needs CONSENT cookie to skip bot check
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        // Mobile Safari UA — YouTube is more lenient with mobile (no session = normal)
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1.15"

        self.webView.scrollView.isScrollEnabled = false
        self.webView.scrollView.bounces = false
        self.webView.isOpaque = false
        self.webView.backgroundColor = .black

        super.init()
    }

    /// Load a YouTube video by ID. Guards against duplicate loads.
    func loadYouTubeVideo(id: String) {
        // Hard guard: if this video is already loaded, ignore — protects network stack
        guard id != currentVideoId && !id.isEmpty else { return }
        self.currentVideoId = id

        // Backend player URL — real HTTPS origin, no local HTML, no sandbox issues
        let playerURLString = "https://plink-backend-production-ef31.up.railway.app/api/media/youtube-player?id=\(id)"
        guard let url = URL(string: playerURLString) else { return }

        print("📺 YouTube v20: PlinkPlayerManager loading video \(id) (single load, no reload loops)")
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15.0)

        DispatchQueue.main.async {
            self.webView.load(request)
        }
    }

    /// Reset when leaving a room — allows next room to load a new video
    func reset() {
        currentVideoId = nil
    }
}
