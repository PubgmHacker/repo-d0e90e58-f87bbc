// Plink/Playback/EmbedPlaybackController.swift — P1 Cinema / Generic Web Embed
//
// Generic WKWebView-based controller for cinema services (Kinopoisk, Ivi, Okko, etc.)
// and other web pages that don't have a dedicated controller.
//
// Loads the watch page URL directly (user must be logged in on the service in Safari/WebView
// or the embed will prompt for subscription — App Store compliant).
//
// Attempts sync via injected JS that drives the first <video> element + common player globals.
// Best-effort for most services (full frame-accurate sync is impossible without their SDKs).

import Foundation
import WebKit
import UIKit
import Observation

@MainActor
@Observable
public final class EmbedPlaybackController: PlaybackControlling {
    public private(set) var isReady = false
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var lastError: String?

    public var capabilities: PlaybackCapabilities {
        PlaybackCapabilities(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    public private(set) var embeddedView: UIView?
    private var webView: WKWebView?
    private var sourceURL: URL?
    private var pollTask: Task<Void, Never>?

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        let playerURL: URL

        switch source {
        case .embed(let url):
            // Cinema service URL — load directly
            playerURL = url

        case .youtube(let videoId):
            // YouTube — load backend-hosted player page (avoids error 153)
            let baseURL = PlinkConfig.baseURLString
            guard let url = URL(string: "\(baseURL)/api/media/youtube-player?id=\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        case .rutube(let videoId):
            // Rutube — load embed page
            guard let url = URL(string: "https://rutube.ru/play/embed/\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        case .vk(let videoId):
            // VK Video — load embed page
            guard let url = URL(string: "https://vk.com/video_ext.php?\(videoId)") else {
                throw ProviderError.unsupportedSource
            }
            playerURL = url

        default:
            throw ProviderError.unsupportedSource
        }

        teardown()
        self.sourceURL = playerURL
        isReady = false
        lastError = nil

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false  // YouTube player doesn't need scroll
        web.translatesAutoresizingMaskIntoConstraints = false

        // Desktop UA for YouTube IFrame API compatibility
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        webView = web
        embeddedView = web

        web.load(URLRequest(url: playerURL))

        // Give the page a chance to render the player
        try? await Task.sleep(for: .seconds(2))

        // For YouTube: inject postMessage bridge for play/pause/seek
        if case .youtube = source {
            await injectYouTubeBridge()
        } else {
            await injectControlBridge()
        }
        isReady = true
        startPolling()
    }

    /// YouTube-specific control bridge via postMessage
    private func injectYouTubeBridge() async {
        guard let web = webView else { return }
        let bridge = """
        window.addEventListener('message', function(e) {
            try {
                var cmd = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                if (cmd.event === 'plink-yt') {
                    window.webkit.messageHandlers.plinkYT && window.webkit.messageHandlers.plinkYT.postMessage(cmd);
                }
            } catch(err) {}
        });
        // Also poll player state
        setInterval(function() {
            try {
                var iframe = document.querySelector('iframe');
                if (iframe && iframe.contentWindow) {
                    iframe.contentWindow.postMessage(JSON.stringify({event: 'listening', id: 'plink'}), '*');
                }
            } catch(err) {}
        }, 1000);
        """
        _ = try? await web.evaluateJavaScript(bridge)
    }

    public func play() async {
        guard isReady else { return }
        await evaluate(controlScript("play"))
    }

    public func pause() {
        guard isReady else { return }
        Task { await evaluate(controlScript("pause")) }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard isReady else { return .unavailable }
        let target = max(0, seconds)
        _ = await evaluate(controlScript("seek", arg: "\(target)"))
        position = target
        return .applied
    }

    public func setRate(_ rate: Float) {
        guard isReady else { return }
        Task { await evaluate(controlScript("rate", arg: "\(rate)")) }
    }

    public func teardown() {
        pollTask?.cancel()
        webView?.stopLoading()
        webView = nil
        embeddedView = nil
        isReady = false
        position = 0
        duration = 0
    }

    // MARK: - Internals

    private func injectControlBridge() async {
        let bridge = """
        (function() {
            if (window.__plinkEmbedBridgeInstalled) return true;
            window.__plinkEmbedBridgeInstalled = true;

            function getVideo() {
                return document.querySelector('video') || document.querySelector('video[playsinline]');
            }

            window.plinkEmbedPlay = function() {
                const v = getVideo();
                if (v) { v.play().catch(()=>{}); return true; }
                return false;
            };

            window.plinkEmbedPause = function() {
                const v = getVideo();
                if (v) { v.pause(); return true; }
                return false;
            };

            window.plinkEmbedSeek = function(s) {
                const v = getVideo();
                if (v) { v.currentTime = s; return true; }
                return false;
            };

            window.plinkEmbedRate = function(r) {
                const v = getVideo();
                if (v) { v.playbackRate = r; return true; }
                return false;
            };

            window.plinkEmbedSnapshot = function() {
                const v = getVideo();
                if (!v) return { time: 0, duration: 0, playing: false };
                return {
                    time: v.currentTime || 0,
                    duration: v.duration || 0,
                    playing: !v.paused && !v.ended
                };
            };

            // Try to auto-start muted if autoplay blocked (cinema sites often do this)
            setTimeout(() => {
                const v = getVideo();
                if (v && v.paused) {
                    v.muted = true;
                    v.play().catch(()=>{});
                }
            }, 800);

            return true;
        })();
        """
        _ = await evaluate(bridge)
    }

    private func controlScript(_ action: String, arg: String = "") -> String {
        switch action {
        case "play":  return "window.plinkEmbedPlay && window.plinkEmbedPlay();"
        case "pause": return "window.plinkEmbedPause && window.plinkEmbedPause();"
        case "seek":  return "window.plinkEmbedSeek && window.plinkEmbedSeek(\(arg));"
        case "rate":  return "window.plinkEmbedRate && window.plinkEmbedRate(\(arg));"
        default:      return ""
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snap = await self.evaluate("window.plinkEmbedSnapshot && window.plinkEmbedSnapshot();") as? [String: Any] {
                    if let t = snap["time"] as? Double, t.isFinite { self.position = t }
                    if let d = snap["duration"] as? Double, d > 0 { self.duration = d }
                    if let p = snap["playing"] as? Bool { self.isPlaying = p }
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    @discardableResult
    private func evaluate(_ js: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }
}
