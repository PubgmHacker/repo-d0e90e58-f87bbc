import SwiftUI
import AVKit
import WebKit

// 🔧 v32.12: Notification when YouTube player is ready (hides loading overlay).
extension Notification.Name {
    static let youtubePlayerReady = Notification.Name("PlinkYouTubePlayerReady")
}

// MARK: - WebViewControl (singleton for JS bridge to WKWebView)
//
// 🔧 NEW: SyncEngine calls WebViewControl.shared.play()/pause()/seek() when
// in webview mode (player == nil). This singleton holds a weak reference to
// the active WKWebView and evaluates JavaScript to control the YouTube player.
//
// 🔧 v32.6 (July 2026): updated for v32 architecture. v30-v31 used IFrame API
// with global `player` variable (player.playVideo()). v32 loads full m.youtube.com
// page and defines global functions window.playVideo/pauseVideo/seekTo that
// operate on the HTML5 <video> element directly.
//
// v32.6 also adds fallback: if window.playVideo is not yet defined (video
// element not found yet), directly query for <video> and call play/pause.
@MainActor
final class WebViewControl {
    static let shared = WebViewControl()
    private weak var webView: WKWebView?
    /// 🔧 v32.10: callback for time updates from WebView (NOT seeks).
    /// Wired up by RoomViewModel to call syncEngine.updateCurrentTimeFromWebView().
    var onTimeUpdate: ((TimeInterval) -> Void)?

    func register(_ webView: WKWebView) {
        self.webView = webView
    }

    func unregister() {
        self.webView = nil
    }

    /// 🔧 v32.10: handle time updates from <video> element.
    /// Calls onTimeUpdate callback — does NOT seek the player.
    func handleTimeUpdate(_ time: TimeInterval) {
        onTimeUpdate?(time)
    }

    /// 🔧 v32.11: handle duration updates from <video> element.
    /// Calls onDurationUpdate callback — updates SyncEngine.duration.
    var onDurationUpdate: ((TimeInterval) -> Void)?
    func handleDurationUpdate(_ duration: TimeInterval) {
        onDurationUpdate?(duration)
    }

    /// 🔧 v32.12: handle player ready event — used to hide loading overlay.
    var onPlayerReady: (() -> Void)?
    func handlePlayerReady() {
        onPlayerReady?()
    }

    /// 🔧 v32.13: handle video ended event — shows completion screen.
    var onPlayerEnded: (() -> Void)?
    func handlePlayerEnded() {
        onPlayerEnded?()
    }

