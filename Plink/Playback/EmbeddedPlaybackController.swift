// Plink/Playback/EmbeddedPlaybackController.swift — PATCH 03
//
// GLM-5.2 master implementation patch — Commit Group 3.
//
// The single official YouTube embedded controller for the room session.
// Owns one WKWebView per room (runbook §16: 'Не добавлять еще один
// singleton WebView' — coordinator is per-room, never global).
//
// PATCH 03 changes from previous version:
//   - Public isReady + lastError properties for UI binding.
//   - 8s prepare timeout via withThrowingTaskGroup race (was 5s busy-wait).
//   - Pending enum consolidates pendingSeekSeconds + pendingPlaying.
//   - Cleaner HTML: plinkPlayer namespace, snapshot() helper for
//     position+duration in one JS round-trip.
//   - Teardown stops poll task via .cancel() (was Timer.invalidate only).
//   - Background/foreground polling throttle (250ms visible, 1s background).
//
// JS bridge contract (YouTube IFrame API):
//   - 'ready' → isReady = true, drain pending commands.
//   - 'state' (1/2/3/0) → isPlaying, isBuffering.
//   - 'error' (2/5/100/101/150) → lastError set, isBuffering cleared.
//   - poll task: plinkSnapshot() every 250ms (visible) / 1s (background).
//
// App Store compliance (runbook §7):
//   - Official YouTube IFrame API inside WKWebView.
//   - NO server-side extraction (no Innertube, no yt-dlp, no Piped).
//   - NO cookie relay — cookies never leave the device.
//   - NO raw CDN proxy.
//   - YouTube controls + branding visible (ToS): controls=1, modestbranding=1.
//
// Capability limitations (runbook §19):
//   - supportsRateCorrection = false → OrderedSyncController uses less
//     frequent precise seeks (drift threshold 500-750ms after device testing).

import Foundation
import UIKit
import WebKit
import Observation

@MainActor
@Observable
public final class EmbeddedPlaybackController: PlaybackControlling {
    // MARK: - Public state (UI binds to these)

    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false

    /// PATCH 03: ready state is now public. UI uses this to show "Loading…"
    /// vs "Buffering…" — loading means the player isn't ready yet;
    /// buffering means ready but mid-playback rebuffer.
    public private(set) var isReady: Bool = false

