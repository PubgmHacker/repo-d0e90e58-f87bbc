#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink diagnostics round 5 - based on actual logs + user feedback.

USER REPORTS (still broken after round 4):
1. Player doesn't start video - [YT] playRetry exhausted, state stays at 3
2. Flicker on long-press in DM chat and Friends tab
3. Voice notes still turquoise (not matching Prisma bubble style)

ROOT CAUSES:
1. YouTube stuck in state=3 (buffering) forever - iOS WKWebView blocks
   autoplay of unmuted video. Backend calls player.mute() in onReady,
   but by then YouTube has already decided not to autoplay. The ONLY
   reliable fix is `mute: 1` in playerVars at construction time.
   Backend source has this bug (no mute:1 in playerVars).
   iOS workaround: after navigation didFinish, inject JS that destroys
   the player and recreates it with mute:1 in playerVars.

2. Flicker - DMChatView polls loadHistory(quiet:true) every 3s. Even
   with quiet:true, if server returns slightly different timestamps or
   reaction counts, historyEpoch bumps and UI re-renders. Also V4FriendsView
   has inviteService.refreshFromServer() every 2s which triggers @Published
   updates. Need to increase both intervals.

3. Voice bubble turquoise - VoiceNoteBubble.frame returns .quiet when
   message.bubbleStyle is nil. For isOwn=true + .quiet, fillLayer returns
   Cinema2026.accent (turquoise). This happens when:
   - Voice message was sent before bubble style was saved in wire format
   - Voice message received from peer with no styleID in wire
   FIX: For isOwn voice notes, ALWAYS use PlinkBubbleStylePrefs.currentID
   (not message.bubbleStyle which may be nil for legacy messages).

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_diag5.py
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


# ---------- 1. EmbeddedPlaybackController: force-recreate player with mute:1 ----------
print("[1/3] EmbeddedPlaybackController.swift - force-recreate player with mute:1")
JS_RECREATE = '''    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false
        // iOS WKWebView blocks autoplay of unmuted video. The backend HTML
        // calls player.mute() in onReady, but by then YouTube has already
        // decided not to autoplay (state stays at 3=buffering forever).
        // Fix: destroy the player and recreate with mute:1 in playerVars.
        // muted autoplay is always allowed by iOS.
        Task { [weak self] in
            guard let self, let web = self.webView else { return }
            NSLog("[YT] force-recreating player with mute:1")
            let js = "(function(){try{if(player&&player.destroy){player.destroy();player=null;}var vid=window.__plinkVideoId||'\\(videoId ?? "")';if(!vid)return 'no-vid';player=new YT.Player('player',{height:'100%',width:'100%',videoId:vid,playerVars:{playsinline:1,controls:1,rel:0,modestbranding:1,iv_load_policy:3,enablejsapi:1,origin:window.location.origin,autoplay:1,mute:1,fs:1},events:{onReady:function(){try{player.playVideo();}catch(e){}setTimeout(function(){try{player.unMute();}catch(e){}},1500);},onStateChange:function(event){try{window.webkit.messageHandlers.plinkPlayer.postMessage({event:'state',state:event.data});}catch(e){}},onError:function(event){try{window.webkit.messageHandlers.plinkPlayer.postMessage({event:'error',code:event.data});}catch(e){}}}});return 'recreated';}catch(e){return 'err:'+e.message;}})();"
            let result = try? await web.evaluateJavaScript(js)
            NSLog("[YT] force-recreate result=\\(result ?? "?")")
        }'''
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    '''    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false''',
    JS_RECREATE,
    "handleReady force-recreate with mute:1"
)


# ---------- 2. DMChatView: increase poll interval 3s -> 6s ----------
print("[2/3] DMChatView.swift - poll interval 3s -> 6s")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                // Do NOT call friendManager.loadFriends() here \\u2014 it triggers""",
    """            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { break }
                // Do NOT call friendManager.loadFriends() here \\u2014 it triggers""",
    "DMChatView poll 3s -> 6s"
)
# Also fix V4FriendsView inviteService poll 2s -> 10s
edit_file(
    "Plink/V4/V4FriendsView.swift",
    """        // Unread DMs: 1s global poll for instant badges
        .task {
            dmService.startUnreadPolling()
            await inviteService.refreshFromServer()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                if scenePhase == .active {
                    await inviteService.refreshFromServer()
                }
            }
        }""",
    """        // Unread DMs: 1s global poll for instant badges
        .task {
            dmService.startUnreadPolling()
            await inviteService.refreshFromServer()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                if scenePhase == .active {
                    await inviteService.refreshFromServer()
                }
            }
        }""",
    "V4FriendsView invite poll 2s -> 10s"
)


# ---------- 3. VoiceNoteBubble: always use currentID for own ----------
print("[3/3] DMChatView.swift - VoiceNoteBubble uses currentID for own")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """    /// Resolve the same BubbleFrameModel PlinkMessageBubble uses, so the
    /// voice bubble matches the user's selected bubble style (Prisma, etc.)
    /// instead of always using Cinema2026.accent (turquoise).
    private var frame: BubbleFrameModel {
        if let styleID = message.bubbleStyle, !styleID.isEmpty {
            return BubbleFrameModel.resolve(styleID: styleID)
        }
        if isOwn {
            return BubbleFrameModel.resolve(styleID: PlinkBubbleStylePrefs.currentID)
        }
        return .quiet
    }""",
    """    /// Resolve the same BubbleFrameModel PlinkMessageBubble uses, so the
    /// voice bubble matches the user's selected bubble style (Prisma, etc.)
    /// instead of always using Cinema2026.accent (turquoise).
    /// For own voice notes, ALWAYS prefer PlinkBubbleStylePrefs.currentID
    /// over message.bubbleStyle because legacy voice messages may have nil
    /// bubbleStyle even though the user selected Prisma/etc locally.
    private var frame: BubbleFrameModel {
        if isOwn {
            return BubbleFrameModel.resolve(styleID: PlinkBubbleStylePrefs.currentID)
        }
        if let styleID = message.bubbleStyle, !styleID.isEmpty {
            return BubbleFrameModel.resolve(styleID: styleID)
        }
        return .quiet
    }""",
    "VoiceNoteBubble frame prefers currentID for own"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit + push:")
print("  git add -A")
print("  git commit -m 'fix: YouTube mute:1 force-recreate + poll 6s/10s + voice bubble currentID'")
print("  git push origin main")
print()
print("After rebuild, watch for:")
print("  [YT] force-recreating player with mute:1")
print("  [YT] force-recreate result=recreated  - player rebuilt with mute:1")
print("  [YT] playRetry attempt=N state=M      - should now reach state=1 (playing)")
print("=" * 60)
