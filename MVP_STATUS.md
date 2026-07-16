# Plink MVP Status — 16 July 2026

## Core loop: READY for closed beta

| Platform | Auth | Room | Chat | YouTube | Sync | Installer |
|----------|------|------|------|---------|------|-----------|
| **iOS** | ✅ | ✅ | ✅ | ✅ | ✅ | IPA on landing |
| **Desktop Mac** | ✅ | ✅ | ✅ | ✅ hosted player | ✅ | **DMG rebuilt** |
| **Desktop Win** | ✅ | ✅ | ✅ | ✅ | ✅ | EXE (old; rebuild on Windows CI) |
| **Android** | ✅ | ✅ | ✅ | ✅ local bridge | ✅ | **APK updated** |
| **Backend** | ✅ Railway | ✅ | ✅ | ✅ player | ✅ v2 | live |

## Shipped this continuation

1. **macOS DMG rebuild** with player + sync + AI chat UI  
   - `plink-landing/public/downloads/Plink-1.0.0-arm64.dmg`  
   - `plink-landing/public/downloads/Plink.dmg`  
   - App: `windows-client/src-tauri/target/release/bundle/macos/Plink.app`
2. **Desktop AI page** — real `/ai/chat` (message compat), fallback UX
3. **Rooms page** — join by code inline
4. **Backend** empty JSON body → `{}` (leave room no longer 400)
5. Voice still **hidden** until LiveKit (`FeatureFlags.liveKitVoiceEnabled`)
6. Cinema services **OFF** by default (App Store)

## How to run MVP now

| Client | Command / file |
|--------|----------------|
| Mac app | Open `Plink.dmg` or `Plink.app` from downloads / tauri bundle |
| Web desktop | `cd windows-client && npm run dev` → localhost:5173 |
| Android | Install `app-debug.apk` |
| iOS | Existing IPA / Xcode |

**Test path:** signup → create room from trending → 2nd device join by code → host play/pause/seek → chat.

## Remaining (post-MVP polish)

- [ ] Windows `.exe` rebuild (needs Windows runner)
- [ ] LiveKit keys → enable voice
- [ ] TestFlight / closed beta 25 users
- [ ] App Store screenshots + IAP products in ASC
- [ ] Measure 3-device drift lab formally
