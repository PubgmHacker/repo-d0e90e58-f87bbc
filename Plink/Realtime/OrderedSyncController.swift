// Plink/Realtime/OrderedSyncController.swift
// Authoritative state → player bridge (runbook §5 + Brain Review P1-1, P1-2)
//
// Brain P1-1 fix: rate correction returns to 1.0 reliably.
//   - Store the LAST applied authoritative state — recompute drift from
//     current player position vs projected target on each re-evaluation.
//   - Respect state.rate (use it as the base rate, not always 1.0).
//   - After correction window (2s), if drift < 80ms → setRate(state.rate).
//   - If drift still > 80ms after window → continue nudging but increment
//     a counter; after 3 windows, fall back to precise seek.
//
// Brain P1-2 fix: effectiveAt transition.
//   - Server sets effectiveAtServerMs = now + 80ms (slightly in the future).
//   - Client computes elapsed = max(0, serverNow - effectiveAt). If
//     effectiveAt is in the future, elapsed is 0 — but the client must NOT
//     apply play/pause/seek until the effectiveAt deadline arrives.
//   - We schedule a Task that sleeps until effectiveAtServerMs (converted
//     to local time via clock.offsetMs) before applying the transition.
//   - For non-transition states (drift correction only), no wait — we
//     apply immediately because the player is already playing.
//
// All player interactions are async — the player is the single source of
// truth for current position.

import Foundation
import Observation

// P1-18: ContinuousClock for monotonic waits (immune to system clock changes).
// ClockSynchronizer still uses wall clock for server epoch mapping, but local
// duration waits use ContinuousClock.

@MainActor
@Observable
public final class OrderedSyncController {
    // Watermark — drops out-of-order / duplicate messages.
    public private(set) var lastEpoch: Int64 = 0
    public private(set) var lastSeq: Int64 = 0
    public private(set) var hasAppliedAnyState: Bool = false

    public private(set) var lastDriftMs: Double = 0
    public private(set) var hardCorrectionCount: Int = 0

    private let clock: ClockSynchronizer
    private let player: PlaybackControlling

    // P1-1: store last applied state for re-evaluation
    private var lastAppliedState: RealtimeRoomState?
    private var rateCorrectionTask: Task<Void, Never>?
    private var effectiveAtWaitTask: Task<Void, Never>?
    private var correctionWindowCount = 0

    public init(clock: ClockSynchronizer, player: PlaybackControlling) {
        self.clock = clock
        self.player = player
    }

    public func apply(_ state: RealtimeRoomState) async {
        // ── 1. Ordering watermark ───────────────────────────────────────
        if hasAppliedAnyState {
            if state.epoch < lastEpoch { return }
            if state.epoch == lastEpoch && state.seq <= lastSeq { return }
        }
        lastEpoch = state.epoch
        lastSeq = state.seq
        hasAppliedAnyState = true
        lastAppliedState = state

        // ── 2. P1-2: wait for effectiveAt deadline if it's in the future ──
        // The server sets effectiveAtServerMs = now + 80ms so all clients
        // apply the transition at the same wall-clock moment. We must NOT
        // apply play/pause/seek before that moment.
        // P1-18: use ContinuousClock for monotonic wait (immune to system clock changes).
        let serverNow = clock.serverNowMs
        let waitMs = Double(state.effectiveAtServerMs) - serverNow
        if waitMs > 0 {
            effectiveAtWaitTask?.cancel()
            effectiveAtWaitTask = Task { [weak self] in
                let clock = ContinuousClock()
                let duration = Duration.milliseconds(Int64(waitMs))
                try? await clock.sleep(for: duration)
                if !Task.isCancelled {
                    await self?.applyTransition(state)
                }
            }
            await effectiveAtWaitTask?.value
            effectiveAtWaitTask = nil
        } else {
            await applyTransition(state)
        }
    }

