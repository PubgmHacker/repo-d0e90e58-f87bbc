#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink diagnostics + flicker fix (round 2).

This patch addresses what round 1 missed:

1. FLICKER ROOT CAUSE — DM polling loop in DMChatView.swift
   Every 1.5s the loop calls loadHistory(quiet: false). `quiet: false`
   BYPASSES the change-detection in loadHistory, forcing `conversations`
   to be replaced and `historyEpoch` to bump on EVERY poll — even when
   nothing changed. SwiftUI re-renders the entire message list, which
   re-evaluates the contextMenu preview during long-press → flicker.
   FIX: change `quiet: false` -> `quiet: true` (use change detection),
   increase interval from 1.5s -> 3s.

2. PLAYER OFFLINE - diagnostic logging
   The previous "Offline" pill fix only kicks in for transient states.
   If the user still sees bare "Offline", connectionState is .idle or
   .failed — meaning the WebSocket never reached .connected. We need
   logs to see WHY. Add NSLog calls to:
   - RealtimeClient.setState (log every state transition)
   - RealtimeClient.openConnection (log ticket + URL)
   - WatchRoomModel.connect (log mediaSource + roomId)
   - EmbeddedPlaybackController.prepare (log YouTube URL + ready state)

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_diag.py
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


# --------- 1. FLICKER FIX: DM polling loop ----------
print("[1/4] DMChatView.swift - fix polling flicker (quiet:false -> true, 1.5s -> 3s)")
edit_file(
    "Plink/Views/Chat/DMChatView.swift",
    """            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { break }
                await friendManager.loadFriends()
                // quiet:false every poll so server newest messages always win
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: liveFriend.displayTitle,
                    friendAvatarURL: liveFriend.avatarURL,
                    quiet: false
                )
            }""",
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
    "DM polling loop"
)


# ---------- 2. REALTIME CLIENT - log every state transition ----------
print("[2/4] RealtimeClient.swift - log state transitions + connection flow")
edit_file(
    "Plink/Realtime/RealtimeClient.swift",
    """    private func setState(_ newState: RealtimeConnectionState) {
        state = newState""",
    """    private func setState(_ newState: RealtimeConnectionState) {
        NSLog("[Realtime] state: \\(newState)")
        state = newState""",
    "setState logging"
)
edit_file(
    "Plink/Realtime/RealtimeClient.swift",
    """    private func openConnection() async {
        guard let roomId = currentRoomId else {
            setState(.failed(reason: "No roomId"))
            return
        }""",
    """    private func openConnection() async {
        guard let roomId = currentRoomId else {
            setState(.failed(reason: "No roomId"))
            return
        }
        NSLog("[Realtime] openConnection roomId=\\(roomId)")""",
    "openConnection logging"
)
edit_file(
    "Plink/Realtime/RealtimeClient.swift",
    """        let ticket: RealtimeTicket
        do {
            ticket = try await ticketProvider(roomId)
        } catch {
            if gen == generation { setState(.failed(reason: "Ticket error: \\(error.localizedDescription)")) }
            return
        }""",
    """        let ticket: RealtimeTicket
        do {
            ticket = try await ticketProvider(roomId)
            NSLog("[Realtime] ticket OK roomId=\\(ticket.roomId) expiresIn=\\(ticket.expiresInSec)s")
        } catch {
            NSLog("[Realtime] ticket FAIL: \\(error.localizedDescription)")
            if gen == generation { setState(.failed(reason: "Ticket error: \\(error.localizedDescription)")) }
            return
        }""",
    "ticket logging"
)
edit_file(
    "Plink/Realtime/RealtimeClient.swift",
    """        var request = URLRequest(url: url)
        request.setValue("plink.v2, plink.ticket.\\(ticket.jwt)", forHTTPHeaderField: "Sec-WebSocket-Protocol")""",
    """        var request = URLRequest(url: url)
        request.setValue("plink.v2, plink.ticket.\\(ticket.jwt)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        NSLog("[Realtime] WS url=\\(url.absoluteString)")""",
    "WS URL logging"
)
edit_file(
    "Plink/Realtime/RealtimeClient.swift",
    """    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
        let transient = [57, 60, 54, -1005, -1009, -1001].contains(nsError.code)
        if transient {
            beginReconnect(cause: "receive error: \\(nsError.localizedDescription)")
        } else {
            setState(.failed(reason: nsError.localizedDescription))
        }
    }""",
    """    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
        NSLog("[Realtime] receive error code=\\(nsError.code) domain=\\(nsError.domain) desc=\\(nsError.localizedDescription)")
        let transient = [57, 60, 54, -1005, -1009, -1001].contains(nsError.code)
        if transient {
            beginReconnect(cause: "receive error: \\(nsError.localizedDescription)")
        } else {
            setState(.failed(reason: nsError.localizedDescription))
        }
    }""",
    "handleReceiveError logging"
)


