# Plink MVP Status — FINAL (16 July 2026)

## Verdict: **Closed-beta MVP READY**

Core loop (auth → room → YouTube → chat → sync) works on **iOS + Android + Mac Desktop + Backend**.

| Platform | Auth | Room | Chat | YouTube | Sync | Build |
|----------|------|------|------|---------|------|-------|
| iOS | ✅ | ✅ | ✅ | ✅ | ✅ | IPA / Xcode |
| Android | ✅ | ✅ | ✅ | ✅ bridge | ✅ | APK |
| Mac Desktop | ✅ | ✅ | ✅ | ✅ | ✅ | **DMG rebuilt** |
| Windows | ✅ code | ✅ | ✅ | ✅ | ✅ | CI workflow triggered |
| Backend | ✅ | ✅ | ✅ | ✅ | ✅ v2 | Railway live |

## Drift lab (production)

```
node scripts/drift-lab.mjs
samples: 20/20
median lag: 286 ms
p95 lag:    303 ms
→ PASS (median <500ms, p95 <1.5s)
```

## Completed this sprint

- [x] YouTube 153 fix (hosted player + Android local bridge)
- [x] Desktop + Android playback sync (protocol v2)
- [x] Mac DMG rebuild → `plink-landing/public/downloads/Plink.dmg`
- [x] Android APK with sync
- [x] Empty JSON body leave-room fix
- [x] Desktop AI chat + join-by-code
- [x] Cinema services OFF by default (App Store)
- [x] Voice UI gated on LiveKit (`/api/rtc/status`)
- [x] Analytics funnel (iOS Firebase + desktop hooks)
- [x] Drift lab script PASS
- [x] Windows/Mac CI workflows (dispatch)
- [x] Docs: LiveKit, App Store, Beta launch

## Ops remaining (need human keys / Apple account)

| Item | Owner | Notes |
|------|-------|--------|
| LiveKit cloud keys | Ops | `docs/LIVEKIT_SETUP.md` → enable mic |
| App Store Connect products | Ops | `plink.plus.1m/3m/12m` |
| Screenshots upload | Ops | `docs/APP_STORE_SUBMISSION.md` |
| TestFlight invite 20–25 | Ops | `docs/BETA_LAUNCH.md` |
| Windows EXE from CI | Auto | Actions run; download artifact → landing |
| Sign Android release | Ops | Play Internal track |

## Install now

| File | Path |
|------|------|
| Mac | `plink-landing/public/downloads/Plink.dmg` |
| Android | `plink-landing/public/downloads/app-debug.apk` |
| Backend | `https://plink-backend-production-ef31.up.railway.app` |

## Commands

```bash
# Drift lab
cd Desktop/Grok && npm i ws && node scripts/drift-lab.mjs

# Desktop web
cd windows-client && npm run dev

# Rebuild Mac
cd windows-client && npm run tauri:build
```
