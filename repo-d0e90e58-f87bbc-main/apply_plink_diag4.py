#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink diagnostics round 4 - based on actual logs + user feedback.

USER REPORTS:
1. Player shows "Connecting" forever, video doesn't load
2. Flicker on long-press in DM chat AND in Friends tab
3. Voice notes use turquoise bubble instead of selected bubble style (e.g. Prisma)

LOG ANALYSIS:
1. [YT] post-ready state=3 - YouTube stuck in BUFFERING forever
   state=3 means buffering, never transitions to state=1 (playing)
   Backend HTML calls player.mute(); player.playVideo() on ready,
   but on iOS WKWebView the playVideo() may not actually start playback
   without user gesture. Need to retry playVideo() with delays from
   the iOS side, and surface a "Tap to play" overlay if still stuck.

2. [Friends] loaded 1 friends - repeats every 1 second
   V4FriendsView has a .task that polls store.refreshQuietly() every 1s
   store.refreshQuietly() -> friendManager.loadAll() -> loadFriends()
   This triggers @Published friends array update -> SwiftUI re-renders
   the entire Friends list -> contextMenu preview re-snapshots -> flicker
   FIX: increase poll interval from 1s to 10s (presence doesn't need 1s
   precision; avatars refresh via NotificationCenter on changes).

3. VoiceNoteBubble ignores message.bubbleStyle
   PlinkMessageBubble uses BubbleFrameModel.resolve(styleID:) and applies
   frame.fillColors gradient. VoiceNoteBubble hardcodes Cinema2026.accent
   for own and #2E333A for incoming - never reads bubbleStyle.
   FIX: VoiceNoteBubble should use the same fillLayer logic as
   PlinkMessageBubble so voice notes match the selected bubble style.

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_diag4.py
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


# ---------- 1. V4FriendsView: 1s poll -> 10s poll ----------
print("[1/3] V4FriendsView.swift - 1s friends poll -> 10s (fix flicker)")
edit_file(
    "Plink/V4/V4FriendsView.swift",
    """        // Friends list (presence + avatars) while tab visible \u2014 ~1s for near-realtime avatars
        .task(id: isActive) {
            guard isActive else { return }
            await store?.refreshQuietly()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                guard !Task.isCancelled, isActive else { break }
                await store?.refreshQuietly()
            }
        }""",
    """        // Friends list (presence + avatars) while tab visible.
        // Was 1s poll - caused contextMenu flicker on long-press because
        // friendManager.loadAll() rebuilds @Published friends array every
        // second, forcing SwiftUI to re-snapshot the preview. 10s is enough
        // for presence; avatars refresh instantly via .plinkAvatarsDidChange.
        .task(id: isActive) {
            guard isActive else { return }
            await store?.refreshQuietly()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard !Task.isCancelled, isActive else { break }
                await store?.refreshQuietly()
            }
        }""",
    "V4FriendsView 1s -> 10s poll"
)