# ---------- 3. WATCHROOM MODEL - log connect + mediaSource ----------
print("[3/4] WatchRoomModel.swift - log connect flow")
edit_file(
    "Plink/Features/WatchRoom/WatchRoomModel.swift",
    """    public func connect() async {
        wantsDismiss = false
        connectionState = .connecting""",
    """    public func connect() async {
        wantsDismiss = false
        connectionState = .connecting
        NSLog("[WatchRoom] connect roomId=\\(_roomId) mediaSource=\\(String(describing: mediaSource)) mediaId=\\(String(describing: mediaId))")""",
    "WatchRoomModel.connect logging"
)


# ---------- 4. EMBEDDED PLAYBACK - log YouTube URL load ----------
print("[4/4] EmbeddedPlaybackController.swift - log YouTube prepare flow")
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            throw ProviderError.unsupportedSource
        }
        guard Self.isValidVideoId(id) else {
            throw ProviderError.loadingFailed("Invalid YouTube video ID")
        }""",
    """    public func prepare(_ source: PlaybackSource) async throws {
        guard case .youtube(let id) = source else {
            NSLog("[YT] prepare rejected: not a youtube source")
            throw ProviderError.unsupportedSource
        }
        guard Self.isValidVideoId(id) else {
            NSLog("[YT] prepare rejected: invalid videoId=\\(id)")
            throw ProviderError.loadingFailed("Invalid YouTube video ID")
        }
        NSLog("[YT] prepare start videoId=\\(id)")""",
    "prepare logging"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """        guard let wrapperURL = components.url else {
            throw ProviderError.loadingFailed("Invalid wrapper URL")
        }""",
    """        guard let wrapperURL = components.url else {
            NSLog("[YT] wrapper URL invalid")
            throw ProviderError.loadingFailed("Invalid wrapper URL")
        }
        NSLog("[YT] loading wrapper URL=\\(wrapperURL.absoluteString)")""",
    "wrapper URL logging"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """        if !isReady {
            // Keep webview visible; stop covering it with a full-screen spinner.
            // YouTube chrome may still become interactive.
            isBuffering = false
            lastError = nil
        }

        startPolling()""",
    """        if !isReady {
            NSLog("[YT] prepare timeout - YouTube IFrame API never signaled ready")
            // Keep webview visible; stop covering it with a full-screen spinner.
            // YouTube chrome may still become interactive.
            isBuffering = false
            lastError = nil
        } else {
            NSLog("[YT] prepare OK - ready=true")
        }

        startPolling()""",
    "prepare result logging"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    private func handleReady() {
        guard !isReady else { return }
        isReady = true
        isBuffering = false""",
    """    private func handleReady() {
        guard !isReady else { return }
        NSLog("[YT] handleReady - YouTube IFrame API ready")
        isReady = true
        isBuffering = false""",
    "handleReady logging"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """    private func handleError(code: Int) {
        // Brain §5.1: map official YouTube IFrame API error codes.
        // https://developers.google.com/youtube/iframe_api_reference#onError
        let message: String
        switch code {""",
    """    private func handleError(code: Int) {
        NSLog("[YT] handleError code=\\(code)")
        // Brain §5.1: map official YouTube IFrame API error codes.
        // https://developers.google.com/youtube/iframe_api_reference#onError
        let message: String
        switch code {""",
    "handleError logging"
)
edit_file(
    "Plink/Playback/EmbeddedPlaybackController.swift",
    """        let nav = YTWebNavigationDelegate { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.pageDidFinishLoad = true
                } else {
                    self.lastError = err ?? "Не удалось загрузить страницу плеера"
                    self.isBuffering = false
                }
            }
        }""",
    """        let nav = YTWebNavigationDelegate { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    NSLog("[YT] navigation didFinish")
                    self.pageDidFinishLoad = true
                } else {
                    NSLog("[YT] navigation FAIL: \\(err ?? "unknown")")
                    self.lastError = err ?? "navigation failed"
                    self.isBuffering = false
                }
            }
        }""",
    "navigation delegate logging"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit + push:")
print("  git add -A")
print("  git commit -m 'fix: DM flicker (quiet:true polling) + diagnostic logs for player offline'")
print("  git push origin main")
print()
print("After rebuild + run, watch the Xcode console for [Realtime], [WatchRoom], [YT] logs.")
print("Send me the logs from room creation -> player load - they will show exactly where it fails.")
print("=" * 60)
