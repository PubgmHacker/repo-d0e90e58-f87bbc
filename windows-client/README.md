# Plink Windows Client

MVP desktop/web client for multi-device sync testing.

## Stack

- Vite + React + TypeScript
- Ready to wrap with **Tauri** on Windows for `.exe` production build

## Dev (browser)

```bash
npm install
npm run dev
```

Open http://localhost:5173 — connects to Railway backend by default.

## Environment

```bash
VITE_API_BASE=https://plink-backend-production-ef31.up.railway.app/api
VITE_WS_BASE=wss://plink-backend-production-ef31.up.railway.app
```

## Production `.exe` (Windows machine required)

1. Install [Rust](https://rustup.rs/) and [Node.js 20+](https://nodejs.org/)
2. From this folder:

```bash
npm install
npm run build
cargo install tauri-cli
npm run tauri init   # if src-tauri not yet added
npm run tauri build
```

Output: `src-tauri/target/release/bundle/nsis/Plink_*_x64-setup.exe`

> **Note:** `.exe` cannot be cross-compiled from macOS without a Windows VM/CI. Use GitHub Actions `windows-latest` runner for automated builds.

## MVP Features

- Auth (sign in / sign up)
- Home (trending YouTube + active rooms + join by code)
- Room (YouTube embed + WebSocket chat + presence)
- Profile (avatar upload base64 + logout)