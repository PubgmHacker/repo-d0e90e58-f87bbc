# Sync drift lab results (production)

**Date:** 2026-07-15  
**Script:** `scripts/drift-lab.mjs`  
**API:** `https://plink-backend-production-ef31.up.railway.app`  
**Setup:** 1 host + 2 synthetic viewers, 10 sync.command runs  

## Results (latest PASS)

| Metric | Value | Target |
|--------|-------|--------|
| Samples received | 20/20 | 100% |
| Median lag | **~286–311 ms** | <500 ms |
| p95 lag | **~303–347 ms** | <1500 ms |
| Max lag | **~303–347 ms** | <2000 ms |
| **Verdict** | **PASS** | ±2s marketing claim supported for WS path |

## How to reproduce

```bash
cd Desktop/Grok
npm install
npm run drift-lab
# or: VIEWERS=2 RUNS=20 node scripts/drift-lab.mjs
```

## Notes

- Measures **WebSocket sync.state lag** after host `sync.command` (not video frame decode).
- Real device A/V drift may add buffer underrun; UI shows drift ms on Desktop/Android.
- Cross-platform player apply path: iOS EmbeddedPlaybackController · Desktop postMessage · Android `window.plinkCmd`.