# ---------- 2. EmbeddedPlaybackController: retry playVideo + tap-to-play overlay ----------
print("[2/3] EmbeddedPlaybackController.swift - retry playVideo + tap-to-play")
# Inject repeated playVideo() calls after handleReady
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false
        // Log actual player state + frame to diagnose "video doesn't play"
        Task { [weak self] in
            guard let self, let web = self.webView else { return }
            let state = try? await web.evaluateJavaScript(
                "(function(){try{return player&&player.getPlayerState?player.getPlayerState():'no-player';}catch(e){return 'err:'+e.message;}})()"
            )
            let url = try? await web.evaluateJavaScript(
                "(function(){try{return player&&player.getVideoUrl?player.getVideoUrl():'no-url';}catch(e){return 'err:'+e.message;}})()"
            )
            NSLog("[YT] post-ready state=\\(state ?? "?") url=\\(url ?? "?") frame=\\(web.frame)")
        }""",
    """    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false
        // Log actual player state + frame to diagnose "video doesn't play"
        Task { [weak self] in
            guard let self, let web = self.webView else { return }
            let state = try? await web.evaluateJavaScript(
                "(function(){try{return player&&player.getPlayerState?player.getPlayerState():'no-player';}catch(e){return 'err:'+e.message;}})()"
            )
            let url = try? await web.evaluateJavaScript(
                "(function(){try{return player&&player.getVideoUrl?player.getVideoUrl():'no-url';}catch(e){return 'err:'+e.message;}})()"
            )
            NSLog("[YT] post-ready state=\\(state ?? "?") url=\\(url ?? "?") frame=\\(web.frame)")
        }
        // Retry playVideo() with delays - YouTube on iOS WKWebView often needs
        // multiple nudges because the initial player.mute(); player.playVideo()
        // in onReady doesn't always start playback (state stays at 3=buffering).
        // We retry every 800ms up to 6 times (~5s total) until state becomes
        // 1 (playing) or 2 (paused by user).
        Task { [weak self] in
            guard let self else { return }
            for attempt in 1...6 {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                guard let web = self.webView else { return }
                let st = try? await web.evaluateJavaScript(
                    "(function(){try{return player&&player.getPlayerState?player.getPlayerState():-99;}catch(e){return -98;}})()"
                )
                let stInt = (st as? Int) ?? -1
                NSLog("[YT] playRetry attempt=\\(attempt) state=\\(stInt)")
                if stInt == 1 || stInt == 2 || stInt == 0 {
                    return // playing, paused, or ended - stop retrying
                }
                // Force playVideo + unmute
                _ = try? await web.evaluateJavaScript(
                    "(function(){try{if(player){player.unMute();player.playVideo();}return 1;}catch(e){return 'err:'+e.message;}})()"
                )
            }
            // If still buffering after 6 retries, surface tap-to-play overlay
            NSLog("[YT] playRetry exhausted - enabling tapToPlay overlay")
            await MainActor.run { self.requiresTapToPlay = true }
        }""",
    "handleReady retry + tap overlay"
)
# Add requiresTapToPlay property + surface to UI
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    /// surface YouTube error callback for UI binding.
    public private(set) var lastError: String?""",
    """    /// surface YouTube error callback for UI binding.
    public private(set) var lastError: String?

    /// True when YouTube IFrame is ready but video stays in buffering state
    /// for >5s after handleReady. UI shows a "Tap to play" overlay so the
    /// user can give the gesture YouTube needs to actually start playback.
    public private(set) var requiresTapToPlay: Bool = false""",
    "requiresTapToPlay property"
)
# Add userTapToPlay() method
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    public func setRate(_ rate: Float) {
        // YouTube IFrame API supports setPlaybackRate for some content,
        // but rate correction is disabled per capabilities.supportsRateCorrection
        // = false. OrderedSyncController falls back to precise seeks.
    }""",
    """    public func setRate(_ rate: Float) {
        // YouTube IFrame API supports setPlaybackRate for some content,
        // but rate correction is disabled per capabilities.supportsRateCorrection
        // = false. OrderedSyncController falls back to precise seeks.
    }

    /// Called by UI when user taps the "Tap to play" overlay. Sends a real
    /// user-gesture-initiated playVideo() to YouTube - this is the only
    /// reliable way to start playback on iOS WKWebView when initial
    /// autoplay failed.
    public func userTapToPlay() async {
        guard let web = webView else { return }
        NSLog("[YT] userTapToPlay - sending playVideo with user gesture")
        _ = try? await web.evaluateJavaScript(
            "(function(){try{if(player){player.unMute();player.playVideo();}return 1;}catch(e){return 'err:'+e.message;}})()"
        )
        // Give YouTube 600ms then clear the overlay if playback started
        try? await Task.sleep(nanoseconds: 600_000_000)
        let st = try? await web.evaluateJavaScript(
            "(function(){try{return player&&player.getPlayerState?player.getPlayerState():-99;}catch(e){return -98;}})()"
        )
        let stInt = (st as? Int) ?? -1
        NSLog("[YT] after userTap state=\\(stInt)")
        if stInt == 1 || stInt == 2 {
            await MainActor.run { self.requiresTapToPlay = false }
        }
    }""",
    "userTapToPlay method"
)


# ---------- 3. VoiceNoteBubble: respect bubbleStyle ----------
print("[3/3] DMChatView.swift - VoiceNoteBubble respects bubbleStyle")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """private struct VoiceNoteBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    @State private var player = VoiceNotePlayer.shared
    @State private var playError: String?

    private var durationLabel: String {
        if let d = message.voiceDurationSec {
            return PlinkVoiceWire.formatDuration(d)
        }
        return "0:00"
    }

    private var isThisPlaying: Bool {
        player.playingMessageId == message.id
    }

    private var canPlay: Bool {
        // Voice notes always try play \u2014 local cache or server stream
        message.isVoiceNote || message.hasMedia || message.mediaType == "voice"
    }""",
    """private struct VoiceNoteBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    @State private var player = VoiceNotePlayer.shared
    @State private var playError: String?

    private var durationLabel: String {
        if let d = message.voiceDurationSec {
            return PlinkVoiceWire.formatDuration(d)
        }
        return "0:00"
    }

    private var isThisPlaying: Bool {
        player.playingMessageId == message.id
    }

    private var canPlay: Bool {
        // Voice notes always try play \u2014 local cache or server stream
        message.isVoiceNote || message.hasMedia || message.mediaType == "voice"
    }

    /// Resolve the same BubbleFrameModel PlinkMessageBubble uses, so the
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
    }

    /// Fill layer matching PlinkMessageBubble.fillLayer so voice bubbles
    /// visually match text bubbles with the same styleID.
    @ViewBuilder
    private var fillLayer: some View {
        switch frame {
        case .quiet:
            if isOwn {
                LinearGradient(
                    colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "#2E333A"), Color(hex: "#252A30")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        default:
            LinearGradient(
                colors: frame.fillColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        if frame.borderColors.count >= 2 {
            V5BubbleShape(isOutgoing: isOwn, isLastInGroup: true)
                .stroke(
                    AngularGradient(
                        colors: frame.borderColors + [frame.borderColors[0]],
                        center: .center
                    ),
                    lineWidth: frame.borderWidth
                )
        }
    }""",
    "VoiceNoteBubble style-aware properties"
)
# Update body to use fillLayer/borderLayer
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """        .padding(.horizontal, PlinkTelegramBubbleMetrics.padH)
        .padding(.vertical, PlinkTelegramBubbleMetrics.padV)
        .background(
            ZStack {
                Color(hex: "#1A1C20")
                if isOwn {
                    LinearGradient(
                        colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color(hex: "#2E333A")
                }
            }
        )
        .clipShape(V5BubbleShape(isOutgoing: isOwn, isLastInGroup: true))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isOwn ? 0.20 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.40), radius: 8, y: 3)
        .shadow(color: .black.opacity(0.20), radius: 1, y: 0.5)
    }
}""",
    """        .padding(.horizontal, PlinkTelegramBubbleMetrics.padH)
        .padding(.vertical, PlinkTelegramBubbleMetrics.padV)
        .background(
            ZStack {
                // Dark base for contrast even if gradient is translucent
                Color(hex: "#1A1C20")
                fillLayer
            }
        )
        .clipShape(V5BubbleShape(isOutgoing: isOwn, isLastInGroup: true))
        .overlay(borderLayer)
        .shadow(color: .black.opacity(0.40), radius: 8, y: 3)
        .shadow(color: .black.opacity(0.20), radius: 1, y: 0.5)
    }
}""",
    "VoiceNoteBubble body uses fillLayer/borderLayer"
)


# ---------- 4. PlayerStage: tap-to-play overlay UI ----------
print("[4/4] PlayerStage.swift - tap-to-play overlay UI")
edit_file(
    "Plink/Features/WatchRoom/PlayerStage.swift",
    """            // Loading overlay only when we still have no player surface.""",
    """            // Tap-to-play overlay - shown when YouTube IFrame is ready
            // but the video is stuck in buffering and never reached playing
            // state. iOS WKWebView often requires a real user gesture to
            // start YouTube playback even with autoplay:1 in playerVars.
            if let yt = model.coordinator.currentController as? EmbeddedPlaybackController,
               yt.requiresTapToPlay {
                Button {
                    HapticManager.impact(.medium)
                    Task { await yt.userTapToPlay() }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                        Text("Tap to play")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("YouTube needs a tap to start")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .zIndex(50)
            }

            // Loading overlay only when we still have no player surface.""",
    "PlayerStage tap-to-play overlay"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit + push:")
print("  git add -A")
print("  git commit -m 'fix: YouTube tap-to-play + friends poll 10s + voice bubble style'")
print("  git push origin main")
print()
print("After rebuild, watch for:")
print("  [YT] playRetry attempt=N state=M  - retries every 800ms")
print("    state: 1=playing, 2=paused, 3=buffering, 5=cued, 0=ended")
print("  [YT] playRetry exhausted           - tap-to-play overlay shown")
print("  [YT] userTapToPlay                 - user tapped overlay")
print("=" * 60)
