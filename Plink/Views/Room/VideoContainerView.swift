import SwiftUI
import AVKit
import AVFoundation
import WebKit

// 🔧 v32.12: Notification when YouTube player is ready (hides loading overlay).
extension Notification.Name {
    static let youtubePlayerReady = Notification.Name("PlinkYouTubePlayerReady")
    /// 🔧 v42: Posted by Coordinator.appWillEnterForeground to force RoomView
    /// to re-evaluate its view tree. This triggers makeUIView again, which
    /// sees needsFullReload=true and recreates the WKWebView (the old one's
    /// WebContent process was killed during background).
    static let plinkWebviewNeedsReload = Notification.Name("PlinkWebviewNeedsReload")
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

    // MARK: - 🔧 v61 (Gemini): Pre-warming API
    //
    // Zero-Latency Init: when the user opens RoomCreationView and selects a
    // YouTube video, we IMMEDIATELY create a hidden WKWebView and start
    // loading the embed URL. By the time the user taps "Create Room" and
    // RoomView's makeUIView runs, the player is already initialized, logged
    // in, and buffered. The user sees instant playback — no 3-5s loading.
    //
    // How it works:
    //   1. RoomCreationView calls WebViewControl.shared.prewarm(videoId:)
    //   2. We create a WKWebView with the same config as WebVideoView uses
    //   3. We load m.youtube.com/watch?v=ID in it (off-screen, no parent view)
    //   4. When RoomView's makeUIView runs, it sees existing webView != nil
    //      → reuses the pre-warmed instance → no cold-start delay
    //
    // The prewarmedWebView is consumed by makeUIView via register() — it
    // becomes the active player. If the user cancels room creation, the
    // prewarmed instance is released when WebViewControl is deallocated or
    // when a different video is prewarmed.

    /// Pre-warmed WKWebView instance, waiting to be adopted by RoomView.
    private var prewarmedWebView: WKWebView?

