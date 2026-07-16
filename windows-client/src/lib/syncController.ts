import type { ClockSynchronizer } from './clockSync';
import type { RoomState } from './syncTypes';

export type PlayerSyncAdapter = {
  getPositionSec: () => number;
  getDurationSec: () => number;
  isPlaying: () => boolean;
  play: () => void;
  pause: () => void;
  seek: (sec: number) => void;
};

export class OrderedSyncController {
  lastEpoch = 0;
  lastSeq = 0;
  hasAppliedAnyState = false;
  lastDriftMs = 0;

  private clock: ClockSynchronizer;
  private player: PlayerSyncAdapter;

  constructor(clock: ClockSynchronizer, player: PlayerSyncAdapter) {
    this.clock = clock;
    this.player = player;
  }

  apply(state: RoomState) {
    if (this.hasAppliedAnyState) {
      if (state.epoch < this.lastEpoch) return;
      if (state.epoch === this.lastEpoch && state.seq <= this.lastSeq) return;
    }
    this.lastEpoch = state.epoch;
    this.lastSeq = state.seq;
    this.hasAppliedAnyState = true;

    const serverNow = this.clock.isSynchronized ? this.clock.serverNowMs : Date.now();
    const waitMs = state.effectiveAtServerMs - serverNow;
    const run = () => this.applyTransition(state);
    if (waitMs > 0) {
      window.setTimeout(run, Math.min(waitMs, 2000));
    } else {
      run();
    }
  }

  private applyTransition(state: RoomState) {
    const serverNow = this.clock.isSynchronized ? this.clock.serverNowMs : Date.now();
    const elapsed = state.playing
      ? Math.max(0, serverNow - state.effectiveAtServerMs) / 1000
      : 0;
    const target = state.positionMs / 1000 + elapsed;
    const driftMs = (target - this.player.getPositionSec()) * 1000;
    this.lastDriftMs = driftMs;

    const playingMismatch = state.playing !== this.player.isPlaying();
    if (playingMismatch || Math.abs(driftMs) >= 750) {
      this.player.seek(target);
      if (state.playing) this.player.play();
      else this.player.pause();
      return;
    }

    if (Math.abs(driftMs) >= 120) {
      this.player.seek(target);
    }
  }
}