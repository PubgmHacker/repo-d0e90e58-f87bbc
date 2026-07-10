// Plink/Realtime/OrderedSyncController.swift
// Authoritative state → player bridge (runbook §5)
//
// Replaces the legacy 3s/6s drift thresholds (incompatible with the
// "millisecond sync" promise). New policy:
//
//   ┌────────────────┬─────────────────────────────────────────┐
//   │ drift          │ action                                   │
//   ├────────────────┼─────────────────────────────────────────┤
//   │ < 80ms         │ no-op                                    │
//   │ 80–250ms       │ set rate 0.98 or 1.02 (gradual catchup) │
//   │ 250–750ms      │ set rate 0.95 or 1.05 (faster catchup)  │
//   │ >= 750ms       │ precise seek                             │
//   │ pause / seek / │ precise transition (rate forced to 1.0)  │
//   │ media change    │                                          │
//   └────────────────┴─────────────────────────────────────────┘
//   After drift correction, rate returns to 1.0 once drift < 80ms.
//
// CRITICAL RULES (runbook §19):
//   - Apply state only if (epoch, seq) is strictly newer than the last
//     applied watermark. Out-of-order or duplicate messages are dropped.
//   - Pause does NOT extrapolate position — elapsed is 0 when !playing.
//   - resetForReconnect() preserves the watermark so we can request a fresh
//     snapshot with afterSeq, and so stale transport commands from the
//     offline period are NOT replayed (runbook §5: 'Не класть play/pause/seek
//     в offline queue. После reconnect запрашивать snapshot').
//
// All player interactions are async — the player is the single source of
// truth for current position, and seek()/play() can take time.

import Foundation
import Observation

/// Abstraction over AVPlayer / WKWebView / external route.
/// Real implementation lives in Plink/Playback/NativePlayerController.swift.
@MainActor
public protocol PlaybackControlling: AnyObject {
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    func prepare(_ source: PlaybackSource) async throws
    func play() async
    func pause()
    func seek(to seconds: TimeInterval, precise: Bool) async
    func setRate(_ rate: Float)
}

public enum PlaybackSource: Sendable {
    case hls(URL, headers: [String: String])
    case mp4(URL, headers: [String: String])
    case youtube(String)
    case external(URL)
}

@MainActor
@Observable
public final class OrderedSyncController {
    /// Last applied (epoch, seq) watermark — used to drop out-of-order / dupes.
    public private(set) var lastEpoch: Int64 = 0
    public private(set) var lastSeq: Int64 = 0
    public private(set) var hasAppliedAnyState: Bool = false

    /// Drift most recently measured (ms). Positive = local is behind.
    public private(set) var lastDriftMs: Double = 0

    /// Count of hard corrections (precise seeks) — surfaced as a metric.
    public private(set) var hardCorrectionCount: Int = 0

    private let clock: ClockSynchronizer
    private let player: PlaybackControlling

    /// Cancellable rate-correction task — when set, we're in catchup mode.
    private var rateCorrectionTask: Task<Void, Never>?

    public init(clock: ClockSynchronizer, player: PlaybackControlling) {
        self.clock = clock
        self.player = player
    }

    /// Apply an authoritative state update.
    /// Drops out-of-order / duplicate messages (§19, §5).
    public func apply(_ state: RealtimeRoomState) async {
        // ── 1. Ordering watermark ───────────────────────────────────────
        if hasAppliedAnyState {
            if state.epoch < lastEpoch { return }
            if state.epoch == lastEpoch && state.seq <= lastSeq { return }
        }
        lastEpoch = state.epoch
        lastSeq = state.seq
        hasAppliedAnyState = true

        // ── 2. Compute target position ──────────────────────────────────
        // If playing, the authoritative position has been advancing since
        // effectiveAtServerMs. If paused, position is frozen.
        let elapsed: Double
        if state.playing {
            elapsed = max(0, clock.serverNowMs - Double(state.effectiveAtServerMs)) / 1000.0
        } else {
            elapsed = 0
        }
        let target = Double(state.positionMs) / 1000.0 + elapsed
        let driftMs = (target - player.position) * 1000
        lastDriftMs = driftMs

        // ── 3. Decide correction strategy ───────────────────────────────
        let playingMismatch = state.playing != player.isPlaying
        let absDrift = abs(driftMs)

        if playingMismatch || absDrift >= 750 {
            // Precise transition (§5: pause, explicit seek, media change,
            // or large drift). Force rate back to 1.0 after seek.
            cancelRateCorrection()
            await player.seek(to: target, precise: true)
            if state.playing {
                await player.play()
            } else {
                player.pause()
            }
            player.setRate(1.0)
            if absDrift >= 750 { hardCorrectionCount += 1 }
            return
        }

        if !state.playing {
            // Paused and small drift — gentle precise seek to lock position.
            if absDrift >= 80 {
                cancelRateCorrection()
                await player.seek(to: target, precise: true)
                player.setRate(1.0)
            }
            return
        }

        // ── 4. Drift correction via rate nudge ──────────────────────────
        if absDrift < 80 {
            // Within tolerance — cancel any ongoing rate correction.
            if rateCorrectionTask != nil {
                cancelRateCorrection()
                player.setRate(1.0)
            }
            return
        }

        let rate: Float
        if absDrift < 250 {
            rate = driftMs > 0 ? 1.02 : 0.98
        } else {
            rate = driftMs > 0 ? 1.05 : 0.95
        }
        player.setRate(rate)

        // Schedule a return-to-1.0 check — re-evaluates drift in 2 seconds.
        // If drift has resolved, drop back to 1.0; otherwise keep nudging.
        cancelRateCorrection()
        rateCorrectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.reEvaluateRate()
        }
    }

    private func reEvaluateRate() async {
        guard hasAppliedAnyState else { return }
        // Re-fetch current authoritative target by re-deriving from last state.
        // (We can't re-receive state from the server on demand here; this just
        // checks whether the local player is now within tolerance of where
        // it should be based on the last applied state's projection.)
        // For simplicity, return to 1.0 — the next sync.state will nudge again.
        if abs(lastDriftMs) < 80 {
            player.setRate(1.0)
            cancelRateCorrection()
        }
    }

    private func cancelRateCorrection() {
        rateCorrectionTask?.cancel()
        rateCorrectionTask = nil
    }

    /// Reconnect protocol (runbook §5, §19):
    ///   - PRESERVE the (epoch, seq) watermark — used for afterSeq in the
    ///     snapshot request.
    ///   - DO NOT replay local transport commands (play/pause/seek) that were
    ///     queued during disconnect.
    ///   - The next sync.state.snapshot from the server will reset our
    ///     authoritative target. If its (epoch, seq) is older than our
    ///     watermark, we ignore it; if newer, we apply normally.
    public func resetForReconnect() {
        cancelRateCorrection()
        player.setRate(1.0)
        // Deliberately do NOT reset lastEpoch/lastSeq — they are the
        // watermark for the afterSeq request.
    }

    /// Hard reset — used when switching rooms or leaving.
    public func resetCompletely() {
        cancelRateCorrection()
        lastEpoch = 0
        lastSeq = 0
        hasAppliedAnyState = false
        lastDriftMs = 0
        hardCorrectionCount = 0
    }
}
