// Plink/Playback/NativePlayerController.swift
// AVPlayer-backed PlaybackControlling (runbook §6)
//
// ONE AVPlayer per room session (§1 DoD). Manages:
//   - AVPlayer instance + AVPlayerViewController for PiP
//   - allowsExternalPlayback = true for AirPlay
//   - preferredForwardBufferDuration: 8s for VOD, 2-3s for live
//   - preroll(atRate:) before reveal (avoids visible stutter on rate change)
//   - KVO on timeControlStatus, reasonForWaitingToPlay — surfaced as
//     isBuffering and access/error logs
//   - Periodic time observer for position reporting
//   - All observers are removed in teardown (§19: 'Player observers,
//     NotificationCenter observers, KVO и periodic time observer должны
//     гарантированно сниматься')
//
// NEVER promises zero buffering — startup/rebuffer ratio is measured and
// surfaced as telemetry (Stage 13).

import Foundation
import AVFoundation
import AVKit
import UIKit
import Observation

@MainActor
@Observable
public final class NativePlayerController: PlaybackControlling {
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var capabilities: PlaybackCapabilities = .unknown

    public private(set) var player: AVPlayer?
    public private(set) var pipController: AVPlayerViewController?

    private var provider: ProviderAdapter?
    private var timeControlObservation: NSKeyValueObservation?
    private var reasonObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        teardown()

        // Pick provider by source type.
        let provider: ProviderAdapter
        switch source {
        case .hls, .mp4, .external:
            provider = NativeHLSProvider()
        case .youtube:
            provider = YouTubeEmbeddedProvider()
        }
        self.provider = provider
        self.capabilities = provider.capabilities

        try await provider.prepare(source: source)

        if let item = provider.playerItem {
            let p = AVPlayer(playerItem: item)
            // allowsExternalPlayback = true → AirPlay route button works
            p.usesExternalPlaybackWhileExternalScreenIsActive = true
            p.allowsExternalPlayback = true
            // VOD: 8s forward buffer. Live: 2-3s. Default keeps it simple here.
            item.preferredForwardBufferDuration = 8
            self.player = p

            observe(p, item)
        } else if provider.embeddedView != nil {
            // Embedded (YouTube) — no AVPlayer. Sync via JS bridge.
            // OrderedSyncController will see capabilities.supportsRateCorrection
            // = false and use less frequent precise seeks.
        }
    }

    public func play() async {
        guard let p = player else { return }
        if capabilities.supportsRateCorrection {
            // Preroll at rate 1.0 to avoid visible stutter on first frame.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.preroll(atRate: 1.0) { _ in cont.resume() }
            }
        }
        p.play()
        isPlaying = true
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async {
        guard let p = player else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        if precise {
            p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            p.seek(to: target, toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                   toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
        }
        // AVPlayer.seek is sync but the actual seek completion needs KVO on
        // currentItem.status. For simplicity we yield once.
        await Task.yield()
    }

    public func setRate(_ rate: Float) {
        // Only apply rate changes if the provider supports rate correction.
        // YouTube IFrame API does NOT support setRate for non-PRO content.
        guard capabilities.supportsRateCorrection else { return }
        player?.rate = rate
    }

    public func teardown() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        reasonObservation?.invalidate()
        reasonObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
        pipController = nil
        provider?.teardown()
        provider = nil
        position = 0
        duration = 0
        isPlaying = false
        isBuffering = false
    }

    deinit {
        // KVO observations are tied to NativePlayerController lifetime —
        // they use [weak self] so they're auto-niled. timeObserverToken
        // must be removed explicitly (we did in teardown()).
    }

    // ── KVO / periodic time observer wiring ────────────────────────────────
    private func observe(_ player: AVPlayer, _ item: AVPlayerItem) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                switch p.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                case .waitingToPlay:
                    self.isPlaying = false
                    self.isBuffering = true
                @unknown default:
                    break
                }
            }
        }

        reasonObservation = player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = (p.reasonForWaitingToPlay != .toMinimizeStalling
                                    && p.reasonForWaitingToPlay != .noReason)
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .readyToPlay {
                    self.duration = it.duration.seconds.isFinite ? it.duration.seconds : 0
                }
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.position = time.seconds
            }
        }
    }
}
