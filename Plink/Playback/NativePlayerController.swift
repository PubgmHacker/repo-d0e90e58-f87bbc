// Plink/Playback/NativePlayerController.swift
// AVPlayer-backed PlaybackControlling (runbook §6 + Brain Review 2 P1-14, P1-16, P1-17)
//
// Brain P1-14 fix: seek generation token. Each seek bumps generation; only
// the latest seek's completion is honored. teardown() cancels pending seek.
// cancelPendingPrerolls() called before new seek.
//
// Brain P1-16 fix: NativePlayerController throws immediately for .youtube
// source — impossible state. Use EmbeddedPlaybackController for YouTube.
//
// Brain P1-17 fix: preroll only after prepare() or route change, NOT on
// every play(). Added isPrerolled state.

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

    // P1-14: seek generation token
    private var seekGeneration = 0
    private var pendingSeekTask: Task<Void, Never>?

    // P1-17: preroll state — only preroll after prepare, not every play()
    private var isPrerolled: Bool = false

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        // P1-16: reject .youtube — use EmbeddedPlaybackController instead
        if case .youtube = source {
            throw ProviderError.unsupportedSource
        }

        teardown()

        let provider: ProviderAdapter
        switch source {
        case .hls, .mp4, .external:
            provider = NativeHLSProvider()
        case .youtube:
            throw ProviderError.unsupportedSource  // unreachable
        }
        self.provider = provider
        self.capabilities = provider.capabilities
        self.isPrerolled = false  // P1-17

        try await provider.prepare(source: source)

        if let item = provider.playerItem {
            let p = AVPlayer(playerItem: item)
            p.usesExternalPlaybackWhileExternalScreenIsActive = true
            p.allowsExternalPlayback = true
            item.preferredForwardBufferDuration = 8
            self.player = p
            observe(p, item)
        }
    }

    public func play() async {
        guard let p = player else { return }
        // P1-17: preroll only if not yet prerolled (after prepare or route change)
        if capabilities.supportsRateCorrection && !isPrerolled {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.preroll(atRate: 1.0) { _ in cont.resume() }
            }
            isPrerolled = true
        }
        p.play()
        isPlaying = true
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    // P1-14: seek generation token. Only latest seek's completion honored.
    public func seek(to seconds: TimeInterval, precise: Bool) async {
        guard let p = player else { return }
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

        // P1-14: bump generation, cancel pending prerolls
        seekGeneration += 1
        let generation = seekGeneration
        p.cancelPendingPrerolls()
        pendingSeekTask?.cancel()

        pendingSeekTask = Task { [weak p, weak self] in
            guard let p else { return }
            if Task.isCancelled { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.seek(
                    to: target,
                    toleranceBefore: tolerance,
                    toleranceAfter: tolerance
                ) { _ in cont.resume() }
            }
            // P1-14: only the latest seek's completion is honored
            guard !Task.isCancelled,
                  let self else { return }
            guard generation == self.seekGeneration else { return }
            // Mark prerolled as invalidated — next play() will re-preroll
            self.isPrerolled = false
        }
        await pendingSeekTask?.value
        if generation == seekGeneration {
            pendingSeekTask = nil
        }
    }

    public func setRate(_ rate: Float) {
        guard capabilities.supportsRateCorrection else { return }
        player?.rate = rate
    }

    public func teardown() {
        // P1-14: cancel pending seek on teardown
        seekGeneration += 1
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        player?.cancelPendingPrerolls()

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
        isPrerolled = false
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

    private func recomputeBuffering(player: AVPlayer, item: AVPlayerItem) {
        let controlStatus = player.timeControlStatus
        let bufferEmpty = item.isPlaybackBufferEmpty
        let likelyKeepUp = item.isPlaybackLikelyToKeepUp
        let ready = item.status == .readyToPlay

        let buffering: Bool
        if controlStatus == .waitingToPlay {
            buffering = true
        } else if !ready {
            buffering = true
        } else if bufferEmpty {
            buffering = true
        } else if !likelyKeepUp && controlStatus == .playing {
            buffering = true
        } else {
            buffering = false
        }
        isBuffering = buffering
    }
}
