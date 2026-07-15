# Plink Mac Desktop

**Option A (native):** Mac Catalyst from `plink-ios/` — enable `SUPPORTS_MACCATALYST: YES` in `project.yml` (done). Requires `#if targetEnvironment(macCatalyst)` guards for iOS-only APIs.

**Option B (recommended for PRO UI parity):** Use the same `windows-client/` codebase wrapped with Tauri:

```bash
cd ../windows-client
npm run tauri init
npm run tauri build -- --target aarch64-apple-darwin
npm run tauri build -- --target x86_64-apple-darwin
# → Universal .dmg via lipo
```

Mac-specific: traffic lights, menu bar, and dock badge ship with Tauri v2 macOS config.