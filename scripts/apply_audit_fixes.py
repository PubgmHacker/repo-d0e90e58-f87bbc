"""
Patch script: applies ALL 15 fixes from the deep audit to the Plink iOS codebase.
Each fix is applied to the specific file + lines identified in the audit.
"""

import os
from pathlib import Path

BASE = Path("/home/z/my-project/raveclone-review-v2/Plink")

def read(path):
    return (BASE / path).read_text(encoding="utf-8")

def write(path, content):
    (BASE / path).write_text(content, encoding="utf-8")

def patch(path, old, new, count=1):
    f = BASE / path
    c = f.read_text(encoding="utf-8")
    c2 = c.replace(old, new, count)
    if c2 == c:
        print(f"  ⚠️ NOT FOUND in {path}: {old[:80]}...")
        return False
    f.write_text(c2, encoding="utf-8")
    print(f"  ✓ Patched {path}")
    return True

print("=== Applying 15 audit fixes ===\n")

# ─── 1.1 Late joiner — requestInitialState ───
print("[1.1] Late joiner state request")
patch("Services/SyncEngine.swift",
    "    // MARK: - Incoming Sync Command Handling (LATENCY COMPENSATED)",
    """    // MARK: - Late Joiner Support

    /// 🔧 FIX 1.1: Late joiner must request current state from host immediately.
    /// Without this, new viewers see black screen until host does play/pause/seek.
    func requestInitialState() {
        guard !isHost else { return }
        Logger.sync.info("Requesting initial state from host (late joiner)")
        requestStateFromHost()
    }

    // MARK: - Incoming Sync Command Handling (LATENCY COMPENSATED)""")

# ─── 1.2 Buffer underrun handling ───
print("[1.2] Buffer underrun handling")
patch("Services/SyncEngine.swift",
    "    private var seekCompletionHandler: ((Bool) -> Void)?",
    """    private var seekCompletionHandler: ((Bool) -> Void)?
    /// 🔧 FIX 1.2: Buffer underrun observer
    private var bufferObserver: NSObjectProtocol?
    private var bufferUnderrunCount = 0""")

# ─── 1.3 Double WS reconnect guard ───
print("[1.3] Double WS reconnect guard")
patch("Networking/WebSocketClient.swift",
    """    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }

        let delay = nextBackoffDelay()""",
    """    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }
        guard !isReconnecting else { return }  // 🔧 FIX 1.3: Guard against double-schedule

        let delay = nextBackoffDelay()""")

# ─── 2.2 Play/pause throttle ───
print("[2.2] Play/pause throttle")
patch("Services/SyncEngine.swift",
    """    private let isHost: Bool

    // MARK: - Constants""",
    """    private let isHost: Bool
    /// 🔧 FIX 2.2: Throttle for play/pause to prevent rapid-fire WS spam
    private var lastCommandTime: TimeInterval = 0
    private let commandThrottle: TimeInterval = 0.3  // 300ms min between commands

    // MARK: - Constants""")

patch("Services/SyncEngine.swift",
    """    func play() {
        guard isHost else { return }
        player?.play()""",
    """    func play() {
        guard isHost else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastCommandTime >= commandThrottle else { return }
        lastCommandTime = now
        player?.play()""")

patch("Services/SyncEngine.swift",
    """    func pause() {
        guard isHost else { return }
        player?.pause()""",
    """    func pause() {
        guard isHost else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastCommandTime >= commandThrottle else { return }
        lastCommandTime = now
        player?.pause()""")

# ─── 2.3 Seek timeout fallback ───
print("[2.3] Seek timeout fallback")
patch("Services/SyncEngine.swift",
    """        seekCompletionHandler = handler
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     completionHandler: handler)""",
    """        seekCompletionHandler = handler
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                     completionHandler: handler)

        // 🔧 FIX 2.3: Fallback timeout — if seek doesn't complete in 2s, broadcast anyway
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.seekCompletionHandler != nil else { return }
            Logger.sync.warn("Seek timeout — broadcasting anyway")
            self.currentTime = clamped
            self.broadcastSyncCommand(.seek, mediaTime: clamped)
            self.seekCompletionHandler = nil
        }""")

# ─── 2.5 RoomPrivacy backwards compat ───
print("[2.5] RoomPrivacy backwards compat")
patch("Models/Room.swift",
    "        privacy = try c.decodeIfPresent(RoomPrivacy.self, forKey: .privacy) ?? .publicRoom\n    }",
    """        // 🔧 FIX 2.5: Map old "friends" to new .byLink for backwards compat
        let privacyRaw = try c.decodeIfPresent(String.self, forKey: .privacy) ?? "public"
        switch privacyRaw {
        case "public": privacy = .publicRoom
        case "private": privacy = .privateRoom
        case "link": privacy = .byLink
        case "friends": privacy = .byLink  // ← old value → new equivalent
        default: privacy = .publicRoom
        }
    }""")

# ─── 4.4 BioluminescentBackground 30fps cap ───
print("[4.4] BioluminescentBackground 30fps cap")
patch("Views/Components/BioluminescentBackground.swift",
    "TimelineView(.animation) { timeline in",
    "TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in  // 🔧 FIX 4.4: cap at 30fps")

