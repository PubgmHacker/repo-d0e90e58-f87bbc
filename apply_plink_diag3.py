#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink diagnostics round 3 — based on actual logs from user.

LOG ANALYSIS:
- [WatchRoom] connect ... mediaSource=.youtube("5ZLMJyoJIsk") ✓
- [Realtime] state: connecting → authenticating → joining → synchronizing → connected ✓
- [YT] handleReady - YouTube IFrame API ready ✓
- [YT] navigation didFinish ✓

So realtime + YouTube IFrame API both succeed. But user reports:
1. Player shows "Offline"  → cause: initial state is .idle → "Offline" flash
2. Video doesn't load      → cause: WKWebView may be zero-size OR YouTube video
                              element not actually playing (need to log state)
3. Flicker on long-press   → cause: friendManager.loadFriends() in poll loop
                              triggers UI re-render every 3s
4. Voice bubble missing    → cause: no voice logs visible, need to track metadata

FIXES:
1. WatchRoomModel default state .idle → .connecting (eliminates initial "Offline" flash)
2. EmbeddedPlaybackController: log WKWebView frame size + poll player state via JS
3. DMChatView: don't call friendManager.loadFriends() in poll loop (only on first load)
4. DMChatService: add voice-specific logs in sendVoiceNote + loadHistory

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_diag3.py
"""
import os

PROJECT = os.getcwd()

def edit_file(rel_path, find, replace, label):
    full = os.path.join(PROJECT, rel_path)
    if not os.path.exists(full):
        print(f"  [MISS] {rel_path}")
        return False
    with open(full, "r", encoding="utf-8") as f:
        content = f.read()
    if replace in content:
        print(f"  [SKIP] {label} - already applied")
        return True
    if find not in content:
        print(f"  [WARN] {label} - find-marker not found")
        return False
    new_content = content.replace(find, replace, 1)
    with open(full, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  [OK]   {label}")
    return True


# ---------- 1. WatchRoomModel: default state .idle → .connecting ----------
print("[1/4] WatchRoomModel.swift - default state .idle -> .connecting")
edit_file(
    "Plink/Features/WatchRoom/WatchRoomModel.swift",
    """    public private(set) var connectionState: RealtimeConnectionState = .idle""",
    """    // Default to .connecting (not .idle) so the SyncHealthPill shows
    // "Connecting\\u2026" instead of "Offline" during the brief moment between
    // view appear and model.connect() running. disconnect() still sets .idle
    // so the pill correctly shows "Offline" after the user leaves the room.
    public private(set) var connectionState: RealtimeConnectionState = .connecting""",
    "default state to .connecting"
)


# ---------- 2. EmbeddedPlaybackController: log frame size + poll player state ----------
print("[2/4] EmbeddedPlaybackController.swift - log frame + poll player state")
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """        webView = web
        embeddedView = web
        // One surface notify — enough for SwiftUI to attach. Do NOT spam
        // surfaceEpoch (recreates UIViewRepresentable and kills the load).
        onSurfaceChanged?()""",
    """        webView = web
        embeddedView = web
        // One surface notify \\u2014 enough for SwiftUI to attach. Do NOT spam
        // surfaceEpoch (recreates UIViewRepresentable and kills the load).
        onSurfaceChanged?()
        NSLog("[YT] WKWebView created frame=\\(web.frame)")""",
    "WKWebView frame log"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false""",
    """    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false
        // Log actual player state + frame to diagnose "video doesn't play"
        Task { [weak self] in
            guard let self, let web = self.webView else { return }
            let state = await web.evaluateJavaScript(
                "(function(){try{return player&&player.getPlayerState?player.getPlayerState():'no-player';}catch(e){return 'err:'+e.message;}})()"
            )
            let url = await web.evaluateJavaScript(
                "(function(){try{return player&&player.getVideoUrl?player.getVideoUrl():'no-url';}catch(e){return 'err:'+e.message;}})()"
            )
            NSLog("[YT] post-ready state=\\(state ?? "?") url=\\(url ?? "?") frame=\\(web.frame)")
        }""",
    "handleReady post-state log"
)


