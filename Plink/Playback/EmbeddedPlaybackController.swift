// Plink/Playback/EmbeddedPlaybackController.swift — PATCH 03 (Brain Phase 2)
//
// The single official YouTube embedded controller for the room session.
// Owns one WKWebView per room (runbook §16: 'Не добавлять еще один
// singleton WebView' — coordinator is per-room, never global).
//
// Brain Phase 2 changes:
//   - YouTube owns play/pause/timeline/captions/quality (official controls visible).
//   - Plink owns room close/sync/participants/chat/reactions/replace-video only.
//   - NO loadHTMLString — navigate WKWebView to backend /api/media/youtube-player
//     so the page has a real HTTPS origin (fixes error 153).
//   - NO duplicate Plink transport UI on YouTube content (PlayerControlLayer
//     only renders for .plink chrome ownership).
//   - NO invented error 152 — official mapping only: 2/5/100/101/150/153.
//
// JS bridge contract (YouTube IFrame API):
//   - 'ready' → isReady = true, drain pending commands.
//   - 'state' (1/2/3/0) → isPlaying, isBuffering.
//   - 'error' (2/5/100/101/150/153) → lastError set, isBuffering cleared.
//   - poll task: plinkSnapshot() every 250ms (visible) / 1s (background).
//
// App Store compliance (runbook §7 + Brain Phase 1.2):
//   - Official YouTube IFrame API served from Plink backend (real HTTPS origin).
//   - NO server-side extraction (no Innertube, no yt-dlp, no Piped).
//   - NO cookie relay — cookies never leave the device.
//   - NO raw CDN proxy.
//   - YouTube controls VISIBLE (controls=1) — Plink does NOT duplicate them.

import Foundation
import UIKit
import WebKit
import Observation

/// Brain Phase 2: determines who owns transport UI.
/// `.provider` (YouTube) → hide Plink's PlayerControlLayer.
/// `.plink` (native HLS/MP4) → render PlayerControlLayer.
public enum PlayerChromeOwnership: Sendable {
    case provider
    case plink
}

@MainActor
@Observable
public final class EmbeddedPlaybackController: PlaybackControlling {
    // MARK: - Public state (UI binds to these)

    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false

    /// ready state — UI uses this to show "Loading…" vs "Buffering…".
    public private(set) var isReady: Bool = false

    /// surface YouTube error callback for UI binding.
    public private(set) var lastError: String?

    /// Brain Phase 2: YouTube owns transport controls — Plink does NOT
    /// render its own PlayerControlLayer on this content.
    public var chromeOwnership: PlayerChromeOwnership { .provider }

    /// Fired when the *user* (or YouTube chrome) changes play/pause/seek —
    /// not when Plink programmatically applies remote sync commands.
    /// Host WatchRoomModel uses this to emit `sync.command`.
    public var onUserPlaybackChange: ((Bool, Double) -> Void)?

    /// Suppress host broadcast while applying remote sync or host Plink commands.
    private var suppressUserBroadcastDepth: Int = 0
    private var lastBroadcastPlaying: Bool?
    private var lastBroadcastPosition: Double = 0

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

    /// Pending enum consolidates pending seek + play state.
    /// Drained atomically when isReady becomes true.
    private var pending: Pending = .none
    private enum Pending {
        case none
        case state(position: Double?, playing: Bool?)

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

    /// Brain Phase 2: backend HTTPS wrapper URL.
    /// Set via prepare(_:) — the wrapper page lives at /api/media/youtube-player.
    private static let backendBaseURL = URL(string: "https://plink-backend-production-ef31.up.railway.app")!

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
        // nonPersistent data store to prevent stale HTML cache.
        config.websiteDataStore = .nonPersistent()

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x0E/255, green: 0x10/255, blue: 0x16/255, alpha: 1)
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

        // Brain Phase 2: navigate to backend HTTPS wrapper (NO loadHTMLString).
        // The wrapper at /api/media/youtube-player?id=VIDEO_ID serves a static
        // HTML page with a real Plink HTTPS origin. This:
        //   - gives the page a real origin (fixes YouTube error 153)
        //   - allows the strict CSP to be enforced by the backend
        //   - prevents YouTube bot-detection (we're not loading youtube.com/embed/)
        //   - keeps YouTube controls visible (controls=1)
        var components = URLComponents(url: Self.backendBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/media/youtube-player"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let wrapperURL = components.url else {
            throw ProviderError.loadingFailed("Invalid wrapper URL")
        }
        web.load(URLRequest(url: wrapperURL))