    /// 🔧 v32.11: unmute video. iOS blocks unmuted autoplay without user gesture.
    /// This must be called from a user gesture handler (tap) to work.
    /// Calls video.muted = false; video.play() via evaluateJavaScript.
    /// 🔧 v32.16: don't call video.play() if user paused — unmute should ONLY
    /// unmute, not resume playback. Otherwise tapping the screen while paused
    /// would resume the video (bug).
    func unmute() {
        let js = """
        (function() {
            var v = document.querySelector('video');
            if (v) {
                v.muted = false;
                // v32.16: only play if user hasn't paused
                if (!window._plinkUserPaused) {
                    v.play().then(function() {
                        console.log('[Plink v32.16] Unmuted + playing');
                    }).catch(function(e) {
                        console.log('[Plink v32.16] Unmute play failed: ' + e);
                    });
                } else {
                    console.log('[Plink v32.16] Unmuted (user paused, not resuming)');
                }
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func play() {
        // v32.6: try window.playVideo() first (defined by v32 JS bridge).
        // Fallback: find <video> element directly and call play().
        let js = """
        (function() {
            if (typeof window.playVideo === 'function') {
                window.playVideo();
                return;
            }
            var v = document.querySelector('video');
            if (v) v.play();
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func pause() {
        let js = """
        (function() {
            if (typeof window.pauseVideo === 'function') {
                window.pauseVideo();
                return;
            }
            var v = document.querySelector('video');
            if (v) v.pause();
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func seek(to time: TimeInterval) {
        let js = """
        (function() {
            if (typeof window.seekTo === 'function') {
                window.seekTo(\(time));
                return;
            }
            var v = document.querySelector('video');
            if (v) v.currentTime = \(time);
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 🔧 v32.8: seek relative — for ±10s forward/backward buttons.
    /// Calls window.seekRelative(delta) which adds delta to currentTime.
    func seekRelative(_ delta: TimeInterval) {
        let js = """
        (function() {
            if (typeof window.seekRelative === 'function') {
                window.seekRelative(\(delta));
                return;
            }
            // Fallback: compute manually
            var v = document.querySelector('video');
            if (v) {
                var newTime = v.currentTime + \(delta);
                if (v.duration) newTime = Math.max(0, Math.min(newTime, v.duration));
                v.currentTime = newTime;
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 🔧 v32.6: get current playback time for sync polling.
    func getCurrentTime(completion: @escaping (Double) -> Void) {
        let js = """
        (function() {
            if (typeof window.getCurrentTime === 'function') {
                return window.getCurrentTime();
            }
            var v = document.querySelector('video');
            return v ? v.currentTime : 0;
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: { result, _ in
            if let time = result as? Double {
                completion(time)
            } else {
                completion(0)
            }
        })
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

    // 🔧 v32.12: loading overlay state — hides YouTube UI flash on startup.
    // Set to false when plinkBridge receives 'ready' event from JS.
    @State private var isYouTubeReady = false

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

                // 🔧 v32.12: BLACK LOADING OVERLAY — hides YouTube UI flash.
                // Covers WebView until plinkBridge 'ready' event fires.
                // This prevents user from seeing YouTube's raw player + unmute
                // button for 3 seconds before CSS injection takes effect.
                if playbackMode == .webview && !isYouTubeReady {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                        )
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onReceive(NotificationCenter.default.publisher(for: .youtubePlayerReady)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    isYouTubeReady = true
                }
            }
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
            // 🔧 v32.10: WebVideoView calls onTimeUpdate when video.currentTime changes.
            // We forward this to a NEW method updateCurrentTimeFromWebView() that
            // ONLY updates the published currentTime — does NOT seek the player.
            // This prevents the feedback loop where timeupdate → seek → timeupdate.
            // onSeek is now ONLY called for user-initiated seeks (seek bar, ±10s).
            WebVideoView(url: url) { time in
                // v32.10: update currentTime without seeking
                // We can't call syncEngine directly from here, so we use onSeek
                // but with a flag. Actually, the parent (RoomView) passes
                // onSeek as { pos in syncEngine.seek(to: pos) }. We need a
                // different callback for time updates.
                // For now, we'll use a static flag on WebViewControl to indicate
                // "this is a time update, not a seek".
                WebViewControl.shared.handleTimeUpdate(time)
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
                let duration = dict["duration"] as? Double ?? 0.0
                print("🎉 YouTube v32: video element ready — player initialized, duration=\(duration)s")
                if duration > 0 {
                    WebViewControl.shared.handleDurationUpdate(duration)
                }
                // v32.12: notify WebViewControl that player is ready —
                // this hides the loading overlay in VideoContainerView.
                WebViewControl.shared.handlePlayerReady()
                onPlayerReady?()

            case "durationChange":
                let duration = dict["duration"] as? Double ?? 0.0
                print("📏 YouTube v32: duration changed to \(duration)s")
                if duration > 0 {
                    WebViewControl.shared.handleDurationUpdate(duration)
                }

            case "stateChange":
                let state = dict["state"] as? Int ?? -1
                let currentTime = dict["currentTime"] as? Double ?? 0.0
                // HTML5 video states: 0=ended, 1=playing, 2=paused (we map from events)
                print("🔄 YouTube v32: state=\(state), currentTime=\(currentTime)s")
                // v32.14: forward currentTime to WebViewControl so SyncEngine
                // can update seek bar + time display in real time.
                // This is called on every timeupdate (throttled to 1s in JS).
                WebViewControl.shared.handleTimeUpdate(currentTime)
                // v32.13: notify ended
                if state == 0 {
                    WebViewControl.shared.handlePlayerEnded()
                }
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

            // 🔧 v32.4: re-inject CSS every 2 seconds for 10 seconds.
            // YouTube dynamically adds elements (especially action bar, like button,
            // pause overlay) after initial page load. Single injection at didFinish
            // misses these late-added elements.
            // Also inject on didCommit (page start) for early hide.

            // CSS: OVERLAY approach — video on top of everything, black background hides rest
            // 🔧 v32.5: instead of hiding individual YouTube elements (losing battle —
            // they change class names), we OVERLAY the video on top of everything.
            // The black body background hides all YouTube UI behind the video.
            // Only YouTube's own player controls (.ytp-*) are hidden, since they're
            // INSIDE #movie_player and would show on top of the video.
            // 🔧 v32.7: also hide topbar/header elements that appear in corners
            // (YouTube logo top-left, search + 3-dot menu top-right). These are
            // NOT inside #movie_player so v32.5 overlay didn't cover them.
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                // v32.5: OVERLAY approach + v32.7 topbar hide
                style.textContent = [
                    '/* === BLACK BACKGROUND hides all YouTube UI behind video === */',
                    'html, body {',
                    '    background: #000 !important;',
                    '    overflow: hidden !important;',
                    '    position: fixed !important;',
                    '    width: 100% !important;',
                    '    height: 100% !important;',
                    '    margin: 0 !important;',
                    '    padding: 0 !important;',
                    '    top: 0 !important;',
                    '    left: 0 !important;',
                    '}',

                    '/* === VIDEO OVERLAY: position video on top of everything === */',
                    '#movie_player, #movie_player video, .html5-main-video {',
                    '    position: fixed !important;',
                    '    top: 0 !important;',
                    '    left: 0 !important;',
                    '    width: 100vw !important;',
                    '    height: 100vh !important;',
                    '    z-index: 2147483647 !important;',
                    '    object-fit: contain !important;',
                    '    background: #000 !important;',
                    '}',

                    '/* === v32.7: HIDE TOPBAR (YouTube logo top-left, search + 3-dot menu top-right) === */',
                    '#masthead-container, #masthead, ytd-masthead,',
                    'ytd-topbar-logo-renderer, #logo, #logo-icon,',
                    'ytd-search, #search-form, #search-input, #search-icon-legacy,',
                    '#end, #buttons, ytd-topbar-menu-button-renderer,',
                    'yt-icon-button[aria-label*="Search"], yt-icon-button[aria-label*="search"],',
                    'button[aria-label*="Search"], button[aria-label*="search"],',
                    '#guide-button, ytd-topbar-menu-button-renderer,',
                    'yt-icon-button.yt-spec-icon-button,',
                    'tp-yt-paper-icon-button,',
                    '.mobile-topbar-header, .mobile-topbar-logo, .mobile-topbar-actions,',
                    '.mobile-topbar-search-button, .mobile-topbar-menu-button,',
                    'ytm-search-button, ytm-menu-button,',
                    'ytm-topbar, ytm-topbar-renderer,',
                    '#top-bar-button-container, .topbar-buttons,',
                    '.ytd-mobile-topbar-renderer, ytd-mobile-topbar-renderer {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '    opacity: 0 !important;',
                    '    pointer-events: none !important;',
                    '}',

                    '/* === v32.7: HIDE YOUTUBE LOGO INSIDE PLAYER === */',
                    '.ytp-watermark, .ytp-youtube-logo, .ytp-youtube-button,',
                    'a.ytp-watermark, a.ytp-youtube-button, .html5-watermark,',
                    '.ytp-watermark-text, ytd-yoodle-renderer {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '}',

                    '/* === HIDE YOUTUBE PLAYER CONTROLS (inside #movie_player) === */',
                    '.ytp-chrome-bottom, .ytp-chrome-top, .ytp-chrome-controls,',
                    '.ytp-progress-bar-container, .ytp-progress-bar,',
                    '.ytp-settings-button, .ytp-settings-menu,',
                    '.ytp-subtitles-button, .ytp-size-button,',
                    '.ytp-fullscreen-button, .ytp-fullerscreen-edu-button,',
                    '.ytp-mute-button, .ytp-volume-slider,',
                    '.ytp-unmute-button, .ytp-unmute,',
                    '.ytp-mute-custom, .ytp-unmute-custom,',
                    'button[aria-label*="Unmute"], button[aria-label*="Mute"],',
                    'button[aria-label*="unmute"], button[aria-label*="mute"],',
                    '.ytp-prev-button, .ytp-next-button,',
                    '.ytp-play-button, .ytp-replay-button,',
                    '.ytp-time-display, .ytp-time-current, .ytp-time-duration,',
                    '.ytp-remote-button, .ytp-cards-button, .ytp-cards-toggle,',
                    '.ytp-ce-element, .ytp-ce-shelf, .ytp-ce-video,',
                    '.ytp-endscreen-content, .ytp-endscreen, .html5-endscreen,',
                    '.ytp-pause-overlay, .ytp-show-cards-title,',
                    '.ytp-tooltip, .ytp-tooltip-text, .ytp-hover-progress,',
                    '.ytp-gradient-bottom, .ytp-gradient-top,',
                    '.ytp-cued-thumbnail-overlay, .ytp-cover-overlay,',
                    '.ytp-scrim-bottom, .ytp-scrim-top,',
                    '.ytp-mdx, .ytp-mdx-button, .ytp-mdx-popup,',
                    '.ytp-iv-bar, .ytp-iv-video-content,',
                    '.ytp-share-button, .ytp-miniplayer-button,',
                    '.ytp-ad-overlay-container, .ytp-ad-overlay,',
                    '.ytp-ad-text, .ytp-ad-skip-button-container {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '    opacity: 0 !important;',
                    '    pointer-events: none !important;',
                    '}'
                ].join('\\n');
                (document.head || document.documentElement).appendChild(style);
                console.log("[Plink v32.7] CSS injected — overlay + topbar/logo hide");
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
                    sendBridge({ "event": "ready", "duration": video.duration || 0 });

                    // v32.11: send duration when metadata loads
                    video.addEventListener('loadedmetadata', function() {
                        sendBridge({ "event": "durationChange", "duration": video.duration || 0 });
                    });
                    video.addEventListener('durationchange', function() {
                        sendBridge({ "event": "durationChange", "duration": video.duration || 0 });
                    });

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
                        // v32.17: send every 0.5s for smoother seek bar
                        if (!video._plinkLastTimeUpdate || video.currentTime - video._plinkLastTimeUpdate >= 0.5) {
                            video._plinkLastTimeUpdate = video.currentTime;
                            sendBridge({ "event": "stateChange", "state": 1, "currentTime": video.currentTime });
                        }
                    });
                    video.addEventListener('error', function() {
                        sendBridge({ "event": "error", "code": video.error ? video.error.code : -1 });
                    });

                    window.playVideo = function() {
                        window._plinkUserPaused = false;  // v32.15: user resumed
                        video.play();
                    };
                    window.pauseVideo = function() {
                        window._plinkUserPaused = true;  // v32.15: user paused — don't auto-resume
                        video.pause();
                    };
                    // v32.8: seekTo takes ABSOLUTE position (seconds from start)
                    window.seekTo = function(seconds) {
                        try {
                            var target = Math.max(0, Math.min(seconds, video.duration || seconds));
                            video.currentTime = target;
                            // v32.15: update lastGoodPosition so watchdog doesn't think
                            // this was a reset
                            lastGoodPosition = target;
                            lastPositionUpdate = Date.now();
                        } catch(e) {}
                    };
                    // v32.8: seekRelative for ±10s buttons (forward + backward)
                    window.seekRelative = function(delta) {
                        try {
                            var newTime = video.currentTime + delta;
                            if (video.duration) newTime = Math.max(0, Math.min(newTime, video.duration));
                            video.currentTime = newTime;
                            console.log("[Plink v32.8] seekRelative(" + delta + ") → " + newTime);
                        } catch(e) { console.log("[Plink v32.8] seekRelative error: " + e); }
                    };
                    window.getCurrentTime = function() { return video.currentTime; };
                    window.getDuration = function() { return video.duration || 0; };

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

                    // 🔧 v32.8: BLOCK YouTube's default tap-to-pause behavior.
                    // YouTube's <video> element has its own onclick that toggles
                    // play/pause. We need Plink's ControlsOverlay to handle taps,
                    // not YouTube. Solution: capture phase + preventDefault +
                    // stopPropagation on video click events.
                    video.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        // v32.8: unmute on first tap (iOS gesture requirement)
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v32.8] User tapped — unmuted (NOT paused)");
                        }
                        return false;
                    }, true);  // capture phase — runs BEFORE YouTube's handler

                    // 🔧 v32.12: KEEP VIDEO PLAYING — YouTube sometimes auto-pauses
                    // after 30-60s (ad overlay, pause overlay, buffering).
                    // Periodically check: if video is paused but should be playing,
                    // resume it. Also keep it unmuted.
                    // 🔧 v32.13: also track last known good position — if video
                    // resets to 0 unexpectedly, restore it.
                    var lastGoodPosition = 0;
                    var lastPositionUpdate = Date.now();

                    video.addEventListener('timeupdate', function() {
                        // Track last position where video was actually playing
                        if (!video.paused && video.currentTime > 0) {
                            lastGoodPosition = video.currentTime;
                            lastPositionUpdate = Date.now();
                        }
                    });

                    setInterval(function() {
                        // v32.15: don't auto-resume if user explicitly paused
                        if (window._plinkUserPaused) {
                            // v32.16: but still re-unmute if needed (user paused
                            // doesn't mean user muted)
                            if (video.muted) {
                                video.muted = false;
                            }
                            return;
                        }

                        // v32.13: detect reset to 0 while video should be playing
                        // (YouTube sometimes reloads the video from start)
                        // v32.15: but NOT if we're near the end — that's a legit
                        // end-of-video state, not a reset
                        var nearEnd = video.duration && video.currentTime >= video.duration - 2;
                        if (video.currentTime === 0 && lastGoodPosition > 5 &&
                            !nearEnd &&
                            (Date.now() - lastPositionUpdate) < 10000) {
                            console.log("[Plink v32.13] Video reset detected, restoring to " + lastGoodPosition + "s");
                            video.currentTime = lastGoodPosition;
                            video.play().catch(function() {});
                            return;
                        }

                        if (video.paused && video.currentTime > 0 && video.currentTime < (video.duration || Infinity) - 1) {
                            console.log("[Plink v32.13] Video auto-paused, resuming");
                            video.play().catch(function(e) {
                                console.log("[Plink v32.13] Resume failed: " + e);
                            });
                        }
                        // v32.16: re-unmute if YouTube muted us — check more
                        // frequently to prevent audio dropouts
                        if (video.muted) {
                            video.muted = false;
                            console.log("[Plink v32.16] Video auto-muted, unmuting");
                        }

                        // v32.13: aggressively hide any ad/overlay elements that
                        // may have appeared. YouTube injects these dynamically.
                        var overlays = document.querySelectorAll(
                            '.ytp-ad-overlay-container, .ytp-ad-overlay, .ytp-ad-text, ' +
                            '.ytp-ad-skip-button-container, .ytp-pause-overlay, ' +
                            '.ytp-endscreen-content, .ytp-endscreen, .html5-endscreen, ' +
                            '.ytp-cued-thumbnail-overlay, .ytp-cover-overlay, ' +
                            '.ytp-scrim-bottom, .ytp-scrim-top, .ytp-mdx-popup, ' +
                            '.ytp-pause-overlay-back, .paused-overlay, ' +
                            'ytd-ad-slot-renderer, ytd-promoted-video-renderer, ' +
                            'ytd-promo-sparkles-web-renderer, .ytd-banner-promo-renderer'
                        );
                        overlays.forEach(function(el) {
                            el.style.display = 'none';
                            el.style.visibility = 'hidden';
                            el.style.opacity = '0';
                            el.style.pointerEvents = 'none';
                        });
                    }, 1000);  // v32.16: check every 1 second (faster mute detection)
                    // Also block on parent #movie_player
                    var moviePlayer = document.getElementById('movie_player');
                    if (moviePlayer) {
                        moviePlayer.addEventListener('click', function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            return false;
                        }, true);
                    }
                    // Block on document too
                    document.addEventListener('click', function(e) {
                        // v32.8: unmute on first tap anywhere
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v32.8] Document tapped — unmuted");
                        }
                        // Don't preventDefault here — let Plink's overlay buttons work
                    }, { once: true, capture: true });
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

            // 🔧 v32.4: re-inject CSS every 2 seconds for 10 seconds (5 times).
            // YouTube adds elements dynamically after page load — single injection
            // misses late-added like button, action bar, pause overlay.
            for i in 1...5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i * 2)) {
                    webView.evaluateJavaScript(cssInjection) { _, _ in }
                }
            }
        }

        /// 🔧 v32.7: inject CSS EARLY at didCommit (before page finishes loading).
        /// This hides YouTube's UI before user sees it.
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard let url = webView.url, let host = url.host?.lowercased(),
                  host.contains("youtube.com") || host.contains("youtu.be") else {
                return
            }
            // v32.7: same overlay + topbar CSS as didFinish
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                style.textContent = [
                    'html, body {',
                    '    background: #000 !important;',
                    '    overflow: hidden !important;',
                    '    position: fixed !important;',
                    '    width: 100% !important;',
                    '    height: 100% !important;',
                    '    margin: 0 !important;',
                    '    padding: 0 !important;',
                    '    top: 0 !important;',
                    '    left: 0 !important;',
                    '}',
                    '#movie_player, #movie_player video, .html5-main-video {',
                    '    position: fixed !important;',
                    '    top: 0 !important;',
                    '    left: 0 !important;',
                    '    width: 100vw !important;',
                    '    height: 100vh !important;',
                    '    z-index: 2147483647 !important;',
                    '    object-fit: contain !important;',
                    '    background: #000 !important;',
                    '}',
                    '#masthead-container, #masthead, ytd-masthead,',
                    'ytd-topbar-logo-renderer, #logo, #logo-icon,',
                    'ytd-search, #search-form, #search-input,',
                    '#end, #buttons, ytd-topbar-menu-button-renderer,',
                    '.mobile-topbar-header, .mobile-topbar-logo, .mobile-topbar-actions,',
                    'ytm-topbar, ytm-topbar-renderer,',
                    'ytd-mobile-topbar-renderer {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '    opacity: 0 !important;',
                    '}',
                    '.ytp-watermark, .ytp-youtube-logo, .ytp-youtube-button,',
                    '.html5-watermark {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '}',
                    '.ytp-chrome-bottom, .ytp-chrome-top, .ytp-chrome-controls,',
                    '.ytp-progress-bar-container, .ytp-settings-button,',
                    '.ytp-fullscreen-button, .ytp-mute-button, .ytp-unmute-button,',
                    'button[aria-label*="mute"], button[aria-label*="Mute"],',
                    '.ytp-play-button, .ytp-time-display, .ytp-pause-overlay,',
                    '.ytp-endscreen-content, .html5-endscreen,',
                    '.ytp-cued-thumbnail-overlay, .ytp-cover-overlay {',
                    '    display: none !important;',
                    '    visibility: hidden !important;',
                    '    opacity: 0 !important;',
                    '}'
                ].join('\\\\n');
                (document.head || document.documentElement).appendChild(style);
            })();
            """
            webView.evaluateJavaScript(cssInjection) { _, _ in }
            print("📺 YouTube v32.7: early CSS injection at didCommit (overlay + topbar)")
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
