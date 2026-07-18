type Sample = { rttMs: number; offsetMs: number };

export class ClockSynchronizer {
  private samples: Sample[] = [];
  private static readonly maxSamples = 20;
  private static readonly topN = 5;

  offsetMs = 0;
  rttMs = 0;
  probeCount = 0;

  get isSynchronized() {
    return this.probeCount >= 3;
  }

  ingest(clientSentMs: number, serverMs: number, clientReceivedMs: number) {
    const rtt = Math.max(0, clientReceivedMs - clientSentMs);
    const midpoint = clientSentMs + rtt / 2;
    const offset = serverMs - midpoint;

    this.samples.push({ rttMs: rtt, offsetMs: offset });
    if (this.samples.length > ClockSynchronizer.maxSamples) {
      this.samples = this.samples.slice(-ClockSynchronizer.maxSamples);
    }
    this.probeCount += 1;

    const best = [...this.samples].sort((a, b) => a.rttMs - b.rttMs).slice(0, ClockSynchronizer.topN);
    const offsets = best.map((s) => s.offsetMs).sort((a, b) => a - b);
    if (!offsets.length) return;
    this.offsetMs = offsets[Math.floor(offsets.length / 2)]!;
    this.rttMs = best.reduce((sum, s) => sum + s.rttMs, 0) / best.length;
  }

  reset() {
    this.samples = [];
    this.offsetMs = 0;
    this.rttMs = 0;
    this.probeCount = 0;
  }

  get serverNowMs() {
    return Date.now() + this.offsetMs;
  }
}