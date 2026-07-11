// Plink/Playback/EmbeddedPlaybackController.swift
// Embedded (WKWebView) playback controller (Brain Review P0-8)
//
// Brain P0-8 fix: YouTubeEmbeddedProvider was a stub — it created a WKWebView
// but never registered the message handler, never exposed play/pause/seek/
// position via JS bridge, and NativePlayerController's play/pause/seek were
// no-ops for embedded providers.
//
// This file introduces a SEPARATE controller for embedded providers. It
// implements PlaybackControlling directly, NOT through AVPlayer. The
// PlaybackCoordinator (Stage 10 UI) chooses NativePlayerController for
// .hls/.mp4 sources and EmbeddedPlaybackController for .youtube sources.
//
// JS bridge contract (YouTube IFrame API):
//   - onReady → ready state
//   - onStateChange → isPlaying, isBuffering
//   - periodic position poll via getCurrentTime() every 250ms
//   - play/pause/seek via ytPlayer.playVideo()/pauseVideo()/seekTo()
//
// App Store compliance (runbook §7):
//   - YouTube controls + branding visible (controls=1, modestbranding=1)
//   - NO cookies leave device
//   - NO server-side extraction
//   - NO raw CDN proxy
//
// Capability limitations (runbook §19):
//   - supportsRateCorrection = false → OrderedSyncController uses less
//     frequent precise seeks with UX indicator

import Foundation
import UIKit
import WebKit
import Observation

@MainActor
@Observable
public final class EmbeddedPlaybackController: PlaybackControlling {
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    public private(set) var embeddedView: UIView?
    private var webView: WKWebView?
    private var videoId: String?
    private var ready: Bool = false
    // P1-15: pending seek as Double? so seek-to-zero is preserved
    private var pendingSeekSeconds: Double?
    private var pendingPlaying: Bool = false
    private var positionTimer: Timer?
    private var lastError: String?

    // Message handler class — must be NSObject for WKScriptMessageHandler.
    private let messageHandler = EmbeddedMessageHandler()

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        // P1-15: validate/sanitize video ID before interpolation into HTML
        guard Self.isValidVideoId(id) else {
            throw ProviderError.loadingFailed("Invalid YouTube video ID")
        }
        teardown()
        self.videoId = id
        ready = false
        lastError = nil

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = WKUserContentController()
        config.userContentController.add(messageHandler, name: "player")

        let web = WKWebView(frame: .zero, configuration: config)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.scrollView.isScrollEnabled = false
        self.webView = web
        self.embeddedView = web

        let onReady: () -> Void = { [weak self] in
            Task { @MainActor in self?.handleReady() }
        }
        let onStateChange: (Int) -> Void = { [weak self] state in
            Task { @MainActor in self?.handleStateChange(state) }
        }
        let onError: (Int) -> Void = { [weak self] code in
            Task { @MainActor in self?.handleError(code: code) }
        }
        messageHandler.onReady = onReady
        messageHandler.onStateChange = onStateChange
        messageHandler.onError = onError

