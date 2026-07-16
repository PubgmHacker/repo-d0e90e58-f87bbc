package com.plink.app.data.sync

import android.os.Handler
import android.os.Looper

data class RoomPlaybackState(
    val protocolVersion: Int = 2,
    val roomId: String,
    val epoch: Int,
    val seq: Int,
    val mediaId: String?,
    val positionMs: Long,
    val playing: Boolean,
    val rate: Double,
    val effectiveAtServerMs: Long,
    val issuedBy: String,
)

interface PlayerSyncAdapter {
    fun getPositionSec(): Double
    fun getDurationSec(): Double
    fun isPlaying(): Boolean
    fun play()
    fun pause()
    fun seek(sec: Double)
}

class OrderedSyncController(
    private val clock: ClockSynchronizer,
    private val player: PlayerSyncAdapter,
) {
    var lastEpoch = 0
        private set
    var lastSeq = 0
        private set
    var hasAppliedAnyState = false
        private set
    var lastDriftMs = 0.0
        private set

    private val mainHandler = Handler(Looper.getMainLooper())

    fun apply(state: RoomPlaybackState) {
        if (hasAppliedAnyState) {
            if (state.epoch < lastEpoch) return
            if (state.epoch == lastEpoch && state.seq <= lastSeq) return
        }
        lastEpoch = state.epoch
        lastSeq = state.seq
        hasAppliedAnyState = true

        val serverNow = if (clock.isSynchronized) clock.serverNowMs else System.currentTimeMillis()
        val waitMs = state.effectiveAtServerMs - serverNow
        val run = Runnable { applyTransition(state) }
        if (waitMs > 0) {
            mainHandler.postDelayed(run, waitMs.coerceAtMost(2000))
        } else {
            mainHandler.post(run)
        }
    }

    private fun applyTransition(state: RoomPlaybackState) {
        val serverNow = if (clock.isSynchronized) clock.serverNowMs else System.currentTimeMillis()
        val elapsed = if (state.playing) {
            ((serverNow - state.effectiveAtServerMs).coerceAtLeast(0)) / 1000.0
        } else {
            0.0
        }
        val target = state.positionMs / 1000.0 + elapsed
        val driftMs = (target - player.getPositionSec()) * 1000.0
        lastDriftMs = driftMs

        val playingMismatch = state.playing != player.isPlaying()
        if (playingMismatch || kotlin.math.abs(driftMs) >= 750) {
            player.seek(target)
            if (state.playing) player.play() else player.pause()
            return
        }
        if (kotlin.math.abs(driftMs) >= 120) {
            player.seek(target)
        }
    }
}