    /// Pre-warm the player for a YouTube video.
    /// Call this when the user selects a video in RoomCreationView.
    /// The WKWebView starts loading m.youtube.com/watch?v=ID immediately.
    /// When RoomView's makeUIView runs, it will reuse this instance.
    func prewarm(videoId: String) {
        // Don't prewarm the same video twice
        if let existing = prewarmedWebView,
           loadedVideoId == videoId {
            print("🔥 v61: prewarm(videoId=\(videoId)) — already prewarmed, skipping")
            return
        }

        // Don't prewarm if there's already an active player using this video
        if webView != nil && loadedVideoId == videoId {
            print("🔥 v61: prewarm(videoId=\(videoId)) — active player already has this video, skipping")
            return
        }

        // 🔧 v62: If prewarming a DIFFERENT video, discard the old prewarmed
        // WKWebView first (it's stale — user changed their mind).
        if prewarmedWebView != nil && loadedVideoId != videoId {
            print("🔥 v62: prewarm — discarding stale prewarmed WKWebView (was videoId=\(loadedVideoId ?? "?"))")
            prewarmedWebView?.stopLoading()
            prewarmedWebView = nil
        }

        print("🔥 v61: prewarm(videoId=\(videoId)) — creating hidden WKWebView + loading m.youtube.com")

        // Create config matching what WebVideoView.makeUIView uses
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Inject the same CSS hide script as the active player uses
        let youtubeCssScript = WKUserScript(
            source: WebVideoView.youtubeHideCSS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(youtubeCssScript)

        // 🔧 v61: Native Experience — hide everything except <video>.
        // Must be injected in prewarm too, so the prewarmed WKWebView already
        // has it applied when makeUIView adopts it (makeUIView won't re-inject
        // scripts on the consumed instance).
        let nativeExperienceScript = WKUserScript(
            source: WebVideoView.nativeExperienceScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(nativeExperienceScript)

        // Create the prewarmed WKWebView
        let prewarmed = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        prewarmed.scrollView.isScrollEnabled = false
        prewarmed.isOpaque = false
        prewarmed.backgroundColor = .clear  // 🔧 v61: .clear instead of .black

        // Start loading m.youtube.com/watch?v=ID
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)")!
        prewarmed.load(URLRequest(url: url))

        // Store it — makeUIView will pick it up via consumePrewarmed()
        prewarmedWebView = prewarmed
        loadedVideoId = videoId  // mark as loaded so makeUIView doesn't reload

        print("🔥 v61: prewarm complete — WKWebView loading in background, will be adopted by RoomView.makeUIView")
    }

    /// Called by WebVideoView.makeUIView to consume the prewarmed WKWebView.
    /// Returns the prewarmed instance if one is available, otherwise nil
    /// (makeUIView will create a fresh WKWebView as before).
    func consumePrewarmed() -> WKWebView? {
        let prewarmed = prewarmedWebView
        prewarmedWebView = nil
        if prewarmed != nil {
            print("🔥 v61: consumePrewarmed — adopting prewarmed WKWebView (zero-latency init)")
        }
        return prewarmed
    }

    /// Discard any prewarmed WKWebView (e.g. when user cancels room creation).
    func discardPrewarm() {
        if prewarmedWebView != nil {
            print("🔥 v61: discardPrewarm — releasing prewarmed WKWebView")
            prewarmedWebView?.stopLoading()
            prewarmedWebView = nil
        }
    }

    // MARK: - 🔧 v62 (Gemini): Player Reactivation
    //
    // When a prewarmed WKWebView is adopted by RoomView.makeUIView and added
    // to the SwiftUI view hierarchy, its internal WKCompositingView sometimes
    // "falls asleep" — it thinks it's no longer on screen and stops rendering
    // video, leaving a black screen even though audio may still play.
    //
    // reactivate() forces WebKit to "wake up" the rendering pipeline:
    //   1. setNeedsDisplay() — pings the UIKit layer hierarchy
    //   2. JS resize event — forces WebKit to recompute viewport + repaint
    //   3. video.style.display = 'none' → force reflow → restore — forces the
    //      <video> element to re-attach to the GPU composite layer
    //   4. video.play() if paused — iOS sometimes pauses video on hierarchy change
    //
    // Call this from makeUIView via DispatchQueue.main.async AFTER the webView
    // has been added to the SwiftUI hierarchy (so setNeedsDisplay has somewhere
    // to send its invalidation to).
    func reactivate(webView: WKWebView) {
        print("⚡ v62: reactivate — forcing GPU repaint + video play")

        // 1. Ping UIKit layer hierarchy
        webView.setNeedsDisplay()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        webView.layer.setNeedsDisplay()
        webView.layer.setNeedsLayout()

        // 2. JS: dispatch resize event + force video reflow + resume if paused
        let js = """
        (function() {
            try {
                // Force WebKit to recompute viewport + repaint all layers
                window.dispatchEvent(new Event('resize'));

                var video = document.querySelector('video');
                if (video) {
                    // Force reflow: toggle display:none → read offsetHeight → restore
                    var oldDisplay = video.style.display;
                    video.style.display = 'none';
                    void video.offsetHeight;  // forces synchronous reflow
                    video.style.display = oldDisplay || 'block';

                    // iOS may have paused the video during hierarchy change — resume
                    if (video.paused) {
                        console.log('[Plink v62] Video was paused by hierarchy change — resuming');
                        if (typeof window.playVideo === 'function') {
                            window.playVideo();
                        } else if (window.player && typeof window.player.playVideo === 'function') {
                            window.player.playVideo();
                        } else {
                            video.play().catch(function(e) {
                                console.log('[Plink v62] Play resume failed: ' + e);
                            });
                        }
                    }

                    // Also nudge #movie_player to re-attach to GPU pipeline
                    var moviePlayer = document.querySelector('#movie_player');
                    if (moviePlayer) {
                        var oldPos = moviePlayer.style.position;
                        moviePlayer.style.position = 'absolute';
                        void moviePlayer.offsetHeight;
                        moviePlayer.style.position = oldPos || 'fixed';
                    }
                }
            } catch(e) {
                console.log('[Plink v62] reactivate error: ' + e);
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        // 3. Schedule a second reactivate after 300ms — sometimes the first
        // nudge isn't enough (GPU context is still being re-acquired).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let webView = self.webView, webView === self.webView else { return }
            webView.evaluateJavaScript("""
            (function() {
                try {
                    window.dispatchEvent(new Event('resize'));
                    var video = document.querySelector('video');
                    if (video && video.paused) {
                        if (typeof window.playVideo === 'function') window.playVideo();
                        else if (window.player && typeof window.player.playVideo === 'function') window.player.playVideo();
                        else video.play().catch(function(){});
                    }
                } catch(e) {}
            })();
            """, completionHandler: nil)
        }
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

    /// 🔧 v35.6: handle play state change from YouTube IFrame API.
    /// Updates SyncEngine.isPlaying so ControlsOverlay shows correct icon.
    var onPlayStateChange: ((Bool) -> Void)?
    func handlePlayStateChange(_ isPlaying: Bool) {
        onPlayStateChange?(isPlaying)
    }

    /// 🔧 v41: Flag to force a COMPLETE WKWebView recreation on next makeUIView.
    /// Set by RoomView.enterFullscreen / exitFullscreen BEFORE the layout change.
    /// When true, makeUIView will:
    ///   1. Save the current playback position via evaluateJavaScript
    ///   2. Remove the existing WKWebView from its superview
    ///   3. Set webView = nil (allow old WebContent process to terminate)
    ///   4. Create a brand-new WKWebView
    ///   5. Load the video URL fresh
    ///   6. Restore the saved position
    /// This is the ONLY reliable way to avoid "MediaSourcePrivateRemote object
    /// has been destroyed" — the rendering context is permanently dead after
    /// the WKWebView moves between view hierarchies, and no amount of
    /// reusing-the-same-instance will bring it back. Full reload is required.
    var needsFullReload = false

    /// 🔧 v41: Saved position to restore after a full reload.
    var savedPositionForReload: TimeInterval = 0

    /// 🔧 v41: Save current position, then mark for full reload on next makeUIView.
    /// Called by RoomView.enterFullscreen / exitFullscreen, AND by v42
    /// appWillEnterForeground (after WebContent process was killed during bg).
    ///
    /// 🔧 v42: Try to read position from JS first (works for fullscreen case
    /// where WebContent is still alive). If JS fails (WebContent killed during
    /// background), fall back to _plinkSavedBackgroundTime which was saved by
    /// appDidEnterBackground JS BEFORE the process was killed.
    func prepareForFullReload() {
        guard let webView = webView else {
            needsFullReload = true
            return
        }
        webView.evaluateJavaScript("""
        (function() {
            if (typeof getCurrentTime === 'function') return getCurrentTime();
            var v = document.querySelector('video');
            return v ? v.currentTime : 0;
        })();
        """) { [weak self] result, _ in
            let t = result as? Double ?? -1
            DispatchQueue.main.async {
                if t >= 0 {
                    // JS worked — WebContent process is alive (fullscreen case)
                    self?.savedPositionForReload = t
                } else {
                    // JS failed — WebContent process was killed (background case).
                    // Use the position saved by appDidEnterBackground JS before death.
                    // Read it via a SEPARATE evaluateJavaScript that checks the global.
                    self?.webView?.evaluateJavaScript("window._plinkSavedBackgroundTime || 0") { saved, _ in
                        DispatchQueue.main.async {
                            self?.savedPositionForReload = (saved as? Double) ?? 0
                            self?.needsFullReload = true
                            print("🔄 v42: prepareForFullReload — WebContent dead, using saved bg position \(self?.savedPositionForReload ?? 0)s")
                        }
                    }
                    return
                }
                self?.needsFullReload = true
                print("🔄 v41: prepareForFullReload — saved position \(t)s, will recreate WKWebView on next makeUIView")
            }
        }
    }

    /// 🔧 v41: Destroy the existing WKWebView completely.
    /// Called from makeUIView when needsFullReload is true.
    func destroyExistingWebView() {
        guard let webView = webView else { return }
        print("💥 v41: destroyExistingWebView — removing from superview, releasing WKWebView")
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "plinkBridge")
        webView.removeFromSuperview()
        self.webView = nil
        // Don't clear loadedVideoId — loadVideoOnce needs to know which video to reload.
        // loadVideoOnce has internal guard: if id == loadedVideoId → skip.
        // For full reload we need to BYPASS that guard — see makeUIView.
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
    /// 🔧 v44: AVPictureInPictureController for native PiP support.
    /// Created when the AVPlayer is ready. Automatically shows a floating
    /// PiP window when the app backgrounds (if video is playing).
    private var pipController: AVPictureInPictureController?

    init(url: URL, isPlaying: Bool, currentTime: TimeInterval, sharedPlayer: AVPlayer? = nil) {
        super.init(frame: .zero)
        backgroundColor = .black

        // 🔧 v44: Configure AVAudioSession for background playback + PiP.
        // Previously this was only set in WebVideoView.makeUIView (YouTube
        // WebView mode). Now directStream (AVPlayer) mode also needs it.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ v44: AVAudioSession config failed: \(error)")
        }

        if let shared = sharedPlayer {
            // 🔧 FIX H3: Use SyncEngine's AVPlayer — no second player created.
            player = shared
            ownsPlayer = false
            // Extract video output from the shared player's current item if present
            if let item = shared.currentItem {
                attachVideoOutput(to: item)
            }
            // 🔧 v44: Setup PiP for shared player
            setupPictureInPicture(for: shared)
        } else {
            // Fallback: create a local player (used in previews / tests / no-SyncEngine context)
            let item = AVPlayerItem(url: url)
            attachVideoOutput(to: item)

            let p = AVPlayer(playerItem: item)
            p.actionAtItemEnd = .pause
            player = p
            ownsPlayer = true

            if isPlaying { p.play() }
            // 🔧 v44: Setup PiP for local player
            setupPictureInPicture(for: p)
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

    /// 🔧 v44: Setup AVPictureInPictureController for native PiP.
    /// Requires:
    ///   - AVAudioSession category = .playback (set in WebVideoView.makeUIView)
    ///   - UIBackgroundModes: [audio, picture-in-picture] in Info.plist (added in v40)
    ///   - AVPlayerLayer must be attached to a view in the hierarchy
    /// When the app backgrounds, iOS automatically shows a PiP window if
    /// the video is playing. No JS hacks needed — this is the native iOS API.
    private func setupPictureInPicture(for player: AVPlayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("📱 v44: PiP not supported on this device")
            return
        }
        // AVPictureInPictureController requires the AVPlayerLayer to be
        // visible in the view hierarchy. We create it here but it won't
        // start PiP until the user backgrounds the app (or calls start()).
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        if let pip = pipController {
            // 🔧 v44: allow PiP to start automatically when app backgrounds
            if #available(iOS 14.2, *) {
                pip.canStartPictureInPictureAutomaticallyFromInline = true
            }
            pip.requiresLinearPlayback = false
            print("📱 v44: AVPictureInPictureController created — PiP ready")
        }
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

        // 🔧 v41: FULL RELOAD on orientation change.
        // Previous approach (v34-v40): reuse existing WKWebView when rotating
        // to avoid video reset. PROBLEM: "MediaSourcePrivateRemote object has
        // been destroyed" — when SwiftUI re-attaches the WKWebView to a new
        // view hierarchy (portrait → landscape), the WebContent rendering
        // context is permanently destroyed. The WKWebView is still "alive"
        // (JS still runs, audio still plays) but the visual rendering is gone
        // → BLACK SCREEN.
        //
        // v41 solution: RoomView.enterFullscreen/exitFullscreen calls
        // WebViewControl.shared.prepareForFullReload() BEFORE the layout change.
        // That saves the current position and sets needsFullReload = true.
        // Here in makeUIView, we check that flag:
        //   - If true: destroy the old WKWebView, create a new one, reload the
        //     video, restore the saved position. Brief flicker but video works.
        //   - If false: reuse the existing WKWebView (normal case, no rotation).
        if WebViewControl.shared.needsFullReload {
            print("💥 v41: makeUIView — needsFullReload=true, destroying old WKWebView")
            WebViewControl.shared.destroyExistingWebView()
            WebViewControl.shared.needsFullReload = false
            // Fall through to create a brand-new WKWebView below.
            // loadedVideoId is preserved so loadVideoOnce knows which video
            // to reload, but we need to bypass its "already loaded" guard.
            // See loadVideoOnceForceReload below.
        } else if let existing = WebViewControl.shared.webView {
            // 🔧 v53 (Gemini): Safe Reparenting — detach from old superview
            // BEFORE returning. This prevents WebKit GPU render crash when
            // SwiftUI calls makeUIView again after WS reconnect.
            existing.removeFromSuperview()
            print("📺 v53: reusing existing WKWebView (detached from old parent)")
            if isYouTube || isBackendPlayer {
                existing.navigationDelegate = context.coordinator
            }
            if context.coordinator.webView == nil {
                context.coordinator.webView = existing
            }
            if isYouTube || isBackendPlayer {
                let videoId = VideoTimeBridge.extractYouTubeVideoID(from: url) ?? url.lastPathComponent
                context.coordinator.loadVideoOnce(id: videoId, webView: existing)
            }
            return existing
        }

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        // 🔧 v40: Enable Picture-in-Picture for media playback.
        // This allows the video to continue playing in a small floating window
        // when the app is backgrounded (like YouTube / Rave do).
        // Requires UIBackgroundModes: [audio, picture-in-picture] in Info.plist
        // (added in v40).
        config.allowsPictureInPictureMediaPlayback = true
        // NOTE: background audio playback is enabled via UIBackgroundModes: [audio]
        // in Info.plist — that's the official Apple way. There's no need for a
        // WKWebView config flag; the WebContent process keeps the audio session
        // alive as long as AVAudioSession category is .playback (set in makeUIView).
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

            // 🔧 v39: Early CSS injection via WKUserScript (atDocumentStart).
            // Hides YouTube UI BEFORE it renders — no flash of unstyled content.
            // Previous approach injected CSS via evaluateJavaScript in didFinish,
            // which runs AFTER page load → user saw YouTube UI for ~1 second.
            // atDocumentStart runs before DOM is ready, but (document.head || document.documentElement)
            // works because documentElement always exists.
            let youtubeCssScript = WKUserScript(
                source: Self.youtubeHideCSS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(youtubeCssScript)

            // 🔧 v61 (Gemini): Native Experience — hide everything except <video>.
            // Runs on document.ready. Injected at .atDocumentEnd so it fires
            // after the DOM is ready, then retries at 1s/2s/3s.
            let nativeExperienceScript = WKUserScript(
                source: Self.nativeExperienceScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(nativeExperienceScript)
        }

        let webView: WKWebView
        // 🔧 v61 (Gemini): Try to consume a prewarmed WKWebView first.
        // If RoomCreationView prewarmed the player, we adopt that instance
        // — zero-latency init, player already loaded.
        let didConsumePrewarm: Bool
        if let prewarmed = WebViewControl.shared.consumePrewarmed() {
            webView = prewarmed
            // Re-attach navigation delegate so Coordinator callbacks fire
            webView.navigationDelegate = context.coordinator
            // Re-register the JS bridge handler (prewarmed instance doesn't have it)
            webView.configuration.userContentController.add(context.coordinator, name: "plinkBridge")
            // Adopt in Coordinator
            if context.coordinator.webView == nil {
                context.coordinator.webView = webView
            }
            WebViewControl.shared.register(webView)
            print("📺 v61: makeUIView consumed prewarmed WKWebView — videoId=\(WebViewControl.shared.loadedVideoId ?? "?")")
            didConsumePrewarm = true
        } else {
            webView = WKWebView(frame: .zero, configuration: config)
            webView.scrollView.isScrollEnabled = false
            webView.isOpaque = false
            webView.backgroundColor = .clear  // 🔧 v61: .clear instead of .black (Native Experience)
            didConsumePrewarm = false
        }

        // 🔧 v62 (Gemini): After makeUIView returns, the webView is added to
        // the SwiftUI hierarchy. We schedule reactivate() on the next run loop
        // so it runs AFTER the view is in the hierarchy. This forces WebKit to
        // re-attach to the GPU pipeline (especially important for prewarmed
        // instances that were off-screen during loading).
        let webViewRef = webView
        DispatchQueue.main.async {
            WebViewControl.shared.reactivate(webView: webViewRef)
        }
        _ = didConsumePrewarm  // suppress unused warning

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
            // 🔧 v43: Check if we just did a full reload (needsFullReload was true).
            // If so, bypass loadVideoOnce's "already loaded" guard by clearing
            // loadedVideoId first, then call loadVideoOnce which will reload.
            // Position is restored by the JS bridge (attachToVideo) which reads
            // window._plinkRestorePosition global — see evaluateJavaScript below.
            if WebViewControl.shared.savedPositionForReload > 0 {
                let pos = WebViewControl.shared.savedPositionForReload
                print("📺 YouTube v43: full reload — will restore position \(pos)s via JS global")
                WebViewControl.shared.loadedVideoId = nil  // bypass guard
                // 🔧 v43: Set window._plinkRestorePosition BEFORE the page loads.
                // evaluateJavaScript runs on the current page (about:blank or
                // previous page) — the global persists into the new page load
                // because WKWebView keeps the same JS context for main frame.
                // Actually, it DOESN'T persist across navigation. So we inject
                // it via a WKUserScript at documentStart instead. But since we
                // can't modify the config after creation, we use a different
                // approach: store it in the Coordinator and inject via
                // didCommit navigation callback.
                context.coordinator.pendingRestorePosition = pos
                WebViewControl.shared.savedPositionForReload = 0  // consume
                context.coordinator.loadVideoOnce(id: videoId, webView: webView)
            } else {
                print("📺 YouTube v29: makeUIView → Coordinator.loadVideoOnce, videoId='\(videoId)', url='\(urlString.prefix(80))'")
                context.coordinator.loadVideoOnce(id: videoId, webView: webView)
            }
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
                            'iv_load_policy': 3
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
            // 🔧 v54 (Gemini): Nudge WebKit to restore render after background
            DispatchQueue.main.async {
                uiView.setNeedsLayout()
                uiView.layoutIfNeeded()
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
        /// 🔧 v35.2: saved orientation lock before fullscreen
        private var _savedOrientationLock: UIInterfaceOrientationMask = .all
        /// 🔧 v43: position to restore after a full reload. Set by makeUIView
        /// when needsFullReload=true. Injected as window._plinkRestorePosition
        /// in didCommit (page start) so the JS bridge (attachToVideo) can read
        /// it when the <video> element appears.
        var pendingRestorePosition: TimeInterval = 0

        // MARK: - Lifecycle (v35) + Window Observer (v35.2)

        override init() {
            super.init()
            // 🔧 v40: REPLACED pause-on-resign with keep-playing + PiP-on-background.
            // Old behavior (v35): appWillResignActive paused the video, appDidBecomeActive
            //   did a micro-seek to restore render. User reported: "render stops, audio
            //   stops when opening notification shade" — annoying for co-watching.
            // New behavior (v40):
            //   - willResignActive (shade/control center): do nothing — video keeps playing.
            //     The video element keeps rendering because we set allowsBackgroundPlayback.
            //   - didEnterBackground (real background): trigger PiP so user sees floating
            //     window. If PiP isn't supported or video doesn't allow it, just keep playing.
            //   - willEnterForeground: exit PiP back to inline mode.
            //   - didBecomeActive: noop (no micro-seek needed — video never paused).
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification, object: nil
            )
            // 🔧 v40: Real background/foreground notifications for PiP trigger.
            NotificationCenter.default.addObserver(
                self, selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification, object: nil
            )
            // 🔧 v35.2: AVFullScreenViewController window observer.
            // When YouTube's native fullscreen player appears, allow all orientations.
            // When it disappears, restore previous lock.
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeVisible(_:)),
                name: UIWindow.didBecomeVisibleNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeHidden(_:)),
                name: UIWindow.didBecomeHiddenNotification, object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // 🔧 v35.2: Handle AVFullScreenViewController appearance
        @objc private func windowDidBecomeVisible(_ notification: Notification) {
            guard let window = notification.object as? UIWindow else { return }
            // Check if this is the AVFullScreenViewController window
            let className = String(describing: type(of: window.rootViewController ?? NSObject()))
            if className.contains("AVFullScreen") || className.contains("AVPlayer") {
                print("📱 v35.2: AVFullScreenViewController appeared — allowing all orientations")
                _savedOrientationLock = PlinkAppDelegate.orientationLock
                PlinkAppDelegate.orientationLock = .allButUpsideDown
                // Force UIKit to re-query supported orientations
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        @objc private func windowDidBecomeHidden(_ notification: Notification) {
            guard let window = notification.object as? UIWindow else { return }
            let className = String(describing: type(of: window.rootViewController ?? NSObject()))
            if className.contains("AVFullScreen") || className.contains("AVPlayer") {
                print("📱 v35.2: AVFullScreenViewController dismissed — restoring orientation lock")
                PlinkAppDelegate.orientationLock = _savedOrientationLock
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        // 🔧 v30.1: optional callback — invoked when player state changes.
        // Wired up by RoomViewModel/SyncEngine to broadcast play/pause/seek
        // to other participants in the room via WebSocket.
        var onPlayerStateChange: ((Int, Double) -> Void)?
        var onPlayerReady: (() -> Void)?
        var onPlayerError: ((Int) -> Void)?

        @objc private func appWillResignActive() {
            // 🔧 v47.4: NO-OP. Video keeps playing when notification shade is pulled down.
            // YouTube doesn't pause on shade open, we don't either.
            print("📱 v47.4: appWillResignActive — no-op (video keeps playing)")
        }

        /// 🔧 v60 (Gemini): REVERTED v57 zoom hack + v46.1 manual pause/resume.
        ///
        /// PROBLEM history:
        /// - v46.1: appDidEnterBackground called pauseVideo() → broke buffer on resume
        /// - v57: appDidBecomeActive called zoom + playVideo() → also broke buffer
        /// - v58: reverted v57, but v46.1 still active → still broke buffer
        ///
        /// v60 SOLUTION: ALL app lifecycle handlers are now no-ops. AVAudioSession
        /// (.playback + .moviePlayback) configured in v56 keeps AVPlayer/WebKit
        /// alive in background natively. YouTube's player manages its own buffer
        /// perfectly when we don't interfere.
        @objc private func appDidBecomeActive() {
            // 🔧 v60: NO-OP. AVAudioSession + AVPlayer handle background natively.
            // For WebView fallback mode, YouTube's player manages its own buffer
            // — any "nudge" from us just causes re-buffering (v57 lesson learned).
            print("📱 v60: appDidBecomeActive — no-op (AVAudioSession handles background)")
        }

        /// 🔧 v60 (Gemini): NO-OP. Removed v46.1 pause-on-background.
        ///
        /// PROBLEM with v46.1: When app entered background, we called pauseVideo()
        /// and on foreground called playVideo(). Logs confirmed this BROKE YouTube's
        /// buffer:
        ///   📱 v46.1: appDidEnterBackground — pausing video
        ///   📱 v46.1: appWillEnterForeground — resuming playback
        ///   🔄 YouTube v32: state=3, currentTime=5.591886060994289s  ← BUFFERING!
        ///
        /// The manual play() call forced YouTube to re-buffer (state 3), causing
        /// the 5-second freeze. This is exactly the bug we tried to fix with v57
        /// (which made it worse). The root cause all along was v46.1's manual
        /// intervention.
        ///
        /// v60 SOLUTION: With AVAudioSession (.playback + .moviePlayback) configured
        /// in v56, iOS keeps the audio process alive in background natively. We
        /// don't need to pause OR resume — just let the system handle it. YouTube's
        /// player manages its own buffer perfectly when we don't interfere.
        @objc private func appDidEnterBackground() {
            // 🔧 v60: NO-OP. AVAudioSession handles background audio natively.
            // Pausing the video here breaks YouTube's buffer (state=3) on resume.
            print("📱 v60: appDidEnterBackground — no-op (AVAudioSession handles background)")
        }

        /// 🔧 v60 (Gemini): NO-OP. Removed v46.1 resume-on-foreground.
        @objc private func appWillEnterForeground() {
            // 🔧 v60: NO-OP. AVAudioSession + AVPlayer (or YouTube's own player)
            // handle foreground resume natively. Calling playVideo() here was
            // forcing YouTube to re-buffer (state=3) → 5-second freeze.
            print("📱 v60: appWillEnterForeground — no-op (no manual resume)")
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
                print("🔄 YouTube v32: state=\(state), currentTime=\(currentTime)s")
                WebViewControl.shared.handleTimeUpdate(currentTime)

                // 🔧 v35.6: Update isPlaying state so ControlsOverlay shows
                // correct play/pause icon.
                // YT states: -1=unstarted, 0=ended, 1=playing, 2=paused, 3=buffering, 5=cued
                if state == 1 {
                    WebViewControl.shared.handlePlayStateChange(true)
                } else if state == 2 || state == 0 {
                    WebViewControl.shared.handlePlayStateChange(false)
                }

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
                if code == 101 || code == 150 || code == 152 || code == 153 {
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

            // 🔧 v36: ALWAYS use FULL CSS — we load m.youtube.com directly now.
            // Hide ALL YouTube UI, show only video on top of everything.
            let cssInjection = """
            (function() {
                var style = document.createElement('style');
                style.textContent = [
                    'html, body { background: #000 !important; overflow: hidden !important;',
                    '  position: fixed !important; width: 100% !important; height: 100% !important;',
                    '  margin: 0 !important; padding: 0 !important; top: 0 !important; left: 0 !important; }',
                    '#masthead-container, #masthead, ytd-masthead, ytd-mini-guide-renderer,',
                    'ytd-guide, #guide-button, #back-button, #logo,',
                    '.mobile-topbar-header, .mobile-topbar-logo, .mobile-topbar-actions,',
                    'ytm-watch-metadata, ytm-slim-video-action-bar-renderer,',
                    '.slim-video-information-title, .slim-video-information-meta,',
                    'ytm-channel-name, ytm-subscribe-button-renderer,',
                    'ytm-comment-section-renderer, #comments-button, ytd-comments, #comments,',
                    'ytm-compact-video-renderer, ytm-item-section-renderer, #related, #secondary,',
                    '.ytp-chrome-top, .ytp-settings-button,',
                    '.ytp-mute-button, .ytp-unmute-button,',
                    '.ytp-time-display, .ytp-watermark,',
                    '.ytp-pause-overlay, .ytp-endscreen-content, .html5-endscreen,',
                    '.ytp-cued-thumbnail-overlay, .ytp-cover-overlay,',
                    'button[aria-label*=\"mute\"], button[aria-label*=\"Mute\"],',
                    'button[aria-label*=\"unmute\"], button[aria-label*=\"Unmute\"],',
                    'ytd-topbar-logo-renderer, ytd-search, #search-form, #search-input,',
                    '#end, #buttons, ytd-topbar-menu-button-renderer,',
                    'ytm-topbar, ytm-topbar-renderer, ytd-mobile-topbar-renderer {',
                    '  display: none !important; visibility: hidden !important; opacity: 0 !important;',
                    '  pointer-events: none !important; }',
                    '#movie_player, #movie_player video, .html5-main-video {',
                    '  position: fixed !important; top: 0 !important; left: 0 !important;',
                    '  width: 100vw !important; height: 100vh !important; z-index: 2147483647 !important;',
                    '  object-fit: contain !important; background: #000 !important; }'
                ].join('\\\\n');
                (document.head || document.documentElement).appendChild(style);
                console.log("[Plink v36] CSS injected (m.youtube.com direct — FULL hide)");
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

                    // 🔧 v43: Restore position if _plinkRestorePosition was set
                    // by Swift (didCommit injection). This runs IMMEDIATELY when
                    // the <video> element is found, before YouTube's autoplay
                    // kicks in. The 'loadedmetadata' event fires when duration
                    // is known — we seek there.
                    if (window._plinkRestorePosition && window._plinkRestorePosition > 0) {
                        var restorePos = window._plinkRestorePosition;
                        window._plinkRestorePosition = 0;  // consume
                        console.log("[Plink v43] Will restore position to " + restorePos + "s");
                        var doRestore = function() {
                            if (video.duration > 0 || video.readyState >= 1) {
                                try {
                                    video.currentTime = restorePos;
                                    console.log("[Plink v43] Restored position to " + restorePos + "s");
                                } catch(e) {
                                    console.log("[Plink v43] Restore failed: " + e);
                                }
                            } else {
                                // metadata not loaded yet — retry in 200ms
                                setTimeout(doRestore, 200);
                            }
                        };
                        // Try immediately, then via loadedmetadata event as backup
                        doRestore();
                        video.addEventListener('loadedmetadata', function() {
                            if (video.currentTime < 0.5 && restorePos > 1) {
                                video.currentTime = restorePos;
                                console.log("[Plink v43] Restored via loadedmetadata to " + restorePos + "s");
                            }
                        }, { once: true });
                    }

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

                    // 🔧 v39: Let YouTube handle tap = play/pause natively.
                    // v32.8 blocked YouTube's tap (preventDefault + stopPropagation)
                    // because we had our own ControlsOverlay. v37 removed ControlsOverlay,
                    // so now we NEED YouTube's native tap-to-toggle. Just unmute on
                    // first tap (iOS gesture requirement), don't block the event.
                    video.addEventListener('click', function(e) {
                        if (video.muted) {
                            video.muted = false;
                            video.play();
                            console.log("[Plink v39] User tapped — unmuted");
                        }
                        // Don't preventDefault — let YouTube toggle play/pause.
                    }, true);  // capture phase — runs before YouTube's handler

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

                        // 🔧 v47.4: NO auto-resume, NO reset detection, NO micro-seeks.
                        // YouTube doesn't do this — we don't either.
                        // Only unmute if somehow muted, and hide ad overlays.

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

            // 🔧 v43: Inject window._plinkRestorePosition so the JS bridge
            // (attachToVideo) can restore playback position as soon as the
            // <video> element appears. This replaces the v41 3s/5s/7s polling
            // approach which was unreliable (video had already started playing
            // by the time the JS ran → currentTime > 0.5 → restore skipped).
            if pendingRestorePosition > 0 {
                let pos = pendingRestorePosition
                let restoreJS = """
                window._plinkRestorePosition = \(pos);
                console.log('[Plink v43] Set _plinkRestorePosition = ' + \(pos) + 's');
                """
                webView.evaluateJavaScript(restoreJS) { _, _ in
                    print("📺 YouTube v43: injected _plinkRestorePosition = \(pos)s at didCommit")
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
        /// 🔧 v36: DIRECT m.youtube.com loading — skip IFrame API (error 152).
        /// Load the REAL m.youtube.com/watch page, hide ALL YouTube UI via CSS,
        /// overlay Plink controls. YouTube handles video natively including
        /// swipe-down gesture in landscape.
        func loadVideoOnce(id: String, webView: WKWebView) {
            guard !id.isEmpty else { return }
            guard id != WebViewControl.shared.loadedVideoId else {
                print("📺 v36: video already loaded (\(id)) — skipping reload")
                return
            }
            WebViewControl.shared.loadedVideoId = id
            self.loadedVideoId = id
            WebViewControl.shared.didFallbackToFullPage = true  // skip IFrame API fallback

            let cleanVideoId = Self.sanitizeVideoIdForBundle(id)
            // 🔧 v39: use m.youtube.com — mobile UI is cleaner and the CSS
            // selectors match better. www.youtube.com on iPhone sometimes
            // serves the desktop layout which has different class names.
            let watchURLString = "https://m.youtube.com/watch?v=\(cleanVideoId)"
            guard let watchURL = URL(string: watchURLString) else { return }

            print("📺 YouTube v39: loading m.youtube.com/watch?v=\(cleanVideoId)")
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

    /// 🔧 v39: Comprehensive CSS to hide ALL YouTube UI — only show the video.
    /// Injected via WKUserScript at atDocumentStart so it applies BEFORE first paint.
    /// Hides: topbar, metadata, action bar (like/subscribe), comments, recommendations,
    ///        player chrome (controls, progress bar, fullscreen button, mute, play).
    /// Keeps visible: #movie_player, <video>, .html5-main-video (full-screen, contained).
    static let youtubeHideCSS: String = """
    (function() {
        var style = document.createElement('style');
        style.textContent = [
            'html, body { background:#000!important; overflow:hidden!important;',
            '  position:fixed!important; width:100%!important; height:100%!important;',
            '  margin:0!important; padding:0!important; top:0!important; left:0!important; }',
            // Topbar (desktop + mobile)
            '#masthead-container, #masthead, ytd-masthead, ytd-mini-guide-renderer,',
            'ytd-guide, #guide-button, #back-button, #logo,',
            '.mobile-topbar-header, .mobile-topbar-logo, .mobile-topbar-actions,',
            'ytd-topbar-logo-renderer, ytd-search, #search-form, #search-input,',
            '#end, #buttons, ytd-topbar-menu-button-renderer,',
            'ytm-topbar, ytm-topbar-renderer, ytd-mobile-topbar-renderer {',
            '  display:none!important; visibility:hidden!important; opacity:0!important;',
            '  pointer-events:none!important; }',
            // Watch page metadata + action bar (like, share, subscribe)
            'ytm-watch-metadata, ytd-watch-metadata, ytd-watch-flexy,',
            'ytm-slim-video-action-bar-renderer, ytd-slim-video-action-bar-renderer,',
            '.slim-video-information-title, .slim-video-information-meta,',
            'ytm-channel-name, ytm-subscribe-button-renderer, ytd-subscribe-button-renderer,',
            '#info, #info-contents, #meta, #meta-contents, ytd-video-primary-info-renderer,',
            'ytd-video-secondary-info-renderer {',
            '  display:none!important; visibility:hidden!important; opacity:0!important;',
            '  pointer-events:none!important; }',
            // Comments + related videos
            'ytm-comment-section-renderer, #comments-button, ytd-comments, #comments,',
            'ytm-compact-video-renderer, ytd-compact-video-renderer,',
            'ytm-item-section-renderer, ytd-item-section-renderer,',
            '#related, #secondary, ytd-watch-next-secondary-results-renderer {',
            '  display:none!important; visibility:hidden!important; opacity:0!important;',
            '  pointer-events:none!important; }',
            // YouTube player chrome (hide topbar + settings, KEEP bottom controls + fullscreen)
            '.ytp-chrome-top, .ytp-chrome-controls,',
            '.ytp-settings-button,',
            '.ytp-mute-button, .ytp-unmute-button,',
            '.ytp-next-button, .ytp-prev-button,',
            '.ytp-time-display, .ytp-watermark, .ytp-tooltip,',
            '.ytp-pause-overlay, .ytp-endscreen-content, .html5-endscreen,',
            '.ytp-cued-thumbnail-overlay, .ytp-cover-overlay,',
            '.ytp-scrim-bottom, .ytp-scrim-top, .ytp-mdx-popup,',
            '.ytp-pause-overlay-back, .paused-overlay,',
            'button[aria-label*="mute" i], button[aria-label*="unmute" i],',
            'button[aria-label*="settings" i],',
            '.ytp-ad-overlay-container, .ytp-ad-overlay, .ytp-ad-text,',
            '.ytp-ad-skip-button-container,',
            'ytd-ad-slot-renderer, ytd-promoted-video-renderer,',
            'ytd-promo-sparkles-web-renderer, .ytd-banner-promo-renderer {',
            '  display:none!important; visibility:hidden!important; opacity:0!important;',
            '  pointer-events:none!important; }',
            // KEEP bottom controls + fullscreen button VISIBLE
            '.ytp-chrome-bottom, .ytp-progress-bar-container, .ytp-progress-bar,',
            '.ytp-play-button, .ytp-fullscreen-button {',
            '  display:block!important; visibility:visible!important; opacity:1!important;',
            '  pointer-events:auto!important; }',
            // Make video player fullscreen (only visible element)
            '#movie_player, #movie_player video, .html5-main-video, video {',
            '  position:fixed!important; top:0!important; left:0!important;',
            '  width:100vw!important; height:100vh!important;',
            '  z-index:2147483647!important; object-fit:contain!important;',
            '  background:#000!important; }'
        ].join('\\n');
        (document.head || document.documentElement).appendChild(style);
        console.log('[Plink v39] CSS injected at documentStart (YouTube UI hidden)');
    })();
    """

    /// 🔧 v61 (Gemini): Native Experience — hide everything except <video>.
    /// Runs on document.ready (DOMContentLoaded). Aggressively removes
    /// every element that isn't the <video> tag or its parent #movie_player.
    /// This is the "nuclear" approach: even if YouTube adds new UI elements
    /// we don't know about, they get hidden.
    static let nativeExperienceScript: String = """
    (function() {
        function plinkNativeExperience() {
            try {
                var video = document.querySelector('video');
                if (!video) {
                    // Video not ready yet — retry in 500ms
                    setTimeout(plinkNativeExperience, 500);
                    return;
                }

                // Hide EVERYTHING except video, #movie_player, and its essential children
                var bodyChildren = document.body.children;
                for (var i = 0; i < bodyChildren.length; i++) {
                    var child = bodyChildren[i];
                    // Keep #movie_player (YouTube's player container)
                    if (child.id === 'movie_player' || child.id === 'player' || child.tagName === 'VIDEO') continue;
                    // Keep scripts and styles (don't break JS execution)
                    if (child.tagName === 'SCRIPT' || child.tagName === 'STYLE') continue;
                    // Hide everything else
                    try {
                        child.style.display = 'none !important';
                        child.style.visibility = 'hidden !important';
                        child.style.opacity = '0 !important';
                        child.style.position = 'absolute !important';
                        child.style.left = '-9999px !important';
                    } catch(e) {}
                }

                // Force #movie_player and <video> to fill viewport
                var moviePlayer = document.querySelector('#movie_player') || video.parentElement;
                if (moviePlayer) {
                    moviePlayer.style.cssText = 'position:fixed!important;top:0!important;left:0!important;width:100vw!important;height:100vh!important;z-index:2147483647!important;background:#000!important;';
                }
                video.style.cssText = 'position:fixed!important;top:0!important;left:0!important;width:100vw!important;height:100vh!important;object-fit:contain!important;z-index:2147483647!important;background:#000!important;';

                console.log('[Plink v61] Native Experience applied — only <video> visible');
            } catch(e) {
                console.log('[Plink v61] Native Experience error: ' + e);
            }
        }

        // Run on DOMContentLoaded (document.ready) + as fallback after 1s, 2s, 3s
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', plinkNativeExperience);
        } else {
            plinkNativeExperience();
        }
        setTimeout(plinkNativeExperience, 1000);
        setTimeout(plinkNativeExperience, 2000);
        setTimeout(plinkNativeExperience, 3000);
    })();
    """

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
