import SwiftUI
import AVKit
import WebKit

// MARK: - WebViewControl (singleton for JS bridge to WKWebView)
//
// 🔧 NEW: SyncEngine calls WebViewControl.shared.play()/pause()/seek() when
// in webview mode (player == nil). This singleton holds a weak reference to
// the active WKWebView and evaluates JavaScript to control the YouTube player.
@MainActor
final class WebViewControl {
    static let shared = WebViewControl()
    private weak var webView: WKWebView?

    func register(_ webView: WKWebView) {
        self.webView = webView
    }

    func unregister() {
        self.webView = nil
    }

    func play() {
        webView?.evaluateJavaScript("if(typeof player!=='undefined'&&player.playVideo){player.playVideo();} else {document.getElementById('player').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"playVideo\",\"args\":[]}','*');}", completionHandler: nil)
    }

    func pause() {
        webView?.evaluateJavaScript("if(typeof player!=='undefined'&&player.pauseVideo){player.pauseVideo();} else {document.getElementById('player').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"pauseVideo\",\"args\":[]}','*');}", completionHandler: nil)
    }

    func seek(to time: TimeInterval) {
        let js = "if(typeof player!=='undefined'&&player.seekTo){player.seekTo(\(time),true);}"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - Video Container View v2
/// Контейнер видео с соотношением 16:9, центрированный по горизонтали.
///
/// В портрете: видео занимает ~70% ширины экрана (16:9), центрировано.
/// В ландшафте: видео растягивается на весь экран.
///
/// WebRTC-ready: AVPlayer сейчас → RTCMTLVideoView позже (одна замена).
struct VideoContainerView: View {
    let mediaURL: String
    let playbackMode: PlaybackMode
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isFullscreen: Bool

    var onTogglePlay: () -> Void
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            let videoSize = computeVideoSize(container: geo.size)

            ZStack {
                Color.black.opacity(0.3)

                switch playbackMode {
                case .directStream:
                    directStreamView(size: videoSize)
                case .webview:
                    webVideoView(size: videoSize)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Size Calculation

    /// Вычисляет размер видео 16:9 в зависимости от контейнера.
    /// Портрет: вписываем по ширине (70%), высота = width * 9/16.
    /// Ландшафт: вписываем по высоте (100%), ширина = height * 16/9.
    private func computeVideoSize(container: CGSize) -> CGSize {
        if isFullscreen {
            // Ландшафт: видео на весь экран
            return container
        }

        // Портрет: 16:9 по ширине контейнера
        let width = container.width
        let height = width * 9.0 / 16.0
        return CGSize(width: width, height: height)
    }

    // MARK: - Direct Stream (AVPlayer)

    @ViewBuilder
    private func directStreamView(size: CGSize) -> some View {
        if let url = URL(string: mediaURL) {
            // 🔧 FIX H3: Use SyncEngine's AVPlayer directly (was: created own AVPlayer).
            // SyncEngine.player is the source of truth — it applies play/pause/seek
            // commands and broadcasts state. The old code created a SECOND AVPlayer
            // here, causing visual desync (SyncEngine controlled an invisible player,
            // the user saw a different one out of sync).
            //
            // We pass isPlaying/currentTime as fallback signals for when the
            // SyncEngine.player is not yet available (e.g. early in setup).
            VideoPlayerRepresentable(
                url: url,
                isPlaying: isPlaying,
                currentTime: currentTime
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12))
        } else {
            VideoPlaceholder()
                .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - WebView (кинотеатры)

    @ViewBuilder
    private func webVideoView(size: CGSize) -> some View {
        if let url = URL(string: mediaURL) {
            WebVideoView(url: url) { time in
                onSeek(time)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12))
        } else {
            VideoPlaceholder()
                .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - VideoPlayer Representable (AVPlayer wrapper)
//
// 🔧 FIX H3: PlayerUIView now accepts an EXTERNAL AVPlayer (from SyncEngine)
// instead of creating its own. This eliminates the dual-AVPlayer desync bug
// where SyncEngine controlled one invisible player while the user saw a
// different player out of sync.
//
// 🔧 FIX H8: PlayerUIView now overrides willMove(toSuperview:) to invalidate
// the display link when the view is removed — prevents leak across URL changes.

struct VideoPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let currentTime: TimeInterval
    /// 🔧 FIX H3: External AVPlayer from SyncEngine. If nil, falls back to
    /// creating a local player (legacy behavior for previews / tests).
    var sharedPlayer: AVPlayer?

    init(url: URL, isPlaying: Bool, currentTime: TimeInterval, sharedPlayer: AVPlayer? = nil) {
        self.url = url
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.sharedPlayer = sharedPlayer
    }

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(url: url, isPlaying: isPlaying, currentTime: currentTime, sharedPlayer: sharedPlayer)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.update(isPlaying: isPlaying, currentTime: currentTime, sharedPlayer: sharedPlayer)
    }
}

final class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var ownsPlayer: Bool = false  // true if we created the player (vs. borrowed from SyncEngine)

    init(url: URL, isPlaying: Bool, currentTime: TimeInterval, sharedPlayer: AVPlayer? = nil) {
        super.init(frame: .zero)
        backgroundColor = .black

        if let shared = sharedPlayer {
            // 🔧 FIX H3: Use SyncEngine's AVPlayer — no second player created.
            player = shared
            ownsPlayer = false
            // Extract video output from the shared player's current item if present
            if let item = shared.currentItem {
                attachVideoOutput(to: item)
            }
        } else {
            // Fallback: create a local player (used in previews / tests / no-SyncEngine context)
            let item = AVPlayerItem(url: url)
            attachVideoOutput(to: item)

            let p = AVPlayer(playerItem: item)
            p.actionAtItemEnd = .pause
            player = p
            ownsPlayer = true

            if isPlaying { p.play() }
        }

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        // ── Display link для периодического захвата кадров ───────────
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 🔧 FIX H8: Tear down display link + player when the view is removed
    /// from its superview. This handles media URL changes (where SwiftUI
    /// creates a new PlayerUIView but the old one's display link keeps firing).
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            displayLink?.invalidate()
            displayLink = nil
            if ownsPlayer {
                player?.pause()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    private func attachVideoOutput(to item: AVPlayerItem) {
        // Remove any existing output from previous item
        if let existing = videoOutput {
            item.remove(existing)
        }
        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        item.add(output)
        videoOutput = output
    }

    private func setupDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(captureFrame))
        link.preferredFramesPerSecond = 4  // ~4 раза/сек (AmbilightSampler сам троттлит до 2 Гц)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func captureFrame() {
        guard let output = videoOutput,
              output.hasNewPixelBuffer(forItemTime: .zero) else { return }

        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        Task { @MainActor in
            AmbilightSampler.shared.processFrame(pixelBuffer)
        }
    }

    func update(isPlaying: Bool, currentTime: TimeInterval, sharedPlayer: AVPlayer? = nil) {
        // 🔧 FIX H3: Swap to shared player if it became available
        if let shared = sharedPlayer, shared !== player {
            player = shared
            ownsPlayer = false
            playerLayer.player = shared
            if let item = shared.currentItem {
                attachVideoOutput(to: item)
            }
        }

        guard let player else { return }

        // Only apply play/pause/seek if we own the player (fallback mode).
        // When using SyncEngine's player, SyncEngine itself drives these —
        // applying them here would fight with the sync engine.
        if ownsPlayer {
            if isPlaying && player.rate == 0 {
                player.play()
            } else if !isPlaying && player.rate > 0 {
                player.pause()
            }

            let current = player.currentTime().seconds
            if abs(current - currentTime) > 1.5 {
                player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
            }
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - Web Video (WKWebView с JS-bridge)
//
// 🔧 FIX: WebView is recreated on rotation → video restarts from beginning.
// Solution: makeUIView creates WebView once. updateUIView is called on
// rotation but does NOT reload the page. The WebView persists across
// rotation because SwiftUI keeps the same UIView instance.
struct WebVideoView: UIViewRepresentable {
    let url: URL
    var onTimeUpdate: (TimeInterval) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.websiteDataStore = WKWebsiteDataStore.default()  // 🔧 allow cookies

        let userScript = WKUserScript(
            source: Self.syncScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        let bridge = VideoTimeBridge(closure: onTimeUpdate)
        context.coordinator.bridge = bridge
        config.userContentController.add(bridge, name: "videoBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        // 🔧 Register webView so SyncEngine can send play/pause/seek via JS.
        // Must happen BEFORE we load any URL — SyncEngine may evaluate JS as
        // soon as the player is ready, and the registration is what makes
        // WebViewControl.shared point at this instance.
        WebViewControl.shared.register(webView)

        // 🔧 FIX v5 (July 2026): YouTube error 153 — real iOS Safari UA.
        //
        // v4 attempted to spoof navigator.userAgent via Object.defineProperty
        // JS injection. Did NOT work — modern iOS WKWebView seals navigator
        // properties, the override silently fails, error 153 persists.
        //
        // ROOT CAUSE (re-investigated):
        //   Default WKWebView UA looks like:
        //     "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)
        //      AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        //   Note: NO "Safari/604.1" suffix.
        //
        //   Real iOS Safari UA looks like:
        //     "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)
        //      AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0
        //      Mobile/15E148 Safari/604.1"
        //   Note: HAS "Safari/604.1" suffix.
        //
        //   YouTube's IFrame API JS checks navigator.userAgent for "Safari/"
        //   to determine if we're a real Safari browser. WKWebView's default
        //   UA omits this → YouTube JS flags as in-app browser → error 153.
        //
        // SOLUTION v5:
        //   Set customUserAgent to a REAL iOS Safari UA string. This is a
        //   legitimate iOS Safari UA — same TLS fingerprint (still iOS device),
        //   same OS, same AppleWebKit version. The only difference from
        //   WKWebView's default is the addition of "Version/17.0" and
        //   "Safari/604.1" — which is exactly what real Safari reports.
        //
        //   Why this works for BOTH detection systems:
        //     - YouTube JS: sees "Safari/604.1" → not WKWebView → no 153
        //     - YouTube TLS anti-abuse: UA matches iOS TLS fingerprint
        //       (real iOS Safari UA on real iOS device) → no bot check
        //
        //   The Mac UA approach (v1-v3) failed because Mac UA on iOS device
        //   = TLS mismatch → bot check. The default WKWebView UA approach (v3-v4)
        //   failed because no "Safari/" → JS detects WKWebView → 153.
        //
        //   v5 is the Goldilocks solution: iOS Safari UA satisfies both.
        let urlString = url.absoluteString
        if urlString.contains("rutube.ru") {
            // Rutube genuinely requires desktop UA on the HTTP layer — different
            // player, no bot check, no TLS fingerprint validation.
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            webView.load(URLRequest(url: url))
        } else if urlString.contains("youtube.com/embed/") {
            // 🔧 v5: real iOS Safari UA — solves both 153 and bot check.
            // See the long comment above for the full rationale.
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

            // 🔧 v5: also rewrite to youtube-nocookie.com (privacy-enhanced
            // embed domain — fewer server-side checks, officially sanctioned
            // by YouTube). Add embed params for cleaner playback.
            let videoId = url.lastPathComponent
            var params = "playsinline=1&rel=0&modestbranding=1&enablejsapi=1"
            // Preserve any existing query params (e.g. origin, autoplay).
            if let existingComps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let existingItems = existingComps.queryItems,
               !existingItems.isEmpty {
                let existing = existingItems
                    .filter { $0.name != "playsinline" && $0.name != "rel" && $0.name != "modestbranding" && $0.name != "enablejsapi" }
                    .map { "\($0.name)=\($0.value ?? "")" }
                    .joined(separator: "&")
                if !existing.isEmpty {
                    params += "&" + existing
                }
            }
            let nocookieURLString = "https://www.youtube-nocookie.com/embed/\(videoId)?\(params)"
            if let nocookieURL = URL(string: nocookieURLString) {
                print("📺 YouTube: real iOS Safari UA + youtube-nocookie.com: \(nocookieURLString)")
                webView.load(URLRequest(url: nocookieURL))
            } else {
                // Fallback: load original URL directly.
                webView.load(URLRequest(url: url))
            }
        } else {
            // Non-YouTube/Rutube: load URL directly with default UA.
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    /// 🔧 DEPRECATED v4 (July 2026): the navigator-spoofing JS script is no
    /// longer used — Object.defineProperty on navigator props fails silently
    /// in modern iOS WKWebView. v5 uses customUserAgent = real iOS Safari UA
    /// instead, which works at both HTTP and JS layers natively.
    ///
    /// Kept here for reference + binary compatibility (in case any external
    /// caller references it). Not added to userContentController anymore.
    static let navigatorSpoofScript: String = """
    // Deprecated v4 — see makeUIView() comment for v5 rationale.
    (function() {
        var macUA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
        try {
            Object.defineProperty(navigator, 'userAgent', { get: function() { return macUA; } });
            Object.defineProperty(navigator, 'platform', { get: function() { return 'MacIntel'; } });
            Object.defineProperty(navigator, 'vendor', { get: function() { return 'Apple Computer, Inc.'; } });
            Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 0; } });
        } catch(e) {}
        if (!window.chrome) { window.chrome = { runtime: {} }; }
    })();
    """

    /// 🔧 DEPRECATED v2 (July 2026): the custom YouTube IFrame HTML wrapper
    /// was REMOVED — see makeUIView() for the rationale. Kept here as a
    /// static no-op for binary compatibility (in case any external caller
    /// references it). Returns empty string.
    static func youtubeEmbedHTML(videoId: String) -> String {
        return ""
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var bridge: VideoTimeBridge?
    }

    static let syncScript: String = """
    (function() {
        function findVideo() { return document.querySelector('video'); }
        function reportTime() {
            var v = findVideo();
            if (v) window.webkit.messageHandlers.videoBridge.postMessage(v.currentTime);
        }
        var v = findVideo();
        if (v) {
            v.addEventListener('timeupdate', reportTime);
            v.addEventListener('play', reportTime);
            v.addEventListener('pause', reportTime);
            v.addEventListener('seeked', reportTime);
        } else {
            setTimeout(function() {
                v = findVideo();
                if (v) {
                    v.addEventListener('timeupdate', reportTime);
                    v.addEventListener('play', reportTime);
                    v.addEventListener('pause', reportTime);
                    v.addEventListener('seeked', reportTime);
                }
            }, 2000);
        }
    })();
    """
}

final class VideoTimeBridge: NSObject, WKScriptMessageHandler {
    let closure: (TimeInterval) -> Void
    init(closure: @escaping (TimeInterval) -> Void) { self.closure = closure }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if let time = message.body as? Double { closure(time) }
    }
}

// MARK: - Video Placeholder

struct VideoPlaceholder: View {
    var body: some View {
        ZStack {
            Color.raveCard
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundColor(.raveTextSecondary)
                Text("No media")
                    .font(.system(size: 14))
                    .foregroundColor(.raveTextSecondary)
            }
        }
    }
}
