# Plink MVP: Current Status & Remaining Tasks

## Completed (Do not modify)
- Technical audit & memory stabilization (WKWebView, HeroVideoBanner, DMChatService).
- VIP Avatar Rings (Admin/Plink+, animated gradient).
- Message Bubbles (TikTok style, adaptive layout).
- Full Media Sharing (Photo upload/fetch, DM/Room gallery, real-time metadata via WebSocket, Prisma migration).

## Active Phase: Chat Functionality Polish
The codebase is currently stable. The next target is to implement **Pinned Messages & Replies** for the DM system.

### 1. Backend Implementation (Pinned Messages)
- Update Prisma Schema: Add `pinnedMessageId` (nullable) to `DirectMessage`.
- Create `PinnedMessage` table for efficient lookups.
- Implement API endpoints: `POST /api/chat/pin`, `GET /api/chat/pinned`.
- Ensure real-time broadcast of pin events via existing WebSocket logic.

### 2. iOS UI Implementation (Chat Bar & Reply)
- **Pinned Message Bar:** Add a thin, sleek bar at the top of the `DMChatView`.
- **Reply Metadata:** Add UI logic to display "Replying to..." context within `PlinkMessageBubble`.
- **Forwarding:** Implement forward logic and target selection flow.

### 3. Verification & Deployment
- Run full build scheme for Backend and iOS.
- Verify WebSocket sync for pinned messages.
- Final commit and push to `main`.

---

## Instructions for Claude
1. **Critical:** Since you are experiencing API errors, work in small, incremental steps. Perform the backend change first. **Stop and verify** before proceeding to iOS.
2. **Persistence:** Do not re-explore already completed areas. The architecture for media and sockets is already in place; extend it, don't reinvent it.
3. **Stability:** If an `API Error` occurs, pause, report the error, and wait for the user to trigger the next step.