# ---------- 3. DMChatView: don't call friendManager.loadFriends() in poll loop ----------
print("[3/4] DMChatView.swift - drop friendManager.loadFriends() from poll loop")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await friendManager.loadFriends()
                // quiet:true so loadHistory's change-detection gates UI
                // updates - only re-renders when messages actually changed.
                // (quiet:false forced historyEpoch bump every poll -> flicker
                // on long-press because contextMenu preview re-snapshotted.)
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: liveFriend.displayTitle,
                    friendAvatarURL: liveFriend.avatarURL,
                    quiet: true
                )
            }""",
    """            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                // Do NOT call friendManager.loadFriends() here \\u2014 it triggers
                // a full UI re-render every 3s (friends list is @Observable),
                // which re-snapshots the contextMenu preview during long-press
                // and causes flicker. Friends are loaded once on .task entry
                // above; the Friends tab refreshes presence independently.
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: liveFriend.displayTitle,
                    friendAvatarURL: liveFriend.avatarURL,
                    quiet: true
                )
            }""",
    "DM poll without friendManager"
)


# ---------- 4. DMChatService: voice-specific logs ----------
print("[4/4] DMChatService.swift - voice metadata logs")
edit_file(
    "Plink/Services/DMChatService.swift",
    """    func sendVoiceNote(dataURL: String, durationSec: TimeInterval, to friend: Friend) {""",
    """    func sendVoiceNote(dataURL: String, durationSec: TimeInterval, to friend: Friend) {
        NSLog("[DMVoice] sendVoiceNote friendId=\\(friend.id) dur=\\(durationSec)s dataLen=\\(dataURL.count)")""",
    "sendVoiceNote entry log"
)
edit_file(
    "Plink/Services/DMChatService.swift",
    """                // Re-key local audio so play keeps working after id swap
                VoiceNotePlayer.shared.promote(from: localID, to: saved.id)""",
    """                NSLog("[DMVoice] upload OK savedId=\\(saved.id) mediaType=\\(saved.mediaType ?? "nil") hasMedia=\\(saved.hasMedia ?? false) dur=\\(saved.mediaDurationSec ?? -1)")
                // Re-key local audio so play keeps working after id swap
                VoiceNotePlayer.shared.promote(from: localID, to: saved.id)""",
    "sendVoiceNote upload result log"
)
edit_file(
    "Plink/Services/DMChatService.swift",
    """                print("[DM] sendVoiceNote error: \\(error.localizedDescription)")""",
    """                NSLog("[DMVoice] upload FAIL: \\(error.localizedDescription)")
                print("[DM] sendVoiceNote error: \\(error.localizedDescription)")""",
    "sendVoiceNote error log"
)
# Log voice detection in loadHistory
edit_file(
    "Plink/Services/DMChatService.swift",
    """                let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                let isVoice = dto.mediaType == "voice" || (dto.hasMedia == true) || voiceMeta.isVoice
                let displayText = voiceMeta.isVoice ? voiceMeta.displayText : decoded.text""",
    """                let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                let isVoice = dto.mediaType == "voice" || (dto.hasMedia == true) || voiceMeta.isVoice
                let displayText = voiceMeta.isVoice ? voiceMeta.displayText : decoded.text
                if isVoice {
                    NSLog("[DMVoice] history voice msg id=\\(dto.id) mediaType=\\(dto.mediaType ?? "nil") hasMedia=\\(dto.hasMedia ?? false) wireVoice=\\(voiceMeta.isVoice) dur=\\(voiceMeta.durationSec ?? -1)")
                }""",
    "loadHistory voice log"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit + push:")
print("  git add -A")
print("  git commit -m 'fix: default state .connecting + drop friends poll + voice logs'")
print("  git push origin main")
print()
print("Watch for these new logs after rebuild:")
print("  [YT] WKWebView created frame=...     - check frame is non-zero")
print("  [YT] post-ready state=N url=...      - 1=playing, 2=paused, 3=buffering, 5=cued")
print("  [DMVoice] sendVoiceNote ...          - voice send flow")
print("  [DMVoice] upload OK/FAIL ...         - server response with mediaType")
print("  [DMVoice] history voice msg ...      - incoming voice metadata")
print("=" * 60)
