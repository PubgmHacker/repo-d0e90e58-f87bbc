# Plink Landing — Rave-style deliverable

## What's inside

- **Bright Rave.io-style video background** (full opacity + light overlay)
- **Living themes** — cycling Aurora / Cinema / Cosmos / Ocean / Sunset / Verdant with animated orbs
- **Plink logo PNG** in `public/img/`:
  - `plink-logo-mark.png` — app icon (512×512)
  - `plink-logo-1024.png` — hi-res icon
  - `plink-logo-wordmark.png` — header logo
  - `plink-logo-white.png` — footer wordmark
  - `plink-logo.png` — 128×128 icon
- **Device mockups** with Plink screenshots
- **Downloads**: Mac, Windows, Android APK, App Store link

## Run locally

```bash
cd plink-landing
npm install
npm run dev
# http://localhost:3000
```

## Production build

```bash
npm run build
npm start
```

## App Store ID

Set `NEXT_PUBLIC_APP_STORE_ID` or edit `src/lib/downloads.ts`.