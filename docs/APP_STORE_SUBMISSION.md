# App Store submission kit (MVP)

## Product IDs (StoreKit)

| Product | ID | Price intent |
|---------|-----|--------------|
| 1 month | `plink.plus.1m` | 149₽ |
| 3 months | `plink.plus.3m` | 349₽ |
| 12 months | `plink.plus.12m` | 990₽ |

Create auto-renewable subscription group **Plink+** in App Store Connect.

## Metadata

See `APP_STORE_METADATA.md`.

- **Name:** Plink — Watch Together / Плинк — смотрите вместе  
- **Category:** Entertainment  
- **Age:** 12+ or 17+ if UGC chat unmoderated  
- **Privacy / Terms:** landing `/privacy` `/terms`

## Screenshots checklist

| Device | Required | Content |
|--------|----------|---------|
| 6.7" iPhone | ☐ | Home hero, Watch room, AI, Friends, Profile+ |
| 6.5" iPhone | ☐ | Same set |
| 12.9" iPad | ☐ | Split watch room |

### Capture (Simulator)

```bash
# After xcodegen + build
xcrun simctl io booted screenshot ~/Desktop/plink-home.png
```

Or use Xcode → Simulator → Device → Screenshots.

**Do not** show Netflix/Disney/cinema services (ENABLE_CINEMA=false).

## Review notes template

```
Test account: <email> / <password>
Core flow: Sign in → Home trending → Create room → Join from 2nd device with code → Chat + play/pause
IAP: Plink+ sandbox products plink.plus.1m / 3m / 12m
Voice: disabled until LiveKit configured (mic hidden)
Supported video: YouTube, VK, Rutube, custom URL
```

## Guidelines risk map

| Guideline | Status |
|-----------|--------|
| 2.1 Completeness | Core loop works; voice hidden not broken |
| 3.1.1 IAP | StoreKit 2 only |
| 4.2 Min functionality | Native app, not shell browser |
| 5.1 Privacy | Policy URL required |
| Cinema ToS | ENABLE_CINEMA default false |

## Upload

1. Archive in Xcode (Release, team signing)  
2. Upload via Organizer / Transporter  
3. Attach screenshots + review notes  
4. Submit for review  