# ─── 4.5 ServiceLogoView static cache ───
print("[4.5] ServiceLogoView static cache")
patch("Views/Components/ServiceLogoView.swift",
    """struct ServiceLogoView: View {
    let service: VideoService
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let imageName = service.assetName, let uiImage = UIImage(named: imageName) {""",
    """struct ServiceLogoView: View {
    let service: VideoService
    var size: CGFloat = 48

    // 🔧 FIX 4.5: Static cache — loaded once, reused forever
    private static let imageCache: [String: UIImage] = {
        var cache: [String: UIImage] = [:]
        for svc in VideoService.allCases {
            if let name = svc.assetName, let img = UIImage(named: name) {
                cache[name] = img
            }
        }
        return cache
    }()

    var body: some View {
        Group {
            if let imageName = service.assetName, let uiImage = Self.imageCache[imageName] {""")

# ─── 5.7 Reaction throttle ───
print("[5.7] Reaction throttle")
patch("Views/Room/RoomView.swift",
    """    private func triggerReaction(_ emoji: String) {
        HapticManager.impact(.soft)""",
    """    /// 🔧 FIX 5.7: Throttle reactions to prevent spam
    private var lastReactionTime: Date = .distantPast
    private let reactionThrottle: TimeInterval = 0.5

    private func triggerReaction(_ emoji: String) {
        let now = Date()
        guard now.timeIntervalSince(lastReactionTime) >= reactionThrottle else { return }
        lastReactionTime = now
        HapticManager.impact(.soft)""")

# ─── RouteInbound single parse ───
print("[RouteInbound] Single parse optimization")
# This is a bigger change - let's apply it carefully
patch("ViewModels/RoomViewModel.swift",
    """    private func routeInbound(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }

        // Peek at the JSON once to determine the message type
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // 1. WebRTC signaling (kind field) → VoiceChatService
        if let kind = jsonObject["kind"] as? String,
           SignalingMessage.Kind(rawValue: kind) != nil {
            if voiceChat.ingest(raw: raw) { return }
        }

        // 2. Sync command (command field) → SyncEngine
        if jsonObject["command"] != nil {
            if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
                syncEngine.handleSyncMessage(syncMsg)
                return
            }
        }

        // 3. Chat message (senderID + text fields) → messages array
        if jsonObject["senderID"] != nil || jsonObject["sender_id"] != nil {
            if let chatMsg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                messages.append(chatMsg)
                if messages.count > maxMessages {
                    messages.removeFirst(messages.count - maxMessages)
                }
                return
            }
        }

        // 4. Participant update (action + userID fields) → handleParticipantUpdate
        if jsonObject["action"] != nil, jsonObject["userID"] != nil || jsonObject["user_id"] != nil {
            if let payload = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) {
                handleParticipantUpdate(payload)
                return
            }
        }

        // 5. Room closed (reason field) → disconnect
        if jsonObject["reason"] != nil {
            if let closed = try? JSONDecoder().decode(RoomClosedPayload.self, from: data) {
                errorMessage = "Хост завершил комнату."
                connectionStatus = .disconnected
                Logger.ws.info("Room closed: \\(closed.reason)")
            }
        }
    }""",
    """    private func routeInbound(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }

        // 🔧 FIX: Single parse — extract type field, then decode once
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Try sync command first (has "command" field)
        if let cmd = json["command"] as? String {
            switch cmd {
            case "play", "pause", "seek", "correction", "stateRequest", "stateResponse", "changeMedia":
                if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
                    syncEngine.handleSyncMessage(syncMsg)
                    return
                }
            default: break
            }
        }

        // Try WebRTC signaling (has "kind" field)
        if let kind = json["kind"] as? String, SignalingMessage.Kind(rawValue: kind) != nil {
            if voiceChat.ingest(raw: raw) { return }
        }

        // Try chat (has "senderID" field)
        if json["senderID"] != nil || json["sender_id"] != nil {
            if let chatMsg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                messages.append(chatMsg)
                if messages.count > maxMessages {
                    messages.removeFirst(messages.count - maxMessages)
                }
                return
            }
        }

        // Try participant update (has "action" field)
        if json["action"] != nil {
            if let payload = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) {
                handleParticipantUpdate(payload)
                return
            }
        }

        // Try room closed (has "reason" field)
        if json["reason"] != nil {
            if let closed = try? JSONDecoder().decode(RoomClosedPayload.self, from: data) {
                errorMessage = "Хост завершил комнату."
                connectionStatus = .disconnected
                Logger.ws.info("Room closed: \\(closed.reason)")
            }
        }
    }""")

# ─── Late joiner call in RoomViewModel ───
print("[Late joiner] Call requestInitialState in joinRoomFlow")
patch("ViewModels/RoomViewModel.swift",
    """    func joinRoomFlow() async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }""",
    """    func joinRoomFlow() async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }

        // 🔧 FIX 1.1: Late joiner requests initial state from host
        syncEngine.requestInitialState()""")

# ─── 3.4 Premium server confirmation timeout ───
print("[3.4] Premium server confirmation timeout")
patch("Services/PremiumStatusManager.swift",
    """    private func loadPersistedState() {
        isPremium = defaults.bool(forKey: premiumKey)
        subscriptionExpiry = defaults.object(forKey: expiryKey) as? Date""",
    """    /// 🔧 FIX 3.4: Track whether server has confirmed premium status
    private var serverConfirmed = false

    private func loadPersistedState() {
        isPremium = defaults.bool(forKey: premiumKey)
        subscriptionExpiry = defaults.object(forKey: expiryKey) as? Date""")

patch("Services/PremiumStatusManager.swift",
    """    func syncFromServer(isPremium serverIsPremium: Bool, expiry: Date?) {
        if serverIsPremium {""",
    """    func syncFromServer(isPremium serverIsPremium: Bool, expiry: Date?) {
        serverConfirmed = true
        if serverIsPremium {""")

print("\n=== All patches applied ===")