    /// PATCH 03: surface YouTube error callback for UI binding.
    public private(set) var lastError: String?

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: false,
            supportsAirPlay: false,
            supportsRateCorrection: false,
            supportsDRM: false
        )
    }

    // MARK: - Embedded view

    public private(set) var embeddedView: UIView?

    // MARK: - Private state

    private var webView: WKWebView?
    private var videoId: String?

    /// PATCH 03: Pending enum consolidates pending seek + play state.
    /// Drained atomically when isReady becomes true.
    /// PATCH 18 (P1-69): merge instead of overwrite — when a new command
    /// arrives before ready, merge it with the existing pending state so
    /// we don't lose position or play intent. The last seek wins (most
    /// recent user intent), but play/pause is preserved across seeks.
    private var pending: Pending = .none
    private enum Pending {
        case none
        case state(position: Double?, playing: Bool?)

        /// Merge a new command into existing pending state.
        /// - position: if non-nil, overrides existing position (last seek wins).
        /// - playing: if non-nil, overrides existing playing (last play/pause wins).
        /// If both are nil, returns self unchanged.
        func merging(position: Double?, playing: Bool?) -> Pending {
            switch self {
            case .none:
                if position == nil && playing == nil {
                    return .none
                }
                return .state(position: position, playing: playing)
            case .state(let existingPos, let existingPlaying):
                let mergedPos = position ?? existingPos
                let mergedPlaying = playing ?? existingPlaying
                return .state(position: mergedPos, playing: mergedPlaying)
            }
        }
    }

    private var pollTask: Task<Void, Never>?
    private let bridge = EmbeddedMessageHandler()

    public init() {}

    // MARK: - Prepare

    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        guard Self.isValidVideoId(id) else {
            throw ProviderError.loadingFailed("Invalid YouTube video ID")
        }

        teardown()
        self.videoId = id
        isReady = false
        lastError = nil

        // WKWebView configuration
        let content = WKUserContentController()
        content.add(bridge, name: "plinkPlayer")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.audio]
        config.userContentController = content
        config.websiteDataStore = .default()

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x0D/255, green: 0x00/255, blue: 0x1A/255, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.translatesAutoresizingMaskIntoConstraints = false
        webView = web
        embeddedView = web

        // Wire bridge callbacks
        bridge.onReady = { [weak self] in
            Task { @MainActor in self?.handleReady() }
        }
        bridge.onStateChange = { [weak self] state in
            Task { @MainActor in self?.handleStateChange(state) }
        }
        bridge.onError = { [weak self] code in
            Task { @MainActor in self?.handleError(code: code) }
        }

        // PATCH 03: JSON-encode video ID to prevent XSS / injection.
        // Use a single-element array (matches existing bridge contract).
        let encoded = try JSONEncoder().encode(id)
        let jsonId = String(decoding: encoded, as: UTF8.self)
        web.loadHTMLString(
            Self.buildHTML(videoIdJSON: jsonId),
            baseURL: URL(string: "https://plink-backend-production-ef31.up.railway.app")
        )

        // PATCH 03: 8s prepare timeout via task group race.
        // First task: poll isReady every 80ms until true.
        // Second task: 8s timeout throws loadingFailed.
        // Whichever finishes first wins; the other is cancelled.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                // PATCH 22: guard let self to bind to strong local const,
                // avoiding "Reference to captured var 'self'" Swift 6 error.
                guard let self else { return }
                while true {
                    let notReady = await MainActor.run {
                        self.isReady == false
                    }
                    if !notReady { return }
                    try await Task.sleep(for: .milliseconds(80))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw ProviderError.loadingFailed("YouTube player timed out")
            }
            _ = try await group.next()
            group.cancelAll()
        }

        startPolling()
    }

    // MARK: - PlaybackControlling

    public func play() async {
        guard isReady else {
            pending = pending.merging(position: nil, playing: true)
            return
        }
        await evaluate("window.plinkPlay && window.plinkPlay();")
    }

    public func pause() {
        guard isReady else {
            pending = pending.merging(position: nil, playing: false)
            return
        }
        Task { await evaluate("window.plinkPause && window.plinkPause();") }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        guard isReady else {
            pending = pending.merging(position: target, playing: nil)
            return .unavailable
        }
        // PATCH 03: plinkSeek returns true on success, undefined if not loaded.
        let result = await evaluate("window.plinkSeek && window.plinkSeek(\(target));")
        guard result != nil else { return .unavailable }
        position = target
        return .applied
    }

    public func setRate(_ rate: Float) {
        // YouTube IFrame API supports setPlaybackRate for some content,
        // but rate correction is disabled per capabilities.supportsRateCorrection
        // = false. OrderedSyncController falls back to precise seeks.
    }

    // MARK: - Teardown

    public func teardown() {
        pollTask?.cancel()
        pollTask = nil

        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "plinkPlayer")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        embeddedView = nil

        bridge.onReady = nil
        bridge.onStateChange = nil
        bridge.onError = nil

        videoId = nil
        isReady = false
        isPlaying = false
        isBuffering = false
        position = 0
        duration = 0
        pending = .none
    }

    // MARK: - Bridge handlers

    private func handleReady() {
        isReady = true
        isBuffering = false

        // Drain pending commands atomically.
        let command = pending
        pending = .none

        Task {
            if case .state(let p, let playing) = command {
                if let p { _ = await seek(to: p, precise: true) }
                if playing == true { await play() }
                if playing == false { pause() }
            }
        }

        // Fetch duration (fire-and-forget — position poll will keep it fresh).
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.evaluate("window.plinkSnapshot && window.plinkSnapshot();")
            if let dict = snapshot as? [String: Any] {
                if let d = dict["duration"] as? Double, d > 0 {
                    self.duration = d
                }
            }
        }
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

    private func handleError(code: Int) {
        // Brain §5.1: map official YouTube IFrame API error codes.
        // https://developers.google.com/youtube/iframe_api_reference#onError
        let message: String
        switch code {
        case 2:        message = "Invalid video parameter"
        case 5:        message = "HTML5 player error"
        case 100:      message = "Video not found or private"
        case 101, 150: message = "This video cannot be embedded in Plink"
        case 153:      message = "Missing client identity — try another video"
        default:       message = "YouTube error \(code) — try another video"
        }
        lastError = message
        isBuffering = false
        isPlaying = false
    }

    // MARK: - Polling

    /// PATCH 03: poll at 250ms while visible, 1s while backgrounded, stop
    /// after teardown. Position + duration in one JS round-trip via
    /// plinkSnapshot() to halve the IPC overhead.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isBackgrounded = await MainActor.run {
                    UIApplication.shared.applicationState == .background
                }
                let snapshot = await self.evaluate("window.plinkSnapshot && window.plinkSnapshot();")
                if let dict = snapshot as? [String: Any] {
                    let time = dict["time"] as? Double
                    let dur = dict["duration"] as? Double
                    await MainActor.run {
                        if let t = time, t.isFinite { self.position = t }
                        if let d = dur, d > 0 { self.duration = d }
                    }
                }
                let interval: UInt64 = isBackgrounded ? 1_000_000_000 : 250_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    // MARK: - JS evaluation

    @discardableResult
    private func evaluate(_ js: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }

    // MARK: - Validation & HTML

    /// PATCH 03: validate YouTube video ID — only [A-Za-z0-9_-]{11}.
    /// Prevents XSS / injection via HTML interpolation.
    private static func isValidVideoId(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.allSatisfy { c in
            c.isLetter || c.isNumber || c == "_" || c == "-"
        }
    }

    /// PATCH 03: cleaner HTML with plinkPlayer namespace.
    /// - Background matches PlinkRave.void (0x0D001A).
    /// - controls=1, modestbranding=1, rel=0, iv_load_policy=3 (ToS).
    /// - plinkPlay/Pause/Seek/Snapshot helpers exposed on window.
    /// - JSON-encoded videoId (no string interpolation).
    private static func buildHTML(videoIdJSON: String) -> String {
        return """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <style>
              html, body, #player {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                background: #0D001A;
                overflow: hidden;
              }
            </style>
          </head>
          <body>
            <div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
              var ytPlayer;
              function post(event, payload) {
                window.webkit.messageHandlers.plinkPlayer.postMessage(
                  Object.assign({event: event}, payload || {})
                );
              }
              function onYouTubeIframeAPIReady() {
                ytPlayer = new YT.Player('player', {
                  videoId: \(videoIdJSON),
                  playerVars: {
                    'playsinline': 1,
                    'controls': 1,
                    'modestbranding': 1,
                    'rel': 0,
                    'iv_load_policy': 3,
                    'origin': 'https://plink-backend-production-ef31.up.railway.app'
                  },
                  events: {
                    'onReady': function() { post('ready'); },
                    'onStateChange': function(e) { post('state', {state: e.data}); },
                    'onError': function(e) { post('error', {code: e.data}); }
                  }
                });
              }
              // Plink namespace — clean JS bridge for the controller.
              window.plinkPlay = function() {
                if (ytPlayer && ytPlayer.playVideo) { ytPlayer.playVideo(); return true; }
                return false;
              };
              window.plinkPause = function() {
                if (ytPlayer && ytPlayer.pauseVideo) { ytPlayer.pauseVideo(); return true; }
                return false;
              };
              window.plinkSeek = function(seconds) {
                if (ytPlayer && ytPlayer.seekTo) { ytPlayer.seekTo(seconds, true); return true; }
                return false;
              };
              window.plinkSnapshot = function() {
                if (!ytPlayer) { return null; }
                return {
                  time: (ytPlayer.getCurrentTime && ytPlayer.getCurrentTime()) || 0,
                  duration: (ytPlayer.getDuration && ytPlayer.getDuration()) || 0
                };
              };
            </script>
          </body>
        </html>
        """
    }
}

// MARK: - Bridge message handler

private final class EmbeddedMessageHandler: NSObject, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onStateChange: ((Int) -> Void)?
    var onError: ((Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let event = body["event"] as? String
        switch event {
        case "ready":
            onReady?()
        case "state":
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
