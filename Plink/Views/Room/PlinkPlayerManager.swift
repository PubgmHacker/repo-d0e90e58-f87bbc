import WebKit

// MARK: - PlinkPlayerManager (v21)
//
// Singleton WKWebView manager — the WebView is created ONCE and reused.
// v21: added removeFromSuperview() in makeUIView + process suppression disable.

final class PlinkPlayerManager: NSObject {
    static let shared = PlinkPlayerManager()

    let webView: WKWebView
    private var currentVideoId: String? = nil

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // 🔧 v21: disable process suppression — prevents iOS from sleeping
        // the WebContent/GPU processes when WebView is not visible.
        // This fixes 'gpuProcessExited: reason=IdleExit' → black screen.
        configuration.preferences.setValue(false, forKey: "pageVisibilityBasedProcessSuppressionEnabled")

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1.15"
        self.webView.scrollView.isScrollEnabled = false
        self.webView.scrollView.bounces = false
        self.webView.isOpaque = false
        self.webView.backgroundColor = .black

        super.init()
    }

    func loadYouTubeVideo(id: String) {
        guard id != currentVideoId && !id.isEmpty else { return }
        self.currentVideoId = id

        let playerURLString = "https://plink-backend-production-ef31.up.railway.app/api/media/youtube-player?id=\(id)"
        guard let url = URL(string: playerURLString) else { return }

        print("📺 YouTube v21: loading video \(id)")
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15.0)
        DispatchQueue.main.async {
            self.webView.load(request)
        }
    }

    func reset() {
        currentVideoId = nil
    }
}
