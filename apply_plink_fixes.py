#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Apply Plink real fixes (commit eb04d145) to local Swift files.

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_fixes.py

What it does:
1. PlinkPermissions.swift — silence iOS 17 deprecation warnings
2. PlayerControlLayer.swift — SyncHealthPill shows transient state labels
3. PlinkApprovedV4Root.swift — quickCreateRoom ensures authToken + mediaItem
4. DMChatService.swift — receiveMessage preserves voice metadata
5. DMChatView.swift — per-bubble contextMenu (no flicker)

Idempotent — skips already-applied edits. Safe to re-run.
"""
import os
import sys

PROJECT = os.getcwd()

def edit_file(rel_path, find, replace, label):
    full = os.path.join(PROJECT, rel_path)
    if not os.path.exists(full):
        print(f"  [MISS] {rel_path} — file not found at {full}")
        return False
    with open(full, "r", encoding="utf-8") as f:
        content = f.read()
    if replace in content:
        print(f"  [SKIP] {label} — already applied")
        return True
    if find not in content:
        print(f"  [WARN] {label} — find-marker not found (file changed?)")
        return False
    new_content = content.replace(find, replace, 1)
    with open(full, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  [OK]   {label}")
    return True


# ---------- 1. PlinkPermissions.swift ----------
print("[1/5] PlinkPermissions.swift — iOS 17 deprecation warnings")
edit_file(
    "Plink/Services/PlinkPermissions.swift",
    """    // MARK: - Microphone (voice notes / room voice)

    static var isMicAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted // deprecated fallback for iOS < 17
    }

    /// Request mic once — first voice note or room voice toggle. Shows system dialog.
    @discardableResult
    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicAuthorized { return true }

        UserDefaults.standard.set(true, forKey: Keys.didPromptMic)

        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }""",
    """    // MARK: - Microphone (voice notes / room voice)
    // Deployment target is iOS 17.0+ — use AVAudioApplication exclusively.
    // AVAudioSession.sharedInstance().recordPermission is deprecated in iOS 17.

    static var isMicAuthorized: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Request mic once — first voice note or room voice toggle. Shows system dialog.
    @discardableResult
    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicAuthorized { return true }

        UserDefaults.standard.set(true, forKey: Keys.didPromptMic)

        return await AVAudioApplication.requestRecordPermission()
    }""",
    "PlinkPermissions mic API"
)


# ---------- 2. PlayerControlLayer.swift ----------
print("[2/5] PlayerControlLayer.swift — SyncHealthPill transient labels")
edit_file(
    "Plink/Features/WatchRoom/PlayerControlLayer.swift",
    """                SyncHealthPill(
                    driftMs: model.lastDriftMs,
                    connected: model.connectionState == .connected
                )""",
    """                SyncHealthPill(
                    driftMs: model.lastDriftMs,
                    connected: model.connectionState == .connected,
                    transientLabel: SyncHealthPill.transientLabel(for: model.connectionState)
                )""",
    "PlayerTopChrome pill call"
)
edit_file(
    "Plink/Features/WatchRoom/PlayerControlLayer.swift",
    """struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    private var color: Color {
        guard connected else { return Cinema2026.danger }
        if driftMs < 80 { return Cinema2026.accent }
        if driftMs < 250 { return Cinema2026.secondary }
        if driftMs < 750 { return Cinema2026.amber }
        return Cinema2026.danger
    }

    private var label: String {
        guard connected else { return "Offline" }
        if driftMs < 80 { return "In sync" }
        if driftMs < 250 { return "Syncing" }
        if driftMs < 750 { return "Lagging" }
        return "Resync"
    }""",
    """struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool
    /// Optional transient label ("Connecting\u2026", "Syncing\u2026", "Reconnecting\u2026").
    /// When non-nil and not connected, this text replaces the bare "Offline"
    /// so the user sees an active progress state instead of a dead-end label.
    var transientLabel: String? = nil

    private var color: Color {
        if !connected {
            // Transient states use amber (in-progress), true offline uses red.
            return transientLabel == nil ? Cinema2026.danger : Cinema2026.amber
        }
        if driftMs < 80 { return Cinema2026.accent }
        if driftMs < 250 { return Cinema2026.secondary }
        if driftMs < 750 { return Cinema2026.amber }
        return Cinema2026.danger
    }

    private var label: String {
        if !connected {
            // Show the active progress label if provided; otherwise bare Offline.
            return transientLabel ?? "Offline"
        }
        if driftMs < 80 { return "In sync" }
        if driftMs < 250 { return "Syncing" }
        if driftMs < 750 { return "Lagging" }
        return "Resync"
    }""",
    "SyncHealthPill struct fields"
)
edit_file(
    "Plink/Features/WatchRoom/PlayerControlLayer.swift",
    """        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }
}""",
    """        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }

    /// Map a RealtimeConnectionState to a transient UX label.
    /// Returns nil for .connected (handled by drift label) and .idle/.failed
    /// (those are "Offline" — the user should see the bare red state).
    static func transientLabel(for state: RealtimeConnectionState) -> String? {
        switch state {
        case .connecting:
            return "Connecting\u2026"
        case .authenticating:
            return "Authenticating\u2026"
        case .joining:
            return "Joining\u2026"
        case .synchronizing:
            return "Syncing\u2026"
        case .reconnecting(let attempt):
            return attempt > 1 ? "Reconnecting (\\(attempt))\u2026" : "Reconnecting\u2026"
        case .connected, .idle, .failed:
            return nil
        }
    }
}""",
    "SyncHealthPill.transientLabel helper"
)


# ---------- 3. PlinkApprovedV4Root.swift ----------
print("[3/5] PlinkApprovedV4Root.swift — quickCreateRoom auth + mediaItem")
edit_file(
    "Plink/V4/PlinkApprovedV4Root.swift",
    """    private func quickCreateRoom() async {
        guard let trending = searchStore.trending.first else { return }
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = trending.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\\(videoId)",
            title: trending.title,
            artist: nil,
            thumbnailURL: trending.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\\(videoId)",
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
        )
        let request = CreateRoomRequest(
            name: "\\(trending.title)",
            maxParticipants: 4,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient.shared
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "\u041a\u043e\u0434 \u043a\u043e\u043c\u043d\u0430\u0442\u044b Plink: \\(room.code)"
                roomToPresent = room
                Task { await roomsStore?.load() }
            }
        } catch {}
    }""",
    """    private func quickCreateRoom() async {
        guard let trending = searchStore.trending.first else { return }
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        // Ensure APIClient.shared has the token — Keychain alone is NOT enough
        // for RoomService.createRoom (which uses APIClient.request that reads
        // authToken from memory). Without this, createRoom silently 401s and
        // the user sees an eternal spinner with "Offline" pill in the room.
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run { HapticManager.errorOccurred() }
            return
        }

        let videoId = trending.id
        // Use watch URL — backend + client both extract videoId reliably
        // (embed URL has different extraction paths and historically lost
        // the mediaItem on the server side, leaving rooms with no media).
        let streamURL = "https://www.youtube.com/watch?v=\\(videoId)"
        let mediaItem = MediaItem(
            id: videoId,
            title: trending.title,
            artist: nil,
            thumbnailURL: trending.artworkURL?.absoluteString,
            streamURL: streamURL,
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
        )
        let request = CreateRoomRequest(
            name: String(trending.title.prefix(80)),
            maxParticipants: 10,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient.shared
            var room = try await RoomService(api: api).createRoom(request)
            // If server stripped mediaItem, keep the local one for playback
            // — otherwise mediaSource is nil → "\u041d\u0435\u0442 \u0432\u0438\u0434\u0435\u043e" + Offline pill.
            if room.mediaItem == nil {
                room = Room(
                    id: room.id,
                    name: room.name,
                    hostID: room.hostID,
                    hostName: room.hostName,
                    code: room.code,
                    participants: room.participants,
                    mediaItem: mediaItem,
                    isActive: room.isActive,
                    maxParticipants: room.maxParticipants,
                    hostIsPremium: room.hostIsPremium,
                    createdAt: room.createdAt,
                    privacy: room.privacy,
                    password: room.password
                )
            }
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "\u041a\u043e\u0434 \u043a\u043e\u043c\u043d\u0430\u0442\u044b Plink: \\(room.code)"
                roomToPresent = room
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
                Task { await roomsStore?.load() }
            }
        } catch {
            await MainActor.run {
                HapticManager.errorOccurred()
                print("[Root] quickCreateRoom failed: \\(error)")
            }
        }
    }""",
    "quickCreateRoom full body"
)


# ---------- 4. DMChatService.swift ----------
print("[4/5] DMChatService.swift — receiveMessage preserves voice metadata")
edit_file(
    "Plink/Services/DMChatService.swift",
    """        let decoded = PlinkBubbleWire.decode(message.text)
        let normalized = DirectMessage(
            id: message.id,
            conversationID: message.conversationID,
            senderID: message.senderID,
            recipientID: message.recipientID,
            senderName: message.senderName,
            text: decoded.text,
            timestamp: message.timestamp,
            isRead: message.isRead,
            senderAvatarURL: message.senderAvatarURL,
            bubbleStyle: decoded.styleID ?? message.bubbleStyle,
            reactions: message.reactions
        )""",
    """        let decoded = PlinkBubbleWire.decode(message.text)
        // Re-detect voice metadata from the wire format. The realtime path
        // may carry voice notes as text-only payloads when the upstream
        // service does not set mediaType/hasMedia explicitly. If we don't
        // re-flag voice here, the bubble renders as plain text instead of
        // the VoiceNoteBubble capsule.
        let wireVoice = PlinkVoiceWire.decode(decoded.text)
        let isVoice = message.mediaType == "voice"
            || message.hasMedia
            || wireVoice.isVoice
        let displayText = wireVoice.isVoice ? wireVoice.displayText : decoded.text
        let normalized = DirectMessage(
            id: message.id,
            conversationID: message.conversationID,
            senderID: message.senderID,
            recipientID: message.recipientID,
            senderName: message.senderName,
            text: displayText,
            timestamp: message.timestamp,
            isRead: message.isRead,
            senderAvatarURL: message.senderAvatarURL,
            bubbleStyle: decoded.styleID ?? message.bubbleStyle,
            reactions: message.reactions,
            mediaType: isVoice ? "voice" : message.mediaType,
            mediaDurationSec: message.mediaDurationSec ?? wireVoice.durationSec,
            hasMedia: isVoice || message.hasMedia
        )""",
    "receiveMessage voice metadata"
)


# ---------- 5. DMChatView.swift ----------
print("[5/5] DMChatView.swift — per-bubble contextMenu")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.isVoiceNote {
                        VoiceNoteBubble(
                            message: message,
                            isOwn: isOwn
                        )
                    } else {
                        PlinkMessageBubble(
                            text: message.text,
                            isOwn: isOwn,
                            styleID: message.bubbleStyle,
                            fontSize: PlinkTelegramBubbleMetrics.fontSize,
                            isLastInGroup: cluster.isLastInGroup
                        )
                    }
                }
                .contextMenu {
                    Button {
                        onReact()
                    } label: {
                        Label("\u0420\u0435\u0430\u043a\u0446\u0438\u044f", systemImage: "face.smiling")
                    }
                    if !message.isVoiceNote {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("\u041a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c", systemImage: "doc.on.doc")
                        }
                    }
                }
                // Removed onLongPressGesture — conflicts with .contextMenu causing flicker.
                // contextMenu already provides long-press behaviour.""",
    """            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                // Apply .contextMenu to each individual bubble rather than to
                // the Group wrapping the conditional content. SwiftUI's
                // contextMenu preview snapshot hits a flicker when the Group's
                // body re-evaluates during the long-press (e.g. a polling
                // refresh flips isVoiceNote or arrives with new reactions).
                // Per-bubble contextMenu gives a stable snapshot target.
                if message.isVoiceNote {
                    VoiceNoteBubble(
                        message: message,
                        isOwn: isOwn
                    )
                    .contextMenu {
                        contextMenuButtons
                    }
                } else {
                    PlinkMessageBubble(
                        text: message.text,
                        isOwn: isOwn,
                        styleID: message.bubbleStyle,
                        fontSize: PlinkTelegramBubbleMetrics.fontSize,
                        isLastInGroup: cluster.isLastInGroup
                    )
                    .contextMenu {
                        contextMenuButtons
                    }
                }
                // Removed onLongPressGesture — conflicts with .contextMenu causing flicker.
                // contextMenu already provides long-press behaviour.""",
    "DMBubble per-bubble contextMenu"
)
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """    private var reactionChips: some View {""",
    """    /// Context menu buttons shared by both voice and text bubbles.
    /// Defined once so the menu's content is identical regardless of which
    /// bubble type the user long-pressed — avoids SwiftUI re-evaluating two
    /// separate menu builders during the long-press gesture.
    @ViewBuilder
    private var contextMenuButtons: some View {
        Button {
            onReact()
        } label: {
            Label("\u0420\u0435\u0430\u043a\u0446\u0438\u044f", systemImage: "face.smiling")
        }
        if !message.isVoiceNote {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("\u041a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c", systemImage: "doc.on.doc")
            }
        }
    }

    private var reactionChips: some View {""",
    "DMBubble contextMenuButtons helper"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit:              git add -A && git commit -m 'fix: REAL fixes for player loading, Offline pill, voice bubble, flicker, warnings'")
print("=" * 60)