        // Wait for player ready:
        //   A) bridge event "ready" → handleReady() sets isReady
        //   B) JS fallback: window.__plinkIsReady() (backend v21+)
        // Timeout 20s — IFrame API + first frame can be slow on cellular.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                var ticks = 0
                while true {
                    let ready = await MainActor.run { self.isReady }
                    if ready { return }

                    // Every ~400ms probe JS readiness in case webkit postMessage
                    // was dropped or an older wrapper lacked the iOS bridge shape.
                    ticks += 1
                    if ticks % 5 == 0 {
                        let jsReady = await self.evaluate(
                            "(function(){try{return !!(window.__plinkIsReady&&window.__plinkIsReady());}catch(e){return false;}})()"
                        )
                        if let flag = jsReady as? Bool, flag {
                            await MainActor.run { self.handleReady() }
                            return
                        }
                        // Ensure control helpers exist even on older wrapper HTML
                        _ = await self.evaluate("""
                        (function(){
                          if (typeof window.plinkPlay !== 'function' && typeof window.plinkCmd === 'function') {
                            window.plinkPlay = function(){ window.plinkCmd('play'); return true; };
                            window.plinkPause = function(){ window.plinkCmd('pause'); return true; };
                            window.plinkSeek = function(s){ window.plinkCmd('seek',{seconds:s}); return true; };
                            window.plinkSnapshot = function(){ return {time:0,duration:0}; };
                          }
                          return true;
                        })()
                        """)
                    }

                    try await Task.sleep(for: .milliseconds(80))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw ProviderError.loadingFailed("Таймаут YouTube-плеера — проверьте сеть")
            }
            _ = try await group.next()
            group.cancelAll()
        }

        startPolling()
    }

    // MARK: - PlaybackControlling

    public func play() async {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
        guard isReady else {
            pending = pending.merging(position: nil, playing: true)
            return
        }
        await evaluate("window.plinkPlay && window.plinkPlay();")
    }

    public func pause() {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
        guard isReady else {
            pending = pending.merging(position: nil, playing: false)
            return
        }
        Task { await evaluate("window.plinkPause && window.plinkPause();") }
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        beginSuppressUserBroadcast()
        defer { endSuppressUserBroadcast() }
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

    private func beginSuppressUserBroadcast() {
        suppressUserBroadcastDepth += 1
    }

    private func endSuppressUserBroadcast() {
        // Keep suppress briefly so IFrame state callbacks from our own JS don't re-broadcast.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            suppressUserBroadcastDepth = max(0, suppressUserBroadcastDepth - 1)
        }
    }

    private func emitUserPlaybackChangeIfNeeded(playing: Bool, position pos: Double, force: Bool = false) {
        guard suppressUserBroadcastDepth == 0 else { return }
        let playingChanged = lastBroadcastPlaying.map { $0 != playing } ?? true
        let seekJump = abs(pos - lastBroadcastPosition) > 1.25
        guard force || playingChanged || seekJump else { return }
        lastBroadcastPlaying = playing
        lastBroadcastPosition = pos
        onUserPlaybackChange?(playing, pos)
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
        let previousPlaying = isPlaying
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
        // Host multi-device: YouTube chrome play/pause → sync.command
        if previousPlaying != isPlaying, state == 1 || state == 2 || state == 0 {
            emitUserPlaybackChangeIfNeeded(playing: isPlaying, position: position, force: true)
        }
    }

    private func handleError(code: Int) {
        // Brain §5.1: map official YouTube IFrame API error codes.
        // https://developers.google.com/youtube/iframe_api_reference#onError
        let message: String
        switch code {
        case 2:             message = "Invalid video parameter"
        case 5:             message = "HTML5 player error"
        case 100:           message = "Video not found or private"
        case 101, 150:      message = "This video cannot be embedded in Plink"
        case 153:           message = "Missing client identity — try another video"
        default:            message = "YouTube error \(code) — try another video"
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
                        let prev = self.position
                        if let t = time, t.isFinite {
                            self.position = t
                            // Large jump while not suppressed → user seek on YouTube chrome
                            if abs(t - prev) > 1.5 {
                                self.emitUserPlaybackChangeIfNeeded(
                                    playing: self.isPlaying,
                                    position: t,
                                    force: true
                                )
                            }
                        }
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

    // MARK: - Validation

    /// Validate YouTube video ID — only [A-Za-z0-9_-]{11}.
    /// Prevents XSS / injection via URL parameter.
    private static func isValidVideoId(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.allSatisfy { c in
            c.isLetter || c.isNumber || c == "_" || c == "-"
        }
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
