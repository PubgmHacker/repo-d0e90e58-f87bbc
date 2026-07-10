// Plink/Playback/NativePlayerController.swift
// AVPlayer-backed PlaybackControlling (runbook §6 + Brain Review P0-6, P0-7)
//
// Brain P0-6 fix: seek() awaits completion via withCheckedContinuation.
//   AVPlayer.seek(to:toleranceBefore:toleranceAfter:completionHandler:) is
//   the only reliable signal that the seek finished. Task.yield() does NOT
//   wait for seek completion. OrderedSyncController may not call play() or
//   declare correction complete until the seek has actually repositioned.
//   Also: clamp non-finite/negative values, serialize overlapping seeks.
//
// Brain P0-7 fix: buffering state derived correctly.
//   timeControlStatus == .waitingToPlayAtSpecifiedRate is the PRIMARY
//   signal of buffering. reasonForWaitingToPlay == .toMinimizeStalling is
//   a TYPICAL buffering reason, NOT a 'not buffering' signal. Derive
//   isBuffering from timeControlStatus + item.isPlaybackLikelyToKeepUp +
//   item.status == .readyToPlay.
//
// ONE AVPlayer per room session (§1 DoD). All observers removed in
// teardown() (§19).

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
    private var likelyKeepUpObservation: NSKeyValueObservation?
    private var isPlaybackBufferEmptyObservation: NSKeyValueObservation?

    // P0-6: serialize overlapping seeks
    private var pendingSeekTask: Task<Void, Never>?

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        teardown()

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
            p.usesExternalPlaybackWhileExternalScreenIsActive = true
            p.allowsExternalPlayback = true
            item.preferredForwardBufferDuration = 8
            self.player = p
            observe(p, item)
        } else if provider.embeddedView != nil {
            // Embedded (YouTube) — sync via JS bridge. NativePlayerController
            // is NOT the right controller for embedded; PlaybackCoordinator
            // should use EmbeddedPlaybackController instead (P0-8).
        }
    }

    public func play() async {
        guard let p = player else { return }
        if capabilities.supportsRateCorrection {
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

    // P0-6: await AVPlayer.seek completion via withCheckedContinuation.
    // Clamp non-finite/negative. Serialize overlapping seeks.
    public func seek(to seconds: TimeInterval, precise: Bool) async {
        guard let p = player else { return }
        // Clamp
        let clamped: Double
        if seconds.isNaN || seconds.isInfinite || seconds < 0 {
            clamped = 0
        } else if duration > 0 && seconds > duration {
            clamped = duration
        } else {
            clamped = seconds
        }
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance: CMTime
        if precise {
            tolerance = .zero
        } else {
            tolerance = CMTime(seconds: 0.15, preferredTimescale: 600)
        }

        // Cancel any pending seek — last-write-wins
        pendingSeekTask?.cancel()
        pendingSeekTask = Task { [weak p] in
            guard let p else { return }
            if Task.isCancelled { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.seek(
                    to: target,
                    toleranceBefore: tolerance,
                    toleranceAfter: tolerance
                ) { _ in cont.resume() }
            }
        }
        // Await the task so callers know seek is done before next op
        await pendingSeekTask?.value
        pendingSeekTask = nil
    }

    public func setRate(_ rate: Float) {
        guard capabilities.supportsRateCorrection else { return }
        player?.rate = rate
    }

    public func teardown() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        for obs in [timeControlObservation, reasonObservation, statusObservation, likelyKeepUpObservation, isPlaybackBufferEmptyObservation] {
            obs?.invalidate()
        }
        timeControlObservation = nil
        reasonObservation = nil
        statusObservation = nil
        likelyKeepUpObservation = nil
        isPlaybackBufferEmptyObservation = nil
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

    // ── KVO / periodic time observer wiring ────────────────────────────────
    private func observe(_ player: AVPlayer, _ item: AVPlayerItem) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: p, item: item)
                switch p.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                case .paused:
                    self.isPlaying = false
                case .waitingToPlay:
                    self.isPlaying = false
                @unknown default:
                    break
                }
            }
        }

        // P0-7: reasonForWaitingToPlay is informational; do NOT use it to
        // override isBuffering=false. Just log it for diagnostics.
        reasonObservation = player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: p, item: item)
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .readyToPlay {
                    self.duration = it.duration.seconds.isFinite ? it.duration.seconds : 0
                }
                self.recomputeBuffering(player: player, item: it)
            }
        }

        // P0-7: also observe playback buffer indicators for accurate state
        likelyKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: player, item: it)
            }
        }
        isPlaybackBufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: player, item: it)
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.position = time.seconds
            }
        }
    }

    // P0-7: derive isBuffering from timeControlStatus + isPlaybackLikelyToKeepUp
    // + isPlaybackBufferEmpty + item.status.
    private func recomputeBuffering(player: AVPlayer, item: AVPlayerItem) {
        let controlStatus = player.timeControlStatus
        let bufferEmpty = item.isPlaybackBufferEmpty
        let likelyKeepUp = item.isPlaybackLikelyToKeepUp
        let ready = item.status == .readyToPlay

        // Buffering iff:
        //   - waitingToPlay (AVPlayer is waiting for media data), OR
        //   - playback buffer empty, OR
        //   - not likely to keep up
        // BUT only if item is .readyToPlay — otherwise we're still loading
        // the asset, which is a separate 'preparing' state we surface as
        // isBuffering=true.
        let buffering: Bool
        if controlStatus == .waitingToPlay {
            buffering = true
        } else if !ready {
            buffering = true
        } else if bufferEmpty {
            buffering = true
        } else if !likelyKeepUp && controlStatus == .playing {
            // Playing but barely keeping up — keep buffering flag on so UI
            // shows a spinner.
            buffering = true
        } else {
            buffering = false
        }
        isBuffering = buffering
    }
}
