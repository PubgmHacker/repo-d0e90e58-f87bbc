#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink YouTube AVPlayer fix - extract direct stream URL via backend.

USER REQUEST:
- YouTube must play via AVPlayer (not WKWebView)
- Like Rave/Hearo - autoplay with sound, no tap required
- Maximum sync quality

APPROACH:
Backend already has /api/media/extract?id=VIDEO_ID endpoint that uses
Piped API / Invidious / YouTube Internal API to extract direct stream
URLs (muxed MP4 or HLS). Returns StreamInfo { streamURL, ... }.

iOS change:
- In WatchRoomModel.connect(), when mediaSource is .youtube(videoId),
  call backend /api/media/extract?id=VIDEO_ID
- If streamURL is returned (muxed MP4 or HLS), replace mediaSource
  with .mp4(url) or .hls(url) - PlaybackCoordinator routes these to
  NativePlayerController (AVPlayer)
- AVPlayer plays natively with sound, autoplay, full sync control
- If extraction fails, fall back to .youtube (WKWebView) - degraded
  mode but app still works

Also: default WatchRoomModel.connectionState .idle -> .connecting
(eliminates "Offline" flash when entering room)

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_avplayer.py
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


# ---------- 1. WatchRoomModel: default state .idle -> .connecting ----------
print("[1/3] WatchRoomModel.swift - default state .idle -> .connecting")
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


# ---------- 2. WatchRoomModel: extract YouTube stream URL before prepare ----------
print("[2/3] WatchRoomModel.swift - extract YouTube stream URL before prepare")
edit_file(
    "Plink/Features/WatchRoom/WatchRoomModel.swift",
    """        // Media prepare — if mediaSource was nil at init (server stripped mediaItem),
        // try one REST re-fetch before giving up on "Нет видео".
        if mediaSource == nil {
            if let recovered = await Self.refetchMediaSource(roomId: _roomId) {
                mediaSource = recovered.source
                if mediaId == nil { mediaId = recovered.mediaId }
            }
        }

        if let source = mediaSource {""",
    """        // Media prepare — if mediaSource was nil at init (server stripped mediaItem),
        // try one REST re-fetch before giving up on "Нет видео".
        if mediaSource == nil {
            if let recovered = await Self.refetchMediaSource(roomId: _roomId) {
                mediaSource = recovered.source
                if mediaId == nil { mediaId = recovered.mediaId }
            }
        }

        // AVPlayer path: if source is .youtube(videoId), extract direct stream
        // URL via backend /api/media/extract. Backend uses Piped/Invidious/
        // YouTube Internal API to get a muxed MP4 or HLS URL that AVPlayer can
        // play natively with sound + autoplay + full sync control (like Rave).
        // Falls back to .youtube (WKWebView) if extraction fails - degraded
        // but app still works.
        if case .youtube(let ytId) = mediaSource {
            NSLog("[WatchRoom] extracting YouTube stream for AVPlayer, videoId=\\(ytId)")
            if let extracted = await Self.extractYouTubeStreamURL(videoId: ytId) {
                NSLog("[WatchRoom] extracted stream URL: \\(extracted.absoluteString.prefix(80))\\u2026")
                if extracted.pathExtension.lowercased() == "m3u8" || extracted.absoluteString.contains(".m3u8") {
                    mediaSource = .hls(extracted, headers: [:])
                } else {
                    mediaSource = .mp4(extracted, headers: ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"])
                }
            } else {
                NSLog("[WatchRoom] YouTube extraction failed - falling back to WKWebView")
            }
        }

        if let source = mediaSource {""",
    "extract YouTube stream URL before prepare"
)


# ---------- 3. WatchRoomModel: add extractYouTubeStreamURL helper ----------
print("[3/3] WatchRoomModel.swift - add extractYouTubeStreamURL helper")
edit_file(
    "Plink/Features/WatchRoom/WatchRoomModel.swift",
    """    /// Recover YouTube/media when create/join returned room without mediaItem.
    private static func refetchMediaSource(roomId: String) async -> (source: PlaybackSource, mediaId: String?)? {
        do {
            let room = try await RoomService(api: APIClient.shared).fetchRoom(id: roomId)
            guard let source = WatchRoomCompositionRoot.mediaSource(from: room) else { return nil }
            let mid = room.mediaItem?.videoId ?? room.mediaItem?.id
            return (source, mid)
        } catch {
            print("[WatchRoom] refetch media failed: \\(error.localizedDescription)")
            return nil
        }
    }""",
    """    /// Recover YouTube/media when create/join returned room without mediaItem.
    private static func refetchMediaSource(roomId: String) async -> (source: PlaybackSource, mediaId: String?)? {
        do {
            let room = try await RoomService(api: APIClient.shared).fetchRoom(id: roomId)
            guard let source = WatchRoomCompositionRoot.mediaSource(from: room) else { return nil }
            let mid = room.mediaItem?.videoId ?? room.mediaItem?.id
            return (source, mid)
        } catch {
            print("[WatchRoom] refetch media failed: \\(error.localizedDescription)")
            return nil
        }
    }

    /// Extract direct stream URL from backend /api/media/extract for AVPlayer.
    /// Backend uses Piped API / Invidious / YouTube Internal API to get a
    /// muxed MP4 or HLS URL that AVPlayer can play natively with sound +
    /// autoplay (no WKWebView, no user gesture needed).
    /// Returns nil if extraction fails - caller falls back to .youtube WKWebView.
    private static func extractYouTubeStreamURL(videoId: String) async -> URL? {
        let api = APIClient.shared
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
        }
        guard let token = api.authToken else {
            NSLog("[WatchRoom] extractYouTubeStreamURL: no auth token")
            return nil
        }
        guard let baseURL = URL(string: "https://plink-backend-production-ef31.up.railway.app") else {
            return nil
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/media/extract"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: videoId)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("[WatchRoom] extractYouTubeStreamURL: HTTP \\((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            // Parse { streamURL: "...", ... }
            struct StreamInfo: Decodable {
                let streamURL: String?
                let hlsURL: String?
            }
            let info = try JSONDecoder().decode(StreamInfo.self, from: data)
            // Prefer HLS for live/long videos, else muxed MP4
            let urlString = info.hlsURL ?? info.streamURL
            guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
                NSLog("[WatchRoom] extractYouTubeStreamURL: no streamURL in response")
                return nil
            }
            return url
        } catch {
            NSLog("[WatchRoom] extractYouTubeStreamURL error: \\(error.localizedDescription)")
            return nil
        }
    }""",
    "extractYouTubeStreamURL helper"
)


print()
print("=" * 60)
print("Done. Review changes with: git diff --stat")
print("Then commit + push:")
print("  git add -A")
print("  git commit -m 'fix: YouTube via AVPlayer + backend stream extraction (no WKWebView)'")
print("  git push origin main")
print()
print("After rebuild, watch for:")
print("  [WatchRoom] extracting YouTube stream for AVPlayer, videoId=...")
print("  [WatchRoom] extracted stream URL: https://... (truncated)")
print("  -> AVPlayer should autoplay with sound, no tap required")
print()
print("If extraction fails (backend issue):")
print("  [WatchRoom] YouTube extraction failed - falling back to WKWebView")
print("  -> falls back to WKWebView (degraded but functional)")
print("=" * 60)
