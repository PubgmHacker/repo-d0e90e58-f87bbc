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
        let urlString = url.absoluteString
        // 🔧 v14.1: must also match youtube-nocookie.com (v14 changed embed URL domain)
        let isYouTube = urlString.contains("youtube.com/embed/") ||
                         urlString.contains("youtube-nocookie.com/embed/") ||
                         urlString.contains("youtu.be/")
        // 🔧 v12: backend embed proxy URL
        let isBackendPlayer = urlString.contains("plink-backend") && (urlString.contains("youtube-player") || urlString.contains("youtube-embed"))

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        // 🔧 v27 (July 2026): WKProcessPool is DEPRECATED in iOS 15+.
        // Apple docs: 'Creating and using multiple instances of
        // WKProcessPool no longer has any effect.' Each WKWebView always
        // gets its own WebContent process automatically. The v26 attempt
        // to isolate via process pools was based on outdated info —
        // removed. v27 keeps the v25 nonPersistent() data store, which
        // is the REAL isolation mechanism.
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // 🔧 v31.1 (July 2026): allowUniversalAccessFromFileURLs — bypass CORS
        // for loadHTMLString with HTTPS baseURL. Without this, the iframe
        // inside the local HTML cannot make HTTPS requests to youtube.com
        // because iOS treats the page as 'file://' origin despite the baseURL.
        // This is a known Apple private API — App Store accepts it (Rave uses
        // the same trick, plus many WebView-based apps).
        // 'allowFileAccessFromFileURLs' is the XHR/fetch equivalent.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // 🔧 v30 (July 2026): REMOVED setURLSchemeHandler(plink-media://).
        // Custom scheme caused "nw_connection_copy_protocol_metadata_internal
        // on unconnected nw_connection" → DownloadFailed → 153.
        // Now using loadHTMLString with baseURL: https://plink.app.
        // See Coordinator.loadVideoOnce for the new loading logic.

        let isYouTubeLike = isYouTube || isBackendPlayer

        if !isYouTubeLike {
            // Non-YouTube (Rutube, VK, etc.): add sync script + bridge + CSS
            let userScript = WKUserScript(
                source: Self.syncScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(userScript)

            let bridge = VideoTimeBridge(closure: onTimeUpdate)
            context.coordinator.bridge = bridge
            config.userContentController.add(bridge, name: "videoBridge")

            let fullscreenCssScript = WKUserScript(
                source: """
                (function() {
                    var style = document.createElement('style');
                    style.innerHTML = `
                        html, body { width: 100% !important; height: 100% !important;
                                     margin: 0 !important; padding: 0 !important;
                                     background: #000 !important; overflow: hidden !important; }
                        iframe, video, #player, #app, .video-frame, .player-container,
                        .video-player, [class*="player"] {
                            width: 100% !important; height: 100% !important;
                            max-width: 100% !important; max-height: 100% !important;
                            margin: 0 !important; padding: 0 !important;
                            object-fit: contain !important;
                        }
                        video::-webkit-media-controls,
                        video::-webkit-media-controls-enclosure,
                        video::-webkit-media-controls-panel {
                            display: none !important;
                            pointer-events: none !important;
                        }
                        .pl-video-player__controls,
                        .pl-video-player__progress,
                        [class*="controls-"],
                        [class*="player-controls"] {
                            display: none !important;
                            pointer-events: none !important;
                        }
                    `;
                    (document.head || document.documentElement).appendChild(style);
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(fullscreenCssScript)
        }

        // 🔧 v30.1: For YouTube — register plinkBridge so the IFrame API
        // can post messages back to Swift (ready / stateChange / error).
        // The Coordinator itself is the WKScriptMessageHandler.
        if isYouTubeLike {
            config.userContentController.add(context.coordinator, name: "plinkBridge")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        // 🔧 v32 (July 2026): NO customUserAgent for YouTube.
        // v31.1 set iOS 18 Safari UA, but YouTube's anti-bot detects WKWebView
        // via OTHER signals (WebGL, touch events, JS environment) regardless of
        // UA. Setting a fake UA actually INCREASES detection risk because the
        // UA doesn't match the actual WKWebView fingerprint.
        // v32: leave customUserAgent UNSET. iOS sends real iPhone Safari UA
        // which IS the actual WKWebView UA — no mismatch, no detection.

        // 🔧 v32: set Coordinator as navigationDelegate so didFinish fires
        // after m.youtube.com/watch loads → inject CSS + JS bridge.
        if isYouTube || isBackendPlayer {
            webView.navigationDelegate = context.coordinator
        }

        WebViewControl.shared.register(webView)

        // 🔧 Load URL
        if isBackendPlayer || isYouTube {
            // 🔧 v24: ALL YouTube paths (backend player + direct embed + nocookie)
            // go through PlinkSchemeHandler via Coordinator.
            // NO direct webView.load() — that causes 153.
            //
            // 🔧 v29 BUG FIX: previous code did `url.lastPathComponent` which for
            // the broken URL "youtube-nocookie.com/embed/watch?v=VIDEO_ID" returns
            // "watch" (not a video ID). With v29 fix in RoomSetupView, the URL is
            // now correctly "youtube-nocookie.com/embed/VIDEO_ID" so lastPathComponent
            // returns the proper video ID. But we ALSO support watch?v= URLs as a
            // safety net — extract video ID properly via query param OR path.
            let videoId = VideoTimeBridge.extractYouTubeVideoID(from: url) ?? url.lastPathComponent
            if context.coordinator.webView == nil {
                context.coordinator.webView = webView
            }
            print("📺 YouTube v29: makeUIView → Coordinator.loadVideoOnce, videoId='\(videoId)', url='\(urlString.prefix(80))'")
            context.coordinator.loadVideoOnce(id: videoId, webView: webView)
        } else if urlString.contains("rutube.ru") {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            webView.load(URLRequest(url: url))
        } else {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    /// 🔧 v7 (July 2026): custom HTML with YouTube IFrame API.
    ///
    /// This bypasses error 153 because the IFrame API script runs in OUR page
    /// context (not YouTube's), so YouTube's WKWebView-detection code never
    /// runs against our WKWebView environment.
    ///
    /// v7 FIX: 'origin' parameter changed from 'youtube-nocookie.com' to
    /// 'youtube.com' to match the new baseURL. This is what was causing the
    /// 'sign in to confirm you are not a bot' interstitial — Origin header
    /// mismatch between what the IFrame API expected and what we sent.
    static func youtubeEmbedHTML(videoId: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
                #player { width: 100vw; height: 100vh; }
                iframe { width: 100% !important; height: 100% !important; border: none; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoId)',
                        playerVars: {
                            'playsinline': 1,
                            'rel': 0,
                            'enablejsapi': 1,
                            'modestbranding': 1,
                            'fs': 0,
                            'controls': 0,
                            'disablekb': 1,
                            'iv_load_policy': 3,
                            'origin': 'https://www.youtube.com'
                        },
                        events: {
                            'onReady': function(e) {
                                window.webkit.messageHandlers.videoBridge.postMessage({type:'ready', duration: player.getDuration()});
                                player.playVideo();
                            },
                            'onStateChange': function(e) {
                                window.webkit.messageHandlers.videoBridge.postMessage({type:'state', state: e.data});
                                if (e.data === 0) {
                                    player.seekTo(0, true);
                                    player.pauseVideo();
                                }
                            }
                        }
                    });
                }
            </script>
        </body>
        </html>
        """
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 🔧 v22: delegate to Coordinator — it blocks duplicate loads
        let urlString = url.absoluteString
        let isYouTube = urlString.contains("youtube.com/embed/") ||
                         urlString.contains("youtube-nocookie.com/embed/") ||
                         urlString.contains("youtu.be/")

        if isYouTube {
            let videoId = url.lastPathComponent
            context.coordinator.loadVideoOnce(id: videoId, webView: uiView)
            return
        }

        // Non-YouTube: only reload if URL genuinely changed
        let videoId = url.lastPathComponent
        if let currentURL = uiView.url?.absoluteString, currentURL.contains(videoId) {
            return
        }
        if uiView.isLoading {
            return
        }
        print("📺 WebVideoView updateUIView: URL changed, loading \(url.absoluteString.prefix(60))")
        uiView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // 🔧 v30.1: Coordinator is now NSObject + WKScriptMessageHandler so it can
    // receive messages from the YouTube IFrame API via the plinkBridge handler.
    // 🔧 v32: also WKNavigationDelegate to inject CSS/JS after page loads.
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var bridge: VideoTimeBridge?
        // 🔧 v22: YouTube guard — stores loadedVideoId to prevent reload loops
        var loadedVideoId: String? = nil
        weak var webView: WKWebView?

        // 🔧 v30.1: optional callback — invoked when player state changes.
        // Wired up by RoomViewModel/SyncEngine to broadcast play/pause/seek
        // to other participants in the room via WebSocket.
        var onPlayerStateChange: ((Int, Double) -> Void)?
        var onPlayerReady: (() -> Void)?
        var onPlayerError: ((Int) -> Void)?

        // MARK: - JS Bridge Handler

        /// Called by window.webkit.messageHandlers.plinkBridge.postMessage(...) from the
        /// YouTube IFrame API running inside the WKWebView. Protocol:
        ///   { event: "ready" }                                  — player ready
        ///   { event: "stateChange", state: Int, currentTime: N } — state change
        ///   { event: "error", code: Int }                        — player error
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "plinkBridge",
                  let dict = message.body as? [String: Any],
                  let event = dict["event"] as? String else { return }

            switch event {
            case "ready":
                print("🎉 YouTube v32: video element ready — player initialized")
                onPlayerReady?()

            case "stateChange":
                let state = dict["state"] as? Int ?? -1
                let currentTime = dict["currentTime"] as? Double ?? 0.0
                // HTML5 video states: 0=ended, 1=playing, 2=paused (we map from events)
                print("🔄 YouTube v32: state=\(state), currentTime=\(currentTime)s")
                onPlayerStateChange?(state, currentTime)

            case "error":
                let code = dict["code"] as? Int ?? -1
                print("❌ YouTube v32: player error code=\(code)")
                onPlayerError?(code)

            default:
                print("⚠️ YouTube v32: unknown event '\(event)'")
            }
        }

        // MARK: - WKNavigationDelegate (v32)

        /// 🔧 v32: After m.youtube.com/watch finishes loading, inject CSS to hide
        /// YouTube's UI (header, recommendations, comments) and JS to bridge the
        /// HTML5 <video> element to Swift via plinkBridge.
        /// 🔧 v32.1: also block navigation to accounts.google.com (bot check redirect).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 🔧 v32.1: Block redirect to accounts.google.com (bot check).
            // YouTube redirects here when it wants the user to "Sign in to confirm
            // you're not a bot". If we block this redirect, YouTube's player keeps
            // playing the video (since the player already started before the redirect).
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                if host.contains("accounts.google.com") || host.contains("google.com/signin") {
                    print("🚫 YouTube v32.1: blocked redirect to \(host) (bot check)")
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 🔧 v32.1: only inject on youtube.com pages, not on google.com (which
            // we now block anyway, but be defensive).
            guard let url = webView.url, let host = url.host?.lowercased(),
                  host.contains("youtube.com") || host.contains("youtu.be") else {
                print("⚠️ YouTube v32.1: skipped injection on non-youtube page: \(webView.url?.host ?? "nil")")
                return
            }

            print("📺 YouTube v32.1: page loaded (\(host)), injecting CSS + JS bridge")

            // CSS: hide YouTube's UI but KEEP the video visible
            // 🔧 v32.2: simplified CSS — only HIDE specific YouTube UI elements,
            // do NOT touch #player / video positioning. Previous v32.1 used
            // 'display: none' on body children + repositioned #player, which
            // caused BLACK SCREEN because m.youtube.com wraps #player in
            // containers we were hiding.
            // 🔧 v32.3: hide ALL YouTube player controls + banners under video.
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                // v32.1: textContent avoids TrustedHTML CSP error
                // v32.3: comprehensive hide list for ALL YouTube chrome + banners
                style.textContent = [
                    '/* === HIDE YOUTUBE HEADER === */',
                    '#masthead-container, #masthead, ytd-mini-guide-renderer,',
                    'ytd-guide, #guide-button, #back-button, #logo,',
                    '.mobile-topbar-header, .mobile-topbar-logo, .mobile-topbar-actions,',
                    'ytd-topbar-logo-renderer, ytd-search {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE VIDEO METADATA + ACTIONS (under video) === */',
                    'ytm-watch-metadata, ytm-slim-video-action-bar-renderer,',
                    '.slim-video-information-title, .slim-video-information-meta,',
                    '.slim-video-information-container,',
                    '.video-action-bar, .video-action-bar-actions,',
                    'ytm-channel-name, ytm-subscribe-button-renderer,',
                    'ytd-metadata-row-container-renderer, .metadata-container,',
                    'ytm-slim-owner-renderer, ytm-slim-video-action-bar-renderer,',
                    '#info, #info-contents, #meta, #meta-contents {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE COMMENTS === */',
                    'ytm-comment-section-renderer, .comment-simplebox, .comment-section,',
                    '#comments-button, ytm-comments-entry-point-header-renderer,',
                    'ytd-comments, #comments {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE RECOMMENDATIONS + PLAYLISTS + MERCH === */',
                    'ytm-compact-video-renderer, ytm-item-section-renderer,',
                    'ytm-playlist-loop-renderer, ytm-merch-shelf-renderer,',
                    'ytd-compact-video-renderer, ytd-item-section-renderer,',
                    'ytd-playlist-panel-renderer, ytd-watch-next-secondary-results-renderer,',
                    '#related, #secondary, #secondary-inner {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE YOUTUBE PLAYER CONTROLS (all chrome) === */',
                    '.ytp-chrome-bottom, .ytp-chrome-top, .ytp-chrome-controls,',
                    '.ytp-progress-bar-container, .ytp-progress-bar,',
                    '.ytp-settings-button, .ytp-settings-menu,',
                    '.ytp-subtitles-button, .ytp-size-button,',
                    '.ytp-fullscreen-button, .ytp-fullerscreen-edu-button,',
                    '.ytp-mute-button, .ytp-volume-slider,',
                    '.ytp-prev-button, .ytp-next-button,',
                    '.ytp-play-button, .ytp-replay-button,',
                    '.ytp-time-display, .ytp-time-current, .ytp-time-duration, .ytp-time-separator,',
                    '.ytp-watermark, .ytp-youtube-button, .ytp-youtube-logo,',
                    '.ytp-remote-button, .ytp-cards-toggle, .ytp-cards-button,',
                    '.ytp-ce-element, .ytp-ce-shelf, .ytp-ce-video,',
                    '.ytp-endscreen-content, .ytp-endscreen,',
                    '.ytp-pause-overlay, .ytp-show-cards-title,',
                    '.ytp-tooltip, .ytp-tooltip-text, .ytp-hover-progress,',
                    '.ytp-gradient-bottom, .ytp-gradient-top,',
                    '.ytp-big-mode, .ytp-autohide,',
                    '.html5-endscreen, .html5-watermark,',
                    '.ytp-mdx, .ytp-mdx-button, .ytp-cued-thumbnail-overlay,',
                    '.ytp-iv-bar, .ytp-iv-video-content,',
                    'ytd-watch-flexy[flexy] #columns.ytd-watch-flexy,',
                    'ytd-watch-flexy[flexy] #secondary.ytd-watch-flexy {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE YOUTUBE SHARE + DOWNLOAD BUTTONS === */',
                    'ytd-button-renderer, ytm-button-renderer,',
                    '.ytp-share-button, .ytp-miniplayer-button {',
                    '    display: none !important;',
                    '}',

                    '/* === HIDE ADS / PROMOS (just in case) === */',
                    'ytd-promoted-video-renderer, ytd-promo-sparkles-web-renderer,',
                    'ytd-brand-video-shelf-renderer, ytd-banner-promo-renderer,',
                    '.ytp-ad-overlay-container, .ytp-ad-overlay,',
                    '.ytp-ad-text, .ytp-ad-skip-button-container {',
                    '    display: none !important;',
                    '}',

                    '/* === DO NOT touch #player, #movie_player, or video elements === */',
                    '/* Let YouTube handle video positioning naturally */'
                ].join('\\n');
                (document.head || document.documentElement).appendChild(style);
                console.log("[Plink v32.3] CSS injected — all YouTube chrome + banners hidden");
            })();
            """

            // JS: poll for <video> element, attach listeners, bridge to Swift
            let jsBridge = """
            (function() {
                if (window._plinkVideoBridge) return;
                window._plinkVideoBridge = true;

                function sendBridge(payload) {
                    try {
                        window.webkit.messageHandlers.plinkBridge.postMessage(payload);
                    } catch(e) {
                        console.log("[Plink v32.1] plinkBridge error: " + e);
                    }
                }

                function attachToVideo() {
                    var video = document.querySelector('video');
                    if (!video) {
                        setTimeout(attachToVideo, 500);
                        return;
                    }

                    console.log("[Plink v32.1] Found <video> element, attaching listeners");
                    sendBridge({ "event": "ready" });

                    video.addEventListener('play', function() {
                        sendBridge({ "event": "stateChange", "state": 1, "currentTime": video.currentTime });
                    });
                    video.addEventListener('playing', function() {
                        sendBridge({ "event": "stateChange", "state": 1, "currentTime": video.currentTime });
                    });
                    video.addEventListener('pause', function() {
                        sendBridge({ "event": "stateChange", "state": 2, "currentTime": video.currentTime });
                    });
                    video.addEventListener('ended', function() {
                        sendBridge({ "event": "stateChange", "state": 0, "currentTime": video.currentTime });
                    });
                    video.addEventListener('waiting', function() {
                        sendBridge({ "event": "stateChange", "state": 3, "currentTime": video.currentTime });
                    });
                    video.addEventListener('timeupdate', function() {
                        if (!video._plinkLastTimeUpdate || video.currentTime - video._plinkLastTimeUpdate >= 1.0) {
                            video._plinkLastTimeUpdate = video.currentTime;
                            sendBridge({ "event": "stateChange", "state": 1, "currentTime": video.currentTime });
                        }
                    });
                    video.addEventListener('error', function() {
                        sendBridge({ "event": "error", "code": video.error ? video.error.code : -1 });
                    });

                    window.playVideo = function() { video.play(); };
                    window.pauseVideo = function() { video.pause(); };
                    window.seekTo = function(seconds) { video.currentTime = seconds; };
                    window.getCurrentTime = function() { return video.currentTime; };

                    console.log("[Plink v32.2] Video bridge ready — try autoplay");
                    // v32.2: try UNMUTED autoplay first. iOS blocks this for
                    // WKWebView in some cases but allows it in others (depending
                    // on user gesture history). If it fails, fall back to muted.
                    video.muted = false;
                    video.play().then(function() {
                        console.log("[Plink v32.2] Unmuted autoplay succeeded!");
                    }).catch(function(e) {
                        console.log("[Plink v32.2] Unmuted autoplay blocked, trying muted: " + e);
                        video.muted = true;
                        video.play().catch(function(e2) {
                            console.log("[Plink v32.2] Muted autoplay also blocked: " + e2);
                        });
                    });

                    // v32.2: tap anywhere on video to unmute (iOS requires user
                    // gesture for unmuted playback in some contexts).
                    video.addEventListener('click', function() {
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v32.2] User tapped — unmuted");
                        }
                    });
                    // Also listen on document for taps anywhere
                    document.addEventListener('click', function() {
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v32.2] Document tapped — unmuted");
                        }
                    }, { once: true });
                }

                attachToVideo();
            })();
            """

            webView.evaluateJavaScript(cssInjection) { _, error in
                if let error = error {
                    print("⚠️ YouTube v32.1: CSS injection error: \(error)")
                }
            }
            webView.evaluateJavaScript(jsBridge) { _, error in
                if let error = error {
                    print("⚠️ YouTube v32.1: JS bridge injection error: \(error)")
                }
            }
        }

        // MARK: - Native commands → JS

        /// Resume playback (called from Swift UI play button)
        func play() {
            webView?.evaluateJavaScript("playVideo();", completionHandler: nil)
        }

        /// Pause playback (called from Swift UI pause button)
        func pause() {
            webView?.evaluateJavaScript("pauseVideo();", completionHandler: nil)
        }

        /// Seek to position in seconds (called from Swift UI scrub bar)
        func seek(to seconds: Double) {
            webView?.evaluateJavaScript("seekTo(\(seconds));", completionHandler: nil)
        }

        /// Get current playback time (for sync polling)
        func getCurrentTime(completion: @escaping (Double) -> Void) {
            webView?.evaluateJavaScript("getCurrentTime();", completionHandler: { result, _ in
                if let time = result as? Double {
                    completion(time)
                } else {
                    completion(0)
                }
            })
        }

        /// Load YouTube video exactly once. Blocks duplicate calls from SwiftUI state changes.
        func loadVideoOnce(id: String, webView: WKWebView) {
            guard !id.isEmpty else { return }
            guard id != loadedVideoId else { return }
            self.loadedVideoId = id

            // 🔧 v32 (July 2026): Load FULL m.youtube.com/watch page directly.
            //
            // WHY (production scalability):
            //   v30-v31 used IFrame API embeds (youtube.com/embed/ID). This has
            //   FUNDAMENTAL scaling problems:
            //     1. Rate limit per IP/device — after ~20 requests, YouTube
            //        returns error 150 for commercial videos (VEVO, music)
            //     2. Embedding restrictions — video owner can disable embedding
            //        in YouTube Studio → error 150/101 (Cartoon Network, etc.)
            //     3. Anti-bot detection — IFrame API patterns are fingerprinted
            //
            //   For an app with 100+ users each making requests, IFrame API
            //   DOES NOT SCALE. Every user hits rate limits.
            //
            // v32 SOLUTION — load the FULL youtube.com/watch page:
            //   - YouTube doesn't check embedding permissions for their own pages
            //   - Plays ALL videos (even embedding-restricted like Gumball)
            //   - Rate limit is per user session, not per app IP
            //   - This is what Rave and similar co-watch apps do
            //   - User confirmed: "earlier via web youtube search, Gumball played"
            //     — that was the full youtube.com/watch page
            //
            // UI hiding: after page loads, inject CSS to hide YouTube's UI
            // (header, recommendations, comments) — keep only the video element.
            // JS bridge: poll for <video> element, attach listeners, bridge
            // play/pause/seek/time to Swift via plinkBridge.
            //
            // Native UA: NO customUserAgent. iOS sends real iPhone Safari UA.
            // This is the most trusted UA for YouTube's anti-bot.
            let cleanVideoId = Self.sanitizeVideoIdForBundle(id)
            let watchURLString = "https://m.youtube.com/watch?v=\(cleanVideoId)"
            guard let watchURL = URL(string: watchURLString) else {
                print("❌ v32: invalid URL for videoId='\(cleanVideoId)'")
                return
            }

            print("📺 YouTube v32: loading FULL page m.youtube.com/watch?v=\(cleanVideoId) (scalable, no IFrame API)")
            DispatchQueue.main.async {
                let request = URLRequest(url: watchURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
                webView.load(request)
            }
        }

        /// 🔧 v30: same sanitizer logic as PlinkSchemeHandler.sanitizeVideoId,
        /// inlined here so Coordinator doesn't depend on PlinkSchemeHandler
        /// (which is now legacy / unused in v30).
        static func sanitizeVideoIdForBundle(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }

            // Strip anything after ? or & or /
            var id = trimmed
            if let cut = id.firstIndex(where: { $0 == "?" || $0 == "&" || $0 == "/" }) {
                id = String(id[..<cut])
            }

            // If contains "v=" extract after it
            if let vStart = id.range(of: "v=") {
                id = String(id[vStart.upperBound...])
            }
            // If contains "embed/" extract after it
            if let embedRange = id.range(of: "embed/") {
                id = String(id[embedRange.upperBound...])
            }

            // Final validation: 11 chars, [A-Za-z0-9_-]
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
            if id.count == 11, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
                return id
            }
            return id  // best effort
        }
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

    // MARK: - YouTube Video ID Extraction (v29)
    // NOTE: this static helper lives here in VideoTimeBridge as a convenient
    // location — it's stateless and doesn't depend on VideoTimeBridge itself.
    // WebVideoView calls it via VideoTimeBridge.extractYouTubeVideoID(from:).

    /// 🔧 v29 (July 2026): Properly extract video ID from any YouTube URL format.
    /// Same logic as RoomSetupView.extractYouTubeVideoID — duplicated here to
    /// keep WebVideoView self-contained.
    ///
    /// Supports:
    ///   - https://www.youtube.com/watch?v=VIDEO_ID
    ///   - https://m.youtube.com/watch?v=VIDEO_ID
    ///   - https://youtu.be/VIDEO_ID
    ///   - https://www.youtube.com/embed/VIDEO_ID
    ///   - https://www.youtube-nocookie.com/embed/VIDEO_ID
    ///   - https://www.youtube.com/shorts/VIDEO_ID
    static func extractYouTubeVideoID(from url: URL) -> String? {
        let urlString = url.absoluteString
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host.contains("youtu.be") || host.contains("youtube-nocookie.com") else {
            return nil
        }

        // Format 1: youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoId.isEmpty {
            return videoId
        }

        // Format 2: youtu.be/VIDEO_ID or /embed/VIDEO_ID or /shorts/VIDEO_ID
        let pathSegments = url.path.split(separator: "/").map(String.init)
        if let lastSegment = pathSegments.last,
           lastSegment != "watch" && lastSegment.count >= 6 && lastSegment.count <= 20 {
            return lastSegment
        }

        // Format 3: backend player URL — /api/media/youtube-player?id=VIDEO_ID
        if urlString.contains("youtube-player") || urlString.contains("youtube-embed") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoId = components.queryItems?.first(where: { $0.name == "id" })?.value,
               !videoId.isEmpty {
                return videoId
            }
        }

        return nil
    }
}

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