        // P1-15: use JSON-encoded video ID instead of string interpolation
        // to prevent XSS / injection
        let videoIdJSON = try JSONSerialization.data(withJSONObject: [id], options: [])
        let videoIdArrayString = String(data: videoIdJSON, encoding: .utf8) ?? "[]"
        let html = Self.buildHTML(videoIdArray: videoIdArrayString)
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))

        // Await ready (5s timeout — degraded mode if not)
        let start = Date()
        while !ready, Date().timeIntervalSince(start) < 5 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
        }
        if !ready {
            // Timeout — proceed in degraded mode; UI shows error
            isBuffering = true
        }
    }

    public func play() async {
        guard ready else { pendingPlaying = true; return }
        evaluate("ytPlayer && ytPlayer.playVideo();")
        isPlaying = true
    }

    public func pause() {
        guard ready else { pendingPlaying = false; return }
        evaluate("ytPlayer && ytPlayer.pauseVideo();")
        isPlaying = false
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard ready else { pendingSeekSeconds = seconds; return .applied }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        guard let web = webView else { return .applied }
        do {
            _ = try await web.callAsyncJavaScript(
                "ytPlayer && ytPlayer.seekTo(seconds, true);",
                arguments: ["seconds": clamped],
                in: nil,
                in: .page
            )
            position = clamped
            return .applied
        } catch {
            lastError = "seek failed: \(error.localizedDescription)"
            return .applied  // P0-27: still resume — don't block caller
        }
    }

    public func setRate(_ rate: Float) {
        // YouTube IFrame API does not support setRate for non-PRO content
        // — capabilities.supportsRateCorrection = false.
        // OrderedSyncController falls back to less frequent precise seeks.
    }

    public func teardown() {
        positionTimer?.invalidate()  // P1-15: stop timer on teardown
        positionTimer = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        embeddedView = nil
        videoId = nil
        ready = false
        position = 0
        duration = 0
        isPlaying = false
        isBuffering = false
        pendingSeekSeconds = nil
        pendingPlaying = false
        messageHandler.onReady = nil
        messageHandler.onStateChange = nil
        messageHandler.onError = nil
    }

    // P1-15: surface YouTube error callback
    private func handleError(code: Int) {
        let message: String
        switch code {
        case 2: message = "Invalid video parameter"
        case 5: message = "HTML5 player error"
        case 100: message = "Video not found or private"
        case 101, 150: message = "Video not allowed to be embedded"
        default: message = "YouTube error code \(code)"
        }
        lastError = message
        isBuffering = false
        isPlaying = false
    }

    // ── JS bridge handlers ────────────────────────────────────────────────
    private func handleReady() {
        ready = true
        isBuffering = false
        // Apply any pending play/seek from before ready
        if pendingPlaying {
            Task { await play() }
            pendingPlaying = false
        }
        // P1-15: pending seek as Double? — seek-to-zero now preserved
        if let pending = pendingSeekSeconds {
            Task { await seek(to: pending, precise: true) }
            pendingSeekSeconds = nil
        }
        // Fetch duration
        evaluate("ytPlayer ? ytPlayer.getDuration() : 0") { result in
            if let d = result as? Double, d > 0 {
                self.duration = d
            }
        }
        // Start position polling
        startPositionPolling()
    }

    private func handleStateChange(_ state: Int) {
        // YouTube IFrame API states:
        //   -1 = unstarted
        //    0 = ended
        //    1 = playing
        //    2 = paused
        //    3 = buffering
        //    5 = cued
        switch state {
        case 1:
            isPlaying = true
            isBuffering = false
        case 2:
            isPlaying = false
            isBuffering = false
        case 3:
            isBuffering = true
        case 0:
            isPlaying = false
            isBuffering = false
        default:
            break
        }
    }

    private func startPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let web = self.webView else { return }
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    web.evaluateJavaScript("ytPlayer ? ytPlayer.getCurrentTime() : 0") { result, _ in
                        if let t = result as? Double, t.isFinite {
                            self.position = t
                        }
                        cont.resume()
                    }
                }
            }
        }
    }

    private func evaluate(_ js: String, completion: ((Any?) -> Void)? = nil) {
        webView?.evaluateJavaScript(js) { result, _ in
            completion?(result)
        }
    }

    // P1-15: validate YouTube video ID — only [A-Za-z0-9_-]{11}
    private static func isValidVideoId(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.allSatisfy { c in
            c.isLetter || c.isNumber || c == "_" || c == "-"
        }
    }

    // P1-15: build HTML with JSON-encoded video ID array (no string interpolation)
    private static func buildHTML(videoIdArray: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
          <body style="margin:0;background:#000;overflow:hidden;">
            <div id="player"></div>
            <script>
              var videoIds = \(videoIdArray);
              var ytPlayer;
              function onYouTubeIframeAPIReady() {
                ytPlayer = new YT.Player('player', {
                  videoId: videoIds[0],
                  width: '100%',
                  height: '100%',
                  playerVars: {
                    'controls': 1,
                    'modestbranding': 1,
                    'playsinline': 1,
                    'rel': 0,
                    'iv_load_policy': 3
                  },
                  events: {
                    'onReady': function() {
                      window.webkit.messageHandlers.player.postMessage({event:'ready'});
                    },
                    'onStateChange': function(e) {
                      window.webkit.messageHandlers.player.postMessage({event:'stateChange', state:e.data});
                    },
                    'onError': function(e) {
                      window.webkit.messageHandlers.player.postMessage({event:'error', code:e.data});
                    }
                  }
                });
              }
              var tag = document.createElement('script');
              tag.src = "https://www.youtube.com/iframe_api";
              document.head.appendChild(tag);
            </script>
          </body>
        </html>
        """
    }
}

// MARK: - Message handler bridge

private final class EmbeddedMessageHandler: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onStateChange: ((Int) -> Void)?
    var onError: ((Int) -> Void)?  // P1-15: surface YouTube error callback

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let event = body["event"] as? String
        switch event {
        case "ready":
            onReady?()
        case "stateChange":
            if let state = body["state"] as? Int {
                onStateChange?(state)
            }
        case "error":
            if let code = body["code"] as? Int {
                onError?(code)
            }
        default:
            break
        }
    }
}
