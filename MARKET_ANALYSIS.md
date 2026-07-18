# Plink Market Analysis — Rave / Hearo Teardown

_Date: 2026-07-18_

## Executive Positioning

Plink should not compete as “another watch party app.” Rave and Hearo already own the generic promise of watching together. Plink’s wedge is a premium, AI-assisted, mobile-first social cinema room: reliable sync, expressive chat, voice presence, rich room identity, and a companion that helps people decide what to watch and keep the room alive.

## Competitor Teardown

| Dimension | Rave | Hearo | Plink Current | Plink Target |
|---|---|---|---|---|
| Core promise | Watch videos together across services | Social watch parties with chat/voice orientation | Room-based co-watch with YouTube/VK/Rutube/web embeds | “Living room in your pocket” with premium AI/social layer |
| YouTube playback | Strong consumer expectation, official-ish UX | Expected support | Backend search + official embedded iOS path; internal extraction verified for backend cache/QA | Embedded-first App Store path, extraction only internal/DEBUG |
| Sync reliability | Users tolerate but often complain about drift/desync in long sessions | Voice/social helps mask sync imperfections | Realtime v2, clock sync, ordered commands, drift telemetry | Expose sync health and self-healing as a visible trust feature |
| Voice | Core social feature | Core differentiator | LiveKit plumbing and Plink+ gating present | Spatial voice, mic ducking, host controls, “couch mode” |
| Chat | Basic room chat/reactions | Strong social layer | Text chat, reactions, danmaku-style overlay | Make chat expressive: stickers, room memes, AI prompts, quote moments |
| UI/UX | Functional, mass-market, ad-supported feel | Social-first, less cinematic | Cinematic SwiftUI shell but uneven legacy surfaces | Premium Siri/Sber-like AI, fluid glass, fewer dead states |
| Discovery | Service/catalog driven | Social discovery | YouTube search/trending/categories, AI recommendations | AI concierge + friend activity + shared queues |
| Monetization | Ads/subscription style | Social utility | Plink+ gates voice/themes | Plink+ as premium room identity + voice + AI power tools |

## Ruthless Product Diagnosis

### Plink Advantages
- AI assistant is a real differentiator if it becomes action-oriented: create room, build queue, suggest based on room mood, summarize chat, troubleshoot sync.
- Realtime architecture is more explicit than typical consumer apps: clock sync, ordered commands, telemetry hooks.
- Regional/provider breadth (VK/Rutube/web embeds) can win markets underserved by Rave/Hearo.
- Visual identity can be much more premium than ad-heavy competitors.

### Plink Gaps Blocking Launch
- App Store-compliant YouTube path must stay embedded-first; raw extraction must never be the Release playback default.
- Invite flow needs low-friction share sheet, room code, deep link fallback, and a loading state when joining.
- Voice needs clear permission/onboarding and graceful disabled states for non-premium users.
- AI UI must feel native and premium; pixel/model avatar breaks trust.
- Empty/error/loading states must be treated as product surfaces, not debug afterthoughts.

## MVP Launch Checklist

- [ ] Stable auth/session restore with clear expired-session UX.
- [ ] Create room from YouTube search result in under 3 taps.
- [ ] Share invite via system share sheet with room code + universal/deep link fallback.
- [ ] Join room from invite link and recover media item if initial payload is incomplete.
- [ ] YouTube Release playback uses official embedded WKWebView path only.
- [ ] Host play/pause state propagates through realtime v2 and viewers recover on reconnect.
- [ ] Loading states for search, room creation, room join, player prepare, and invite send.
- [ ] Non-blocking error surfaces: chat/presence should still work if player fails.
- [ ] Voice permission education + Plink+ upsell state.
- [ ] AI assistant backend key remains server-side only; client never stores AI provider keys.
- [ ] Basic analytics/telemetry for room creation, join success, player ready time, and sync correction.
- [ ] App Store privacy/compliance copy aligned with embedded-provider playback.

## Market Dominance Checklist

- [ ] Spatial audio rooms: friend voices positioned around the “couch.”
- [ ] Mic ducking: lower media volume when someone speaks, with per-room toggle.
- [ ] Picture-in-Picture for native MP4/HLS and provider-safe fullscreen affordances for embeds.
- [ ] AI concierge: “make a room for tonight,” “find 3 funny videos,” “invite my usual group.”
- [ ] AI sync doctor: detects failed player states and gives one-tap recovery.
- [ ] Shared queue with voting, veto, and “surprise me” AI picks.
- [ ] Clip-free moment markers: timestamp reactions and chat highlights without recording protected content.
- [ ] Premium room themes that react to audio/chat/reactions.
- [ ] Creator/community rooms with moderation controls and scheduled watch events.
- [ ] Friend activity graph: who is online, what rooms are active, quick join with privacy controls.
- [ ] Cross-platform parity: Android + desktop shell for watch rooms after iOS MVP hardens.

## Go-To-Market Angle

Lead with: **“Watch together with an AI co-host.”** Rave and Hearo sell synchronization; Plink should sell atmosphere, taste-making, and room identity. The first viral loop is not “we sync YouTube” — it is “our room feels alive.”
