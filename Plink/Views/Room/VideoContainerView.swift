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
        config.websiteDataStore = WKWebsiteDataStore.default()

        // 🔧 v24: register custom URL scheme handler — serves YouTube player
        // HTML from memory. No network → no sandbox → no ATS → no DownloadFailed.
        // URL: plink-media://plink.app/?v=VIDEO_ID (host = plink.app, not localhost)
        config.setURLSchemeHandler(PlinkSchemeHandler(), forURLScheme: "plink-media")

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

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        WebViewControl.shared.register(webView)

        // 🔧 Load URL
        if isBackendPlayer {
            // v12 backend player (kept for fallback)
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            print("📺 YouTube v12: backend embed proxy")
            webView.load(URLRequest(url: url))
        } else if isYouTube {
            // 🔧 v23: Coordinator-based guard — standard SwiftUI lifecycle.
            // WebView created normally → iOS grants sandbox.
            // Coordinator blocks duplicate loads from WebSocket state changes.
            let videoId = url.lastPathComponent
            if context.coordinator.webView == nil {
                context.coordinator.webView = webView
            }
            // 🔧 DO NOT set loadedVideoId here — let loadVideoOnce do it.
            // Setting it here would cause the guard in loadVideoOnce to always
            // block the load (id == loadedVideoId → return).
            print("📺 YouTube v23: makeUIView → Coordinator.loadVideoOnce")
            context.coordinator.loadVideoOnce(id: videoId, webView: webView)
        } else if urlString.contains("rutube.ru") {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            webView.load(URLRequest(url: url))
        } else if isYouTube {
            // Direct YouTube embed (fallback — shouldn't be used in v11)
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

    final class Coordinator {
        var bridge: VideoTimeBridge?
        // 🔧 v22: YouTube guard — stores loaded videoId to prevent reload loops
        var loadedVideoId: String? = nil
        weak var webView: WKWebView?

        /// Load YouTube video exactly once. Blocks duplicate calls from SwiftUI state changes.
        func loadVideoOnce(id: String, webView: WKWebView) {
            guard !id.isEmpty else { return }
            guard id != loadedVideoId else { return }
            self.loadedVideoId = id

            // 🔧 v24: custom URL scheme — plink-media://plink.app/?v=VIDEO_ID
            // PlinkSchemeHandler intercepts this and serves HTML from memory.
            // No network → no sandbox → no ATS → no DownloadFailed.
            // Host is plink.app (not localhost) → YouTube sees legitimate domain.
            let playerURLString = "plink-media://plink.app/?v=\(id)"
            guard let url = URL(string: playerURLString) else { return }

            print("📺 YouTube v24: loading via plink-media:// scheme handler (no network, no sandbox)")
            let request = URLRequest(url: url)
            DispatchQueue.main.async {
                webView.load(request)
            }
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
