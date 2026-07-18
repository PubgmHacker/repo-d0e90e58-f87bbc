# Plink MVP Development Instructions

## Role & Objective
You are the lead iOS engineer for the Plink project. Your goal is to finalize the MVP, transitioning it from a functional prototype to a submission-ready product with professional-grade polish, high-performance architecture, and a "TikTok/Telegram-inspired" user experience.

## Execution Priority
1. **Technical Audit & Stability**
2. **Architectural Prep for Media Sharing**
3. **UI Redesign (Bubbles & Avatar Rings)**

---

## Task Breakdown

### 1. Technical Audit and Stabilization
Before implementing any UI changes, perform a thorough audit:
- Check for memory leaks in chat controllers.
- Ensure the recent `ServiceAuthView` integration is stable and does not cause retain cycles.
- **Output:** Provide a brief report on findings/errors or confirm system stability before proceeding.

### 2. VIP Status Animation ("Ring Effect")
Implement a continuous animated gradient ring around Admin and Plink+ avatars.
- **Style:** Fast, smooth, continuous gradient loop.
- **Palettes:**
  - **Admin:** Bright Scarlet -> Deep Maroon.
  - **Plink+:** Gold -> Bronze.
- **Technical constraints:** Use optimized `CoreAnimation` or `Angular Gradient` (SwiftUI). Performance is critical—the animation must not affect scroll smoothness.

### 3. Message Bubble Redesign (TikTok Style)
Overhaul message visuals for a modern, sleek feel:
- Custom bubble shapes with modern rounded corners.
- Automatic sizing based on content (text/links).
- Refine visual hierarchy (padding, typography, contrast) to match a professional messaging experience.

### 4. Media Sharing (Photos)
Implement photo sharing for Private and Video Room chats.
- **UI:** Add a "+" / "Gallery" button in the chat input field.
- **Functionality:** 
  - Support previews and captions (Telegram-style).
  - **Video Room:** Ensure photo messages integrate into the feed without disrupting video synchronization or obstructing the player.
- **Logic:** Implement image compression to optimize bandwidth usage.

---

## Guidelines for Claude
- **Code Quality:** Prioritize performance and memory safety. Use `@Published` and `WatchRoomModel` state management as per the existing architecture.
- **Stability:** Ensure all experimental code is properly gated.
- **Communication:** If you encounter architectural blockers during the audit, stop and report them before moving to UI tasks.
