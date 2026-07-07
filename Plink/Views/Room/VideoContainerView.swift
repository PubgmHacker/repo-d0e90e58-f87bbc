import SwiftUI
import AVKit
import AVFoundation
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
    var webView: WKWebView?
    /// 🔧 v34.31: true after falling back to m.youtube.com (embed failed).
    /// Prevents reload loops: only fallback ONCE per video.
    var didFallbackToFullPage = false
    /// 🔧 v34.8: store loadedVideoId HERE (singleton) instead of Coordinator.
    /// When SwiftUI switches portraitLayout ↔ landscapeLayout, it creates a
    /// NEW Coordinator → loadedVideoId was nil → loadVideoOnce reloaded video.
    /// With singleton storage, loadedVideoId persists across Coordinator changes.
    var loadedVideoId: String?
    /// 🔧 v32.10: callback for time updates from WebView (NOT seeks).
    /// Wired up by RoomViewModel to call syncEngine.updateCurrentTimeFromWebView().
    var onTimeUpdate: ((TimeInterval) -> Void)?

    func register(_ webView: WKWebView) {
        self.webView = webView
    }

    func unregister() {
        self.webView = nil
        self.loadedVideoId = nil
        self.didFallbackToFullPage = false
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

    /// 🔧 v35: Full reload after rendering context loss.
    /// For IFrame API mode: saves position, reloads loadHTMLString, restores position.
    /// For m.youtube.com mode (fallback): reloads the URL.
    func forceReload() {
        guard let webView = webView else { return }
        // Save current position before reload
        webView.evaluateJavaScript("typeof getCurrentTime === 'function' ? getCurrentTime() : (document.querySelector('video')?.currentTime || 0)") { result, _ in
            let savedTime = result as? Double ?? 0
            print("🔄 v35: forceReload, saving position \(savedTime)s")

            // Check if we're in IFrame API mode (has our custom functions)
            webView.evaluateJavaScript("typeof onYouTubeIframeAPIReady === 'function'") { hasAPI, _ in
                let useHTML = hasAPI as? Bool ?? false

                DispatchQueue.main.async {
                    if useHTML, let videoId = WebViewControl.shared.loadedVideoId {
                        // IFrame API mode: reload loadHTMLString with same videoId
                        let html = WebVideoView.youtubeEmbedHTML(videoId: videoId)
                        let baseURL = URL(string: "https://www.youtube.com")!
                        webView.loadHTMLString(html, baseURL: baseURL)
                        print("🔄 v35: forceReload via loadHTMLString")
                    } else if let url = webView.url {
                        // m.youtube.com fallback mode: reload URL
                        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
                        print("🔄 v35: forceReload via URL reload")
                    }

                    // Restore position after reload
                    for delay in [3.0, 5.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.restorePosition(time: savedTime)
                        }
                    }
                }
            }
        }
    }

    /// Restore playback position after a page reload.
    private func restorePosition(time: Double) {
        let js = """
        (function() {
            var ct = 0;
            if (typeof getCurrentTime === 'function') {
                ct = getCurrentTime();
            } else {
                var v = document.querySelector('video');
                if (v) ct = v.currentTime;
            }
            if (ct < 0.5 && \(time) > 1) {
                if (typeof seekTo === 'function') {
                    seekTo(\(time));
                } else {
                    var v = document.querySelector('video');
                    if (v) v.currentTime = \(time);
                }
            }
            return 'restored';
        })();
        """
        webView?.evaluateJavaScript(js) { result, _ in
            print("🔄 v35: restorePosition(\(time)s) result: \(result ?? "?")")
        }
    }

    /// 🔧 FULLSCREEN FIX: Force YouTube player to recalculate its size after
    /// device rotation. In IFrame API mode (v35), the iframe + #player div need
    /// to be resized. In m.youtube.com fallback mode, the <video> element.
    func triggerResize() {
        let js = """
        (function() {
            var w = window.innerWidth, h = window.innerHeight;

            // v35: IFrame API mode — resize iframe + #player container
            var iframe = document.querySelector('iframe');
            if (iframe) {
                iframe.style.width = w + 'px';
                iframe.style.height = h + 'px';
            }
            var playerDiv = document.getElementById('player');
            if (playerDiv) {
                playerDiv.style.width = w + 'px';
                playerDiv.style.height = h + 'px';
            }
            // Resize inside the iframe too (if accessible)
            if (iframe && iframe.contentWindow) {
                try {
                    iframe.contentWindow.postMessage(JSON.stringify({
                        event: 'listening'
                    }), '*');
                } catch(e) {}
            }

            // m.youtube.com fallback mode — resize <video> + #movie_player
            var v = document.querySelector('video');
            if (v) {
                v.style.width = w + 'px';
                v.style.height = h + 'px';
            }
            var mp = document.getElementById('movie_player');
            if (mp) {
                mp.style.width = w + 'px';
                mp.style.height = h + 'px';
            }

            // 🔧 v34.26: do NOT dispatch orientationchange — YouTube reacts to it
            // by pausing + resetting video.
            console.log('[Plink v35] triggerResize: ' + w + 'x' + h);
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

    var onTogglePlay: () -> Void
    var onSeek: (TimeInterval) -> Void

    // 🔧 v32.12: loading overlay state — hides YouTube UI flash on startup.
    // Set to false when plinkBridge receives 'ready' event from JS.
    @State private var isYouTubeReady = false

    var body: some View {
        // 🔧 v34.25: REMOVED inner GeometryReader.
        // The parent (videoSection in RoomView) already sets .frame(height: videoHeight).
        // Inner GeometryReader caused double layout pass on rotation → SwiftUI
        // re-evaluated WebVideoView identity → makeUIView called again →
        // WKWebView recreated → video reset.
        ZStack {
            Color.black.opacity(0.3)

            switch playbackMode {
            case .directStream:
                directStreamView()
            case .webview:
                webVideoView()
            }

            if playbackMode == .webview && !isYouTubeReady {
                Color.black
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    )
                    .transition(.opacity)
            }
        }
        // 🔧 v34.25: fill whatever frame the parent gives us.
        // No explicit width/height — parent controls sizing.
        .onReceive(NotificationCenter.default.publisher(for: .youtubePlayerReady)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isYouTubeReady = true
            }
        }
    }

    // MARK: - Direct Stream (AVPlayer)

    @ViewBuilder
    private func directStreamView() -> some View {
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
        } else {
            VideoPlaceholder()
        }
    }

    // MARK: - WebView (кинотеатры)

    @ViewBuilder
    private func webVideoView() -> some View {
        if let url = URL(string: mediaURL) {
            // 🔧 v32.10: WebVideoView calls onTimeUpdate when video.currentTime changes.
            // We forward this to a NEW method updateCurrentTimeFromWebView() that
            // ONLY updates the published currentTime — does NOT seek the player.
            // This prevents the feedback loop where timeupdate → seek → timeupdate.
            // onSeek is now ONLY called for user-initiated seeks (seek bar, ±10s).
            // 🔧 v34.25: NO explicit frame — parent controls sizing via .frame(height:)
            WebVideoView(url: url) { time in
                WebViewControl.shared.handleTimeUpdate(time)
            }
        } else {
            VideoPlaceholder()
        }
    }
}

// MARK: - VideoPlayer Representable (AVPlayer wrapper)
//
// 🔧 FIX H3: PlayerUIView now accepts an EXTERNAL AVPlayer (from SyncEngine)
// instead of creating its own. This eliminates the dual-AVPlayer desync bug
// where SyncEngine controlled an invisible player while the user saw a
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
        // 🔧 v35: Configure AVAudioSession for background playback.
        // This keeps audio alive when notification shade/control center is pulled down.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ v35: AVAudioSession config failed: \(error)")
        }
        print("🔧🔧🔧 makeUIView CALLED — WebViewControl.shared.webView exists: \(WebViewControl.shared.webView != nil)")
        let urlString = url.absoluteString
        // 🔧 v14.1: must also match youtube-nocookie.com (v14 changed embed URL domain)
        let isYouTube = urlString.contains("youtube.com/embed/") ||
                         urlString.contains("youtube-nocookie.com/embed/") ||
                         urlString.contains("youtu.be/")
        // 🔧 v12: backend embed proxy URL
        let isBackendPlayer = urlString.contains("plink-backend") && (urlString.contains("youtube-player") || urlString.contains("youtube-embed"))

        // 🔧 v34: REUSE existing WebView if available (fullscreen rotation fix).
        // When device rotates, SwiftUI switches portraitLayout ↔ landscapeLayout.
        // These are different view trees → SwiftUI calls makeUIView again.
        // Without this check, a NEW WKWebView is created → video resets.
        // With this check, we return the EXISTING WebView from WebViewControl.
        // The video keeps playing because the WKWebView process is the same.
        if let existing = WebViewControl.shared.webView {
            print("📺 v34: reusing existing WKWebView (fullscreen rotation — no reset)")
            // Re-register coordinator as navigationDelegate (may have been lost)
            if isYouTube || isBackendPlayer {
                existing.navigationDelegate = context.coordinator
            }
            // Re-register coordinator as plinkBridge handler
            // (WKUserContentController handlers may need re-adding)
            // Actually, the config is part of the WebView — handlers persist.
            // Just make sure coordinator.webView points to the existing one.
            if context.coordinator.webView == nil {
                context.coordinator.webView = existing
            }
            return existing
        }

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

            // 🔧 v34.26: EARLY orientation block — runs BEFORE YouTube loads.
            // Monkey-patch window.dispatchEvent to swallow orientationchange.
            // This prevents YouTube's player from pausing/resetting on rotation.
            let orientationBlockScript = WKUserScript(
                source: """
                (function() {
                    var _orig = window.dispatchEvent.bind(window);
                    window.dispatchEvent = function(event) {
                        if (event && event.type === 'orientationchange') {
                            console.log('[Plink v34.26] BLOCKED orientationchange (early)');
                            return false;
                        }
                        return _orig(event);
                    };
                    // Also override window.onorientationchange setter
                    try {
                        Object.defineProperty(window, 'onorientationchange', {
                            get: function() { return null; },
                            set: function() { console.log('[Plink v34.26] BLOCKED onorientationchange setter'); },
                            configurable: true
                        });
                    } catch(e) {}
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(orientationBlockScript)
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

        // 🔧 v34.34: NO customUserAgent — real WKWebView UA (what m.youtube.com expects).
        // Embed required fake Safari UA, but m.youtube.com works with real WKWebView UA.
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

    /// 🔧 v35: custom HTML with YouTube IFrame API via loadHTMLString.
    /// Bypasses error 153 because the IFrame API script runs in OUR page
    /// context with baseURL: https://www.youtube.com.
    ///
    /// v35 improvements over v34.32:
    /// - Render freeze detector (webkitDecodedFrameCount polling)
    /// - Playback keep-alive watchdog (auto-resume after YouTube auto-pause)
    /// - Position reset protection
    /// - Proper origin parameter matching baseURL
    static func youtubeEmbedHTML(videoId: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
                #player { width: 100%; height: 100%; position: absolute; top: 0; left: 0; }
                iframe { width: 100% !important; height: 100% !important; border: none !important; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
                var player;
                var _plinkUserPaused = false;
                var _plinkLastDecoded = 0;
                var _plinkFrozenSince = 0;
                var _plinkLastGoodPosition = 0;
                var _plinkLastPositionUpdate = Date.now();

                function send(type, data) {
                    try { window.webkit.messageHandlers.plinkBridge.postMessage(Object.assign({event: type}, data || {})); } catch(e) {}
                }

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
                                send('ready', { duration: player.getDuration() });
                                player.playVideo();
                            },
                            'onStateChange': function(e) {
                                send('stateChange', { state: e.data, currentTime: player.getCurrentTime() });
                                if (e.data === 0) { player.seekTo(0, true); player.pauseVideo(); }
                            },
                            'onError': function(e) {
                                send('error', { code: e.data });
                            }
                        }
                    });

                    // Poll time every 0.5s + render freeze detector + keep-alive
                    setInterval(function() {
                        if (!player || !player.getCurrentTime) return;

                        var ct = player.getCurrentTime();
                        var dur = player.getDuration();
                        var playerState = player.getPlayerState();

                        // Send time update
                        send('stateChange', { state: playerState === 1 ? 1 : playerState, currentTime: ct });

                        // Track last good position
                        if (playerState === 1 && ct > 0) {
                            _plinkLastGoodPosition = ct;
                            _plinkLastPositionUpdate = Date.now();
                        }

                        // 🔧 v35.1: Render freeze detector — use IFrame API state instead
                        // of cross-origin iframe.contentDocument (which is always null
                        // for YouTube iframes due to Same-Origin Policy).
                        // Detect freeze: playerState == 1 (playing) but currentTime
                        // hasn't changed for 3+ seconds.
                        var frozenDetected = false;
                        if (playerState === 1 && ct > 0) {
                            if (ct === _plinkLastDecoded && ct > 0) {
                                if (_plinkFrozenSince === 0) {
                                    _plinkFrozenSince = Date.now();
                                } else if (Date.now() - _plinkFrozenSince > 3000) {
                                    console.log('[Plink v35.1] RENDER FROZEN — ct stuck at ' + ct);
                                    send('renderFrozen', {});
                                    _plinkFrozenSince = Date.now() + 60000;
                                    frozenDetected = true;
                                }
                            } else {
                                _plinkFrozenSince = 0;
                            }
                            _plinkLastDecoded = ct;
                        }

                        // 🔧 v35: Keep-alive — auto-resume if YouTube auto-pauses
                        if (!frozenDetected && !_plinkUserPaused && playerState === 2 && ct > 0 && ct < (dur || Infinity) - 1) {
                            console.log('[Plink v35] Auto-resuming after YouTube pause');
                            player.playVideo();
                        }
                    }, 1000);
                }

                // Swift bridge functions
                window.playVideo = function() {
                    _plinkUserPaused = false;
                    if (player) player.playVideo();
                };
                window.pauseVideo = function() {
                    _plinkUserPaused = true;
                    if (player) player.pauseVideo();
                };
                window.seekTo = function(s) {
                    if (player) {
                        player.seekTo(s, true);
                        _plinkLastGoodPosition = s;
                        _plinkLastPositionUpdate = Date.now();
                    }
                };
                window.getCurrentTime = function() { return player ? player.getCurrentTime() : 0; };
                window.getDuration = function() { return player ? player.getDuration() : 0; };
                window.seekRelative = function(d) {
                    if (player) player.seekTo(player.getCurrentTime() + d, true);
                };

                // Expose pause state for Swift queries
                window.isUserPaused = function() { return _plinkUserPaused; };
            </script>
        </body>
        </html>
        """
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 🔧 v35.1: MINIMAL updateUIView — just re-register coordinator if needed.
        // loadVideoOnce is only called from makeUIView (first time) — NOT here.
        // Previously this called loadVideoOnce on EVERY update (including fullscreen
        // toggle) → even though guard blocked reload, the evaluation itself caused
        // SwiftUI to re-evaluate the view → potential identity change → makeUIView.
        // Now: do nothing in updateUIView for YouTube. The WebView is controlled
        // via WebViewControl.shared (play/pause/seek) from Swift.
        let urlString = url.absoluteString
        let isYouTube = urlString.contains("youtube.com/embed/") ||
                         urlString.contains("youtube-nocookie.com/embed/") ||
                         urlString.contains("youtu.be/")

        if isYouTube {
            // Just ensure coordinator has the webView reference
            if context.coordinator.webView == nil {
                context.coordinator.webView = uiView
            }
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
    // 🔧 v35: also listens for app lifecycle events (willResignActive/didBecomeActive)
    // to pause/resume playback and fix render freeze.
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var bridge: VideoTimeBridge?
        // 🔧 v22: YouTube guard — stores loadedVideoId to prevent reload loops
        var loadedVideoId: String? = nil
        weak var webView: WKWebView?
        /// 🔧 v35: saved state for lifecycle pause/resume
        private var _savedPlaybackTime: Double = 0

        // 🔧 v30.1: optional callback — invoked when player state changes.
        // Wired up by RoomViewModel/SyncEngine to broadcast play/pause/seek
        // to other participants in the room via WebSocket.
        var onPlayerStateChange: ((Int, Double) -> Void)?
        var onPlayerReady: (() -> Void)?
        var onPlayerError: ((Int) -> Void)?

        // MARK: - Lifecycle (v35)

        override init() {
            super.init()
            // 🔧 v35: Pause video when app loses focus (notification shade, control center).
            // This prevents the render freeze — instead of letting WKWebView's compositor
            // die mid-stream, we pause cleanly and resume on didBecomeActive.
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil
            )
            // 🔧 v35: Resume video when app regains focus.
            // Micro-seek kick-starts the WKWebView rendering pipeline.
            NotificationCenter.default.addObserver(
                self, selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification, object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func appWillResignActive() {
            guard webView != nil else { return }
            // Save current time, then pause
            webView?.evaluateJavaScript("""
            (function() {
                if (typeof getCurrentTime === 'function') {
                    return getCurrentTime();
                }
                var v = document.querySelector('video');
                return v ? v.currentTime : 0;
            })();
            """) { result, _ in
                let t = result as? Double ?? 0
                self._savedPlaybackTime = t
                print("⏸️ v35: appWillResignActive — saved time \(t)s, pausing")
                self.webView?.evaluateJavaScript("""
                (function() {
                    if (typeof pauseVideo === 'function') pauseVideo();
                    else { var v = document.querySelector('video'); if (v) v.pause(); }
                })();
                """, completionHandler: nil)
            }
        }

        @objc private func appDidBecomeActive() {
            guard webView != nil else { return }
            print("▶️ v35: appDidBecomeActive — micro-seek to restore render")
            // Wait a beat for the UI to settle, then micro-seek + play
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, let wv = self.webView else { return }
                let savedTime = self._savedPlaybackTime
                wv.evaluateJavaScript("""
                (function() {
                    // Micro-seek: move ±0.1s to kick the rendering pipeline
                    if (typeof seekTo === 'function' && typeof getCurrentTime === 'function') {
                        var t = getCurrentTime();
                        var target = t === 0 && \(savedTime) > 1 ? \(savedTime) : t;
                        seekTo(target + 0.1);
                        setTimeout(function() { seekTo(target); }, 100);
                    }
                    if (typeof playVideo === 'function') playVideo();
                    else { var v = document.querySelector('video'); if (v) v.play().catch(function(){}); }
                })();
                """, completionHandler: nil)
            }
        }

        // MARK: - JS Bridge Handler

        /// Called by window.webkit.messageHandlers.plinkBridge.postMessage(...) from the
        /// YouTube IFrame API running inside the WKWebView. Protocol:
        ///   { event: "ready" }                                  — player ready
        ///   { event: "stateChange", state: Int, currentTime: N } — state change
        ///   { event: "error", code: Int }                        — player error
        ///   { event: "renderFrozen" }                             — render context frozen
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
                print("❌ YouTube v34.31: player error code=\(code)")
                // 🔧 v34.31: On embed errors (101/150/153), fallback to m.youtube.com.
                // 101 = embedding disabled by owner
                // 150 = embedding disabled OR rate limited
                // 153 = WKWebView loading error / referrer spoofing
                if code == 101 || code == 150 || code == 153 {
                    if !WebViewControl.shared.didFallbackToFullPage {
                        print("🔄 YouTube v34.31: embed failed (\(code)), falling back to m.youtube.com")
                        WebViewControl.shared.didFallbackToFullPage = true
                        if let vid = WebViewControl.shared.loadedVideoId,
                           let wv = self.webView {
                            let watchURL = URL(string: "https://m.youtube.com/watch?v=\(vid)")!
                            wv.load(URLRequest(url: watchURL, cachePolicy: .reloadIgnoringLocalCacheData))
                        }
                    }
                }
                onPlayerError?(code)

            case "renderFrozen":
                // 🔧 v35: WKWebView rendering context frozen (notification shade,
                // control center). Force micro-seek to kick compositor back to life.
                print("🧊 YouTube v35: render freeze detected — forcing micro-seek")
                webView?.evaluateJavaScript("""
                (function() {
                    if (typeof window.seekTo === 'function' && typeof window.getCurrentTime === 'function') {
                        var t = window.getCurrentTime();
                        window.seekTo(t + 0.1);
                        setTimeout(function() { window.seekTo(t); }, 100);
                    }
                })();
                """) { _, _ in }

            default:
                print("⚠️ YouTube v35: unknown event '\(event)'")
            }
        }

        // MARK: - WKNavigationDelegate (v32)

        /// 🔧 v32: After m.youtube.com/watch finishes loading, inject CSS to hide
        /// YouTube's UI (header, recommendations, comments) and JS to bridge the
        /// HTML5 <video> element to Swift via plinkBridge.
        /// 🔧 v32.1: block navigation to google.com (bot check redirect).
        /// 🔧 v34.11: also block www.google.com (not just accounts.google.com).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                // 🔧 v34.11: Block ALL google.com redirects EXCEPT youtube.com.
                // YouTube redirects to:
                //   - accounts.google.com/signin (bot check)
                //   - www.google.com/some/path (consent / bot check variant)
                // Both break video playback. Block them all.
                if (host.contains("google.com") && !host.contains("youtube.com") && !host.contains("youtu.be")) ||
                   host.contains("accounts.google.com") {
                    print("🚫 YouTube v34.11: blocked redirect to \(host) (bot check)")
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 🔧 v32.1: only inject on youtube pages, not on google.com.
            // 🔧 v34.30: also match youtube-nocookie.com (embed domain).
            guard let url = webView.url, let host = url.host?.lowercased(),
                  host.contains("youtube.com") || host.contains("youtube-nocookie.com") || host.contains("youtu.be") else {
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
            // 🔧 v34.30: Simple CSS for embed — just black bg, video fills screen.
            // No need for MutationObserver or nuclear CSS — embed is already clean.
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                style.textContent = [
                    'html, body {',
                    '    background: #000 !important;',
                    '    overflow: hidden !important;',
                    '    width: 100% !important; height: 100% !important;',
                    '    margin: 0 !important; padding: 0 !important;',
                    '}',
                    'iframe {',
                    '    width: 100% !important; height: 100% !important;',
                    '    border: none !important;',
                    '}',
                    'video {',
                    '    position: fixed !important;',
                    '    top: 0 !important; left: 0 !important;',
                    '    width: 100% !important; height: 100% !important;',
                    '    z-index: 999999 !important;',
                    '    object-fit: contain !important;',
                    '    background: #000 !important;',
                    '}'
                ].join('\\\\n');
                (document.head || document.documentElement).appendChild(style);
                console.log("[Plink v34.30] CSS injected (embed mode)");
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

                    // 🔧 v34.26: BLOCK YouTube from pausing/reloading on orientation change.
                    // (early block already installed at atDocumentStart, but belt+suspenders here)
                    // Override player.pauseVideo if YouTube's IFrame API created one
                    var _checkPlayerPause = setInterval(function() {
                        if (typeof player !== 'undefined' && player && player.pauseVideo) {
                            var _origPause = player.pauseVideo.bind(player);
                            player.pauseVideo = function() {
                                // Only block if we didn't trigger it ourselves
                                if (window._plinkUserPaused) {
                                    _origPause();
                                } else {
                                    console.log('[Plink v34.26] BLOCKED YouTube player.pauseVideo');
                                }
                            };
                            clearInterval(_checkPlayerPause);
                        }
                    }, 500);
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
                            if (video.muted) video.muted = false;
                            return;
                        }

                        // 🔧 v34.35: RENDER FREEZE DETECTOR.
                        // If video claims to be playing but decoded frame count
                        // hasn't changed for 3s → rendering context is frozen
                        // (notification shade, control center, etc).
                        // Signal Swift to reload the page.
                        var decoded = video.webkitDecodedFrameCount || 0;
                        if (!window._plinkLastDecoded) window._plinkLastDecoded = decoded;
                        if (!window._plinkFrozenSince) window._plinkFrozenSince = 0;

                        if (!video.paused && decoded === window._plinkLastDecoded) {
                            if (window._plinkFrozenSince === 0) {
                                window._plinkFrozenSince = Date.now();
                            } else if (Date.now() - window._plinkFrozenSince > 3000) {
                                console.log('[Plink v34.35] RENDER FROZEN — decoded=' + decoded + ', requesting reload');
                                sendBridge({ "event": "renderFrozen" });
                                window._plinkFrozenSince = Date.now() + 60000; // prevent spam
                            }
                        } else {
                            window._plinkFrozenSince = 0;
                        }
                        window._plinkLastDecoded = decoded;

                        // v32.13: detect reset to 0
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
                            video.play().catch(function() {});
                        }
                        if (video.muted) video.muted = false;

                        // hide ad/overlay elements
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
                    }, 1000);  // v34.35: every 1 second
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
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v34.30] Document tapped — unmuted");
                        }
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
                  host.contains("youtube.com") || host.contains("youtube-nocookie.com") || host.contains("youtu.be") else {
                return
            }
            // 🔧 v34.30: simple CSS for embed — black bg + video fullscreen.
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                style.textContent = [
                    'html, body { background:#000!important; overflow:hidden!important;',
                    '  width:100%!important; height:100%!important; margin:0!important; padding:0!important; }',
                    'iframe { width:100%!important; height:100%!important; border:none!important; }',
                    'video { position:fixed!important; top:0!important; left:0!important;',
                    '  width:100%!important; height:100%!important; z-index:999999!important;',
                    '  object-fit:contain!important; background:#000!important; }'
                ].join('\\n');
                (document.head || document.documentElement).appendChild(style);
            })();
            """
            webView.evaluateJavaScript(cssInjection) { _, _ in }
            print("📺 YouTube v34.30: early CSS injection at didCommit (embed mode)")
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
        /// 🔧 v34.8: uses WebViewControl.shared.loadedVideoId (singleton) instead of
        /// self.loadedVideoId (Coordinator instance). When SwiftUI switches portrait ↔
        /// landscape, it creates a NEW Coordinator → old loadedVideoId was nil → reload.
        /// With singleton, loadedVideoId persists across Coordinator recreation.
        ///
        /// 🔧 v35: loadHTMLString with IFrame API + baseURL: https://www.youtube.com
        /// This bypasses error 153 because the IFrame API script runs in OUR page
        /// context. The baseURL tells YouTube's origin check that we're from youtube.com.
        func loadVideoOnce(id: String, webView: WKWebView) {
            guard !id.isEmpty else { return }
            // v34.8: check SINGLETON loadedVideoId, not self.loadedVideoId
            guard id != WebViewControl.shared.loadedVideoId else {
                print("📺 v35: video already loaded (\(id)) — skipping reload")
                return
            }
            WebViewControl.shared.loadedVideoId = id
            self.loadedVideoId = id  // also keep local copy for compatibility
            WebViewControl.shared.didFallbackToFullPage = false  // reset fallback flag

            let cleanVideoId = Self.sanitizeVideoIdForBundle(id)

            // 🔧 v35: loadHTMLString with YouTube IFrame API + baseURL youtube.com
            // This is the "Headless" approach: IFrame API runs in our HTML context,
            // bypasses error 153 (origin spoofing). play/pause/seek via JS bridge.
            let htmlString = WebVideoView.youtubeEmbedHTML(videoId: cleanVideoId)
            let baseURL = URL(string: "https://www.youtube.com")!

            print("📺 YouTube v35: loading IFrame API via loadHTMLString, videoId='\(cleanVideoId)'")
            DispatchQueue.main.async {
                webView.loadHTMLString(htmlString, baseURL: baseURL)
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