    private func applyTransition(_ state: RealtimeRoomState) async {
        // ── 3. Compute target position ──────────────────────────────────
        let elapsed: Double
        if state.playing {
            elapsed = max(0, clock.serverNowMs - Double(state.effectiveAtServerMs)) / 1000.0
        } else {
            elapsed = 0  // §19: pause does NOT extrapolate
        }
        let target = Double(state.positionMs) / 1000.0 + elapsed
        let driftMs = (target - player.position) * 1000
        lastDriftMs = driftMs

        // ── 4. Decide correction strategy ───────────────────────────────
        let playingMismatch = state.playing != player.isPlaying
        let absDrift = abs(driftMs)

        if playingMismatch || absDrift >= 750 {
            cancelRateCorrection()
            await player.seek(to: target, precise: true)
            if state.playing {
                await player.play()
            } else {
                player.pause()
            }
            // P1-1: return to state.rate (not always 1.0)
            player.setRate(Float(state.rate))
            if absDrift >= 750 { hardCorrectionCount += 1 }
            correctionWindowCount = 0
            return
        }

        if !state.playing {
            if absDrift >= 80 {
                cancelRateCorrection()
                await player.seek(to: target, precise: true)
                player.setRate(Float(state.rate))
            }
            return
        }

        // ── 5. Drift correction via rate nudge ──────────────────────────
        if absDrift < 80 {
            if rateCorrectionTask != nil {
                cancelRateCorrection()
                player.setRate(Float(state.rate))
            }
            return
        }

        // P1-1: base rate is state.rate, not always 1.0
        let baseRate = Float(state.rate)
        let rate: Float
        if absDrift < 250 {
            rate = driftMs > 0 ? baseRate * 1.02 : baseRate * 0.98
        } else {
            rate = driftMs > 0 ? baseRate * 1.05 : baseRate * 0.95
        }
        player.setRate(rate)

        cancelRateCorrection()
        correctionWindowCount += 1
        rateCorrectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.reEvaluateRate()
        }
    }

    // P1-1: recompute drift from CURRENT player position vs projected
    // target. If drift < 80ms → reset to state.rate. If 3 correction
    // windows have passed without convergence → fall back to precise seek.
    private func reEvaluateRate() async {
        guard let state = lastAppliedState, hasAppliedAnyState else { return }
        let elapsed: Double
        if state.playing {
            elapsed = max(0, clock.serverNowMs - Double(state.effectiveAtServerMs)) / 1000.0
        } else {
            elapsed = 0
        }
        let target = Double(state.positionMs) / 1000.0 + elapsed
        let driftMs = (target - player.position) * 1000
        lastDriftMs = driftMs
        let absDrift = abs(driftMs)
        let baseRate = Float(state.rate)

        if absDrift < 80 {
            player.setRate(baseRate)
            cancelRateCorrection()
            correctionWindowCount = 0
            return
        }
        if correctionWindowCount >= 3 {
            // Give up on rate nudge — precise seek
            cancelRateCorrection()
            await player.seek(to: target, precise: true)
            player.setRate(baseRate)
            hardCorrectionCount += 1
            correctionWindowCount = 0
            return
        }
        // Continue nudging with recomputed rate
        let rate: Float
        if absDrift < 250 {
            rate = driftMs > 0 ? baseRate * 1.02 : baseRate * 0.98
        } else {
            rate = driftMs > 0 ? baseRate * 1.05 : baseRate * 0.95
        }
        player.setRate(rate)
        rateCorrectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.reEvaluateRate()
        }
    }

    private func cancelRateCorrection() {
        rateCorrectionTask?.cancel()
        rateCorrectionTask = nil
    }

    public func resetForReconnect() {
        cancelRateCorrection()
        effectiveAtWaitTask?.cancel()
        effectiveAtWaitTask = nil
        if let state = lastAppliedState {
            player.setRate(Float(state.rate))
        } else {
            player.setRate(1.0)
        }
        // P1-8: preserve watermark — used as afterSeq in snapshot request.
        // Do NOT reset lastEpoch/lastSeq.
    }

    public func resetCompletely() {
        cancelRateCorrection()
        effectiveAtWaitTask?.cancel()
        effectiveAtWaitTask = nil
        lastEpoch = 0
        lastSeq = 0
        hasAppliedAnyState = false
        lastAppliedState = nil
        lastDriftMs = 0
        hardCorrectionCount = 0
        correctionWindowCount = 0
    }
}
