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
    private var pendingPositionMs: Double = 0
    private var pendingPlaying: Bool = false
    private var positionTimer: Timer?

    // Message handler class — must be NSObject for WKScriptMessageHandler.
    private let messageHandler = EmbeddedMessageHandler()

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        teardown()
        self.videoId = id
        ready = false

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = WKUserContentController()
        // P0-8: register the message handler under the name 'player'
        config.userContentController.add(messageHandler, name: "player")

        let web = WKWebView(frame: .zero, configuration: config)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.scrollView.isScrollEnabled = false
        self.webView = web
        self.embeddedView = web

        // Weak self capture for message handler closure
        let onReady: () -> Void = { [weak self] in
            Task { @MainActor in self?.handleReady() }
        }
        let onStateChange: (Int) -> Void = { [weak self] state in
            Task { @MainActor in self?.handleStateChange(state) }
        }
        messageHandler.onReady = onReady
        messageHandler.onStateChange = onStateChange

        let html = """
        <!DOCTYPE html>
        <html>
          <body style="margin:0;background:#000;overflow:hidden;">
            <div id="player"></div>
            <script>
              var ytPlayer;
              function onYouTubeIframeAPIReady() {
                ytPlayer = new YT.Player('player', {
                  videoId: '\(id)',
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

    public func seek(to seconds: TimeInterval, precise: Bool) async {
        guard ready else { pendingPositionMs = seconds * 1000; return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        evaluate("ytPlayer && ytPlayer.seekTo(\(clamped), true);")
        position = clamped
    }

    public func setRate(_ rate: Float) {
        // YouTube IFrame API does not support setRate for non-PRO content
        // — capabilities.supportsRateCorrection = false.
        // OrderedSyncController falls back to less frequent precise seeks.
    }

    public func teardown() {
        positionTimer?.invalidate()
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
        messageHandler.onReady = nil
        messageHandler.onStateChange = nil
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
        if pendingPositionMs > 0 {
            Task { await seek(to: pendingPositionMs / 1000, precise: true) }
            pendingPositionMs = 0
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
}

// MARK: - Message handler bridge

private final class EmbeddedMessageHandler: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onStateChange: ((Int) -> Void)?

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
            // Surface as a no-op state for now — telemetry in Stage 13
            break
        default:
            break
        }
    }
}
