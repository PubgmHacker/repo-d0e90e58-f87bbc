import Foundation
import Combine

// MARK: - DM Chat Service v4 (history + unread badges)
/// Личные сообщения + счётчик непрочитанных для списка «Чаты».
@MainActor
final class DMChatService: ObservableObject {

    /// Shared instance so friends list badges and open chat share state.
    static let shared = DMChatService(api: APIClient.shared)

    @Published private(set) var conversations: [String: [DirectMessage]] = [:]
    @Published private(set) var lastMessages: [Conversation] = []
    /// friendId → unread count (only when user is NOT in that chat)
    @Published private(set) var unreadByFriend: [String: Int] = [:]
    /// friendId → last message preview (for list subtitle)
    @Published private(set) var lastPreviewByFriend: [String: String] = [:]
    /// friendId → last message / activity time (Telegram chat reordering)
    @Published private(set) var lastActivityAtByFriend: [String: Date] = [:]
    /// Bumps when inbox activity changes so chat list can re-sort.
    @Published private(set) var inboxEpoch: Int = 0
    @Published private(set) var historyEpoch: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Currently open DM friend id — unread for this id stays 0 while open.
    private(set) var openFriendId: String?

    private let api: APIClient
    private var unreadPollTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    /// Start aggressive background unread polling (≈1s) for instant badges.
    func startUnreadPolling() {
        guard unreadPollTask == nil else { return }
        unreadPollTask = Task { [weak self] in
            await self?.refreshUnread()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                guard !Task.isCancelled else { break }
                await self?.refreshUnread()
            }
        }
    }

    func stopUnreadPolling() {
        unreadPollTask?.cancel()
        unreadPollTask = nil
    }

    var currentUserId: String? {
        if let id = UserDefaults.standard.string(forKey: "plink_current_user_id"), !id.isEmpty {
            return id
        }
        if let id = AuthService.shared.currentUserValue?.id, !id.isEmpty {
            return id
        }
        return UserDefaults.standard.data(forKey: "rave_saved_user")
            .flatMap { try? JSONDecoder().decode(User.self, from: $0) }?.id
    }

    var totalUnread: Int {
        unreadByFriend.values.reduce(0, +)
    }

    func unreadCount(for friendId: String) -> Int {
        if openFriendId == friendId { return 0 }
        return unreadByFriend[friendId] ?? 0
    }

    func lastActivityAt(for friendId: String) -> Date? {
        lastActivityAtByFriend[friendId]
    }

    private func touchActivity(friendId: String, at date: Date = Date(), preview: String? = nil) {
        var acts = lastActivityAtByFriend
        let prev = acts[friendId]
        if prev == nil || date >= (prev ?? .distantPast) {
            acts[friendId] = date
            lastActivityAtByFriend = acts
            if let preview, !preview.isEmpty {
                lastPreviewByFriend[friendId] = preview
            }
            inboxEpoch &+= 1
        }
    }

    // MARK: - Open / close chat (drives badge zeroing)

    func chatDidOpen(friendId: String) {
        openFriendId = friendId
        // Instant badge clear — don't wait for next poll
        if unreadByFriend[friendId] != nil {
            var next = unreadByFriend
            next.removeValue(forKey: friendId)
            unreadByFriend = next
        }
    }

    func chatDidClose(friendId: String) {
        if openFriendId == friendId {
            openFriendId = nil
        }
        Task { await refreshUnread() }
    }

    // MARK: - Unread summary (GET /messages/unread)

    func refreshUnread() async {
        ensureToken()
        guard api.authToken != nil else { return }
        do {
            let items: [UnreadDTO] = try await api.request("messages/unread")
            var counts: [String: Int] = [:]
            var previews: [String: String] = lastPreviewByFriend
            var activities: [String: Date] = lastActivityAtByFriend
            var activityChanged = false
            for item in items {
                if openFriendId == item.friendId {
                    // Open chat — treat as read optimistically, still track last activity
                } else if item.unreadCount > 0 {
                    counts[item.friendId] = item.unreadCount
                }
                if let p = item.lastPreview, !p.isEmpty {
                    previews[item.friendId] = PlinkBubbleWire.decode(p).text
                }
                if let at = item.lastAt {
                    let prev = activities[item.friendId]
                    if prev == nil || at > (prev ?? .distantPast) {
                        activities[item.friendId] = at
                        activityChanged = true
                    }
                }
            }
            // Only publish if changed — but always update when counts differ for snappy UI
            if counts != unreadByFriend {
                unreadByFriend = counts
            }
            lastPreviewByFriend = previews
            if activityChanged || activities != lastActivityAtByFriend {
                lastActivityAtByFriend = activities
                inboxEpoch &+= 1
            }
        } catch {
            print("[DM] refreshUnread error: \(error.localizedDescription)")
        }
    }

    // MARK: - Load History (GET /api/messages/dm/:friendId)

    func loadHistory(friendId: String, friendName: String, friendAvatarURL: String? = nil, quiet: Bool = false) async {
        ensureToken()
        guard api.authToken != nil else {
            print("[DM] loadHistory: no token")
            return
        }
        let convID = conversationID(with: friendId)
        if !quiet {
            isLoading = true
        }
        defer { if !quiet { isLoading = false } }

        do {
            let dtos: [DMMessageDTO] = try await api.request("messages/dm/\(friendId)")
            // Server marks inbound as read on this GET
            if openFriendId == friendId {
                unreadByFriend[friendId] = nil
                unreadByFriend = unreadByFriend.filter { $0.value > 0 }
            }
            let me = currentUserId ?? ""
            let messages = dtos.map { dto -> DirectMessage in
                let isOwn = !me.isEmpty && dto.senderID == me
                let decoded = PlinkBubbleWire.decode(dto.content)
                let chips = (dto.reactions ?? []).map {
                    DMReactionChip(emoji: $0.emoji, count: $0.count, includesMe: $0.includesMe)
                }
                // Telegram read receipt:
                //  - outbound (I sent): isRead=true means peer opened the chat (✓✓)
                //  - inbound: isRead is for our unread badge; default true once history loaded
                let readFlag: Bool
                if isOwn {
                    readFlag = dto.isRead ?? false
                } else {
                    readFlag = dto.isRead ?? true
                }
                let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                let isVoice = dto.mediaType == "voice" || (dto.hasMedia == true) || voiceMeta.isVoice
                let displayText = voiceMeta.isVoice ? voiceMeta.displayText : decoded.text
                return DirectMessage(
                    id: dto.id,
                    conversationID: convID,
                    senderID: dto.senderID,
                    recipientID: dto.receiverID,
                    senderName: isOwn ? "You" : friendName,
                    text: displayText,
                    timestamp: dto.createdAt,
                    isRead: readFlag,
                    senderAvatarURL: isOwn ? nil : friendAvatarURL,
                    bubbleStyle: decoded.styleID,
                    reactions: chips,
                    mediaType: isVoice ? "voice" : dto.mediaType,
                    mediaDurationSec: dto.mediaDurationSec ?? voiceMeta.durationSec,
                    hasMedia: isVoice || (dto.hasMedia == true)
                )
            }
            // Merge server history with any newer local-only optimistic messages
            // (avoids chat "vanishing" after send if server lags).
            if messages.isEmpty, let existing = conversations[convID], !existing.isEmpty {
                print("[DM] history empty from server — keep \(existing.count) local msgs")
            } else {
                var merged = messages
                if let existing = conversations[convID] {
                    let serverIds = Set(messages.map(\.id))
                    let localsOnly = existing.filter { !serverIds.contains($0.id) && $0.id.count > 20 }
                    // Keep very recent optimistics not yet on server
                    for loc in localsOnly {
                        if !merged.contains(where: { $0.text == loc.text && abs($0.timestamp.timeIntervalSince(loc.timestamp)) < 30 }) {
                            merged.append(loc)
                        }
                    }
                    merged.sort { $0.timestamp < $1.timestamp }
                }
                // Avoid thrashing UI when nothing meaningful changed —
                // MUST include isRead so Telegram ✓ / ✓✓ updates when peer opens chat.
                let prev = conversations[convID] ?? []
                let changed = prev.count != merged.count
                    || zip(prev, merged).contains {
                        $0.id != $1.id
                            || $0.text != $1.text
                            || $0.bubbleStyle != $1.bubbleStyle
                            || $0.reactions != $1.reactions
                            || $0.isRead != $1.isRead
                    }
                if changed {
                    conversations[convID] = merged
                    historyEpoch &+= 1
                }
            }
            if let last = (conversations[convID] ?? messages).last {
                lastPreviewByFriend[friendId] = last.text
                touchActivity(friendId: friendId, at: last.timestamp, preview: last.text)
            }
            print("[DM] history \(conversations[convID]?.count ?? 0) msgs with \(friendId)")
        } catch {
            print("[DM] loadHistory error: \(error.localizedDescription)")
            // Keep existing conversation on error
        }
    }

    func messages(for friendID: String) -> [DirectMessage] {
        let convID = conversationID(with: friendID)
        return conversations[convID] ?? []
    }

    // MARK: - Send voice note (real audio)

    /// Upload recorded AAC/m4a and create a DM voice note.
    /// - Parameters:
    ///   - dataURL: `data:audio/mp4;base64,...`
    ///   - durationSec: measured recording length
    func sendVoiceNote(dataURL: String, durationSec: TimeInterval, to friend: Friend) {
        ensureToken()
        let me = currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? "me"
        if me != "me", UserDefaults.standard.string(forKey: "plink_current_user_id") == nil {
            UserDefaults.standard.set(me, forKey: "plink_current_user_id")
        }

        let convID = conversationID(with: friend.id)
        let localID = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        let dur = max(0.5, min(60, durationSec))
        let voiceBody = PlinkVoiceWire.encode(durationSec: dur)
        let wireContent = PlinkBubbleWire.encode(text: voiceBody, styleID: styleID)
        let preview = PlinkVoiceWire.decode(voiceBody).displayText

        let message = DirectMessage(
            id: localID,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: preview,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            bubbleStyle: styleID,
            reactions: [],
            mediaType: "voice",
            mediaDurationSec: dur,
            hasMedia: true
        )

        var list = conversations[convID] ?? []
        list.append(message)
        conversations[convID] = list
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = "🎤 Голосовое сообщение"
        touchActivity(friendId: friend.id, at: message.timestamp, preview: "🎤 Голосовое сообщение")
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        struct Body: Encodable {
            let receiverId: String
            let audioData: String
            let durationSec: Double
            let content: String
        }

        Task { @MainActor in
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm/voice",
                    method: .post,
                    body: Body(
                        receiverId: friend.id,
                        audioData: dataURL,
                        durationSec: dur,
                        content: wireContent
                    )
                )
                if var cur = conversations[convID],
                   let idx = cur.firstIndex(where: { $0.id == localID }) {
                    let decoded = PlinkBubbleWire.decode(saved.content.isEmpty ? wireContent : saved.content)
                    let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                    cur[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID.isEmpty ? me : saved.senderID,
                        recipientID: saved.receiverID.isEmpty ? friend.id : saved.receiverID,
                        senderName: "You",
                        text: voiceMeta.isVoice ? voiceMeta.displayText : (decoded.text.isEmpty ? preview : decoded.text),
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil,
                        bubbleStyle: decoded.styleID ?? styleID,
                        reactions: [],
                        mediaType: saved.mediaType ?? "voice",
                        mediaDurationSec: saved.mediaDurationSec ?? dur,
                        hasMedia: saved.hasMedia ?? true
                    )
                    conversations[convID] = cur
                    historyEpoch &+= 1
                }
            } catch {
                errorMessage = error.localizedDescription
                print("[DM] sendVoiceNote error: \(error.localizedDescription)")
                // Keep optimistic row so the user sees the attempt
            }
        }
    }

    // MARK: - Send

    func sendMessage(_ text: String, to friend: Friend) {
        // Allow room-invite payloads (up to 280 server-side)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload = String(trimmed.prefix(280))

        ensureToken()
        // Stable id for isOwnMessage + conversation key
        let me = currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? "me"
        if me != "me", UserDefaults.standard.string(forKey: "plink_current_user_id") == nil {
            UserDefaults.standard.set(me, forKey: "plink_current_user_id")
        }

        let convID = conversationID(with: friend.id)
        let localID = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        // Wire style so peer devices render the same bubble (fits in 280 server limit)
        let markerLen = "[[bs:\(BubbleStyleRegistry.migrateLegacyID(styleID))]]".count
        let body = String(payload.prefix(max(1, 280 - markerLen)))
        let wireContent = PlinkBubbleWire.encode(text: body, styleID: styleID)

        let message = DirectMessage(
            id: localID,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: body,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            bubbleStyle: styleID,
            reactions: []
        )

        var list = conversations[convID] ?? []
        list.append(message)
        conversations[convID] = list
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = body
        touchActivity(friendId: friend.id, at: message.timestamp, preview: body)
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        struct Body: Encodable { let receiverId: String; let content: String }
        Task { @MainActor in
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm",
                    method: .post,
                    body: Body(receiverId: friend.id, content: wireContent)
                )
                // Replace optimistic message in-place — do NOT wipe history
                // (full reload was clearing UI / crashing identity updates).
                if var cur = conversations[convID],
                   let idx = cur.firstIndex(where: { $0.id == localID }) {
                    let decoded = PlinkBubbleWire.decode(saved.content.isEmpty ? wireContent : saved.content)
                    cur[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID.isEmpty ? me : saved.senderID,
                        recipientID: saved.receiverID.isEmpty ? friend.id : saved.receiverID,
                        senderName: "You",
                        text: decoded.text.isEmpty ? body : decoded.text,
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil,
                        bubbleStyle: decoded.styleID ?? styleID,
                        reactions: []
                    )
                    conversations[convID] = cur
                    historyEpoch &+= 1
                }
            } catch {
                errorMessage = error.localizedDescription
                print("[DM] sendMessage error: \(error.localizedDescription)")
                // Keep optimistic message visible so chat does not "disappear"
            }
        }
    }

    func receiveMessage(_ message: DirectMessage, from friend: Friend) {
        let convID = conversationID(with: friend.id)
        if conversations[convID] == nil { conversations[convID] = [] }
        if conversations[convID]?.contains(where: { $0.id == message.id }) == true { return }
        let decoded = PlinkBubbleWire.decode(message.text)
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
        )
        conversations[convID]?.append(normalized)
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = normalized.text
        touchActivity(friendId: friend.id, at: normalized.timestamp, preview: normalized.text)
        updateLastMessage(conversationID: convID, friend: friend, message: normalized)
        if openFriendId != friend.id, normalized.senderID != currentUserId {
            unreadByFriend[friend.id, default: 0] += 1
        }
    }

    // MARK: - Reactions (Telegram-style)

    /// Toggle reaction on a message. Same emoji again removes; other replaces.
    func toggleReaction(emoji: String, on message: DirectMessage, friendId: String) async {
        // Optimistic local update
        applyOptimisticReaction(emoji: emoji, messageId: message.id, friendId: friendId)
        ensureToken()
        struct Body: Encodable { let emoji: String }
        struct Resp: Decodable {
            let success: Bool?
            let reactions: [ReactionDTO]?
        }
        do {
            let resp: Resp = try await api.request(
                "messages/dm/\(message.id)/react",
                method: .post,
                body: Body(emoji: emoji)
            )
            if let chips = resp.reactions {
                setReactions(
                    chips.map { DMReactionChip(emoji: $0.emoji, count: $0.count, includesMe: $0.includesMe) },
                    messageId: message.id,
                    friendId: friendId
                )
            }
        } catch {
            print("[DM] react error: \(error.localizedDescription)")
            // Soft-fail: keep optimistic state; next history poll reconciles
        }
    }

    private func applyOptimisticReaction(emoji: String, messageId: String, friendId: String) {
        let convID = conversationID(with: friendId)
        guard var list = conversations[convID],
              let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        var chips = list[idx].reactions
        if let i = chips.firstIndex(where: { $0.emoji == emoji && $0.includesMe }) {
            // Toggle off
            let c = chips[i]
            if c.count <= 1 {
                chips.remove(at: i)
            } else {
                chips[i] = DMReactionChip(emoji: emoji, count: c.count - 1, includesMe: false)
            }
        } else {
            // Remove previous own reaction on other emoji
            chips = chips.compactMap { chip in
                if chip.includesMe {
                    if chip.count <= 1 { return nil }
                    return DMReactionChip(emoji: chip.emoji, count: chip.count - 1, includesMe: false)
                }
                return chip
            }
            if let i = chips.firstIndex(where: { $0.emoji == emoji }) {
                let c = chips[i]
                chips[i] = DMReactionChip(emoji: emoji, count: c.count + 1, includesMe: true)
            } else {
                chips.append(DMReactionChip(emoji: emoji, count: 1, includesMe: true))
            }
        }
        chips.sort { $0.count > $1.count }
        list[idx].reactions = chips
        conversations[convID] = list
        historyEpoch &+= 1
    }

    private func setReactions(_ chips: [DMReactionChip], messageId: String, friendId: String) {
        let convID = conversationID(with: friendId)
        guard var list = conversations[convID],
              let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        list[idx].reactions = chips
        conversations[convID] = list
        historyEpoch &+= 1
    }

    // MARK: - Helpers

    func conversationID(with friendID: String) -> String {
        let me = currentUserId ?? "me"
        let ids = [me, friendID].sorted()
        return "dm_\(ids.joined(separator: "_"))"
    }

    private func ensureToken() {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
    }

    private func updateLastMessage(conversationID: String, friend: Friend, message: DirectMessage) {
        let conv = Conversation(
            id: conversationID,
            participant: UserPreview(id: friend.id, username: friend.username, avatarURL: friend.avatarURL, isOnline: friend.isOnline),
            lastMessage: message,
            unreadCount: unreadCount(for: friend.id),
            updatedAt: message.timestamp
        )
        lastMessages.removeAll { $0.id == conversationID }
        lastMessages.insert(conv, at: 0)
    }
}

// MARK: - DTOs

private struct UnreadDTO: Decodable {
    let friendId: String
    let unreadCount: Int
    let lastPreview: String?
    let lastAt: Date?
}

private struct ReactionDTO: Decodable {
    let emoji: String
    let count: Int
    let includesMe: Bool
}

private struct DMMessageDTO: Decodable {
    let id: String
    let senderID: String
    let receiverID: String
    let content: String
    let createdAt: Date
    let isRead: Bool?
    let reactions: [ReactionDTO]?
    let mediaType: String?
    let mediaDurationSec: Double?
    let hasMedia: Bool?

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, isRead, reactions
        case senderID, receiverID
        case senderId, receiverId
        case mediaType, mediaDurationSec, hasMedia
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead)
        reactions = try c.decodeIfPresent([ReactionDTO].self, forKey: .reactions)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        mediaDurationSec = try c.decodeIfPresent(Double.self, forKey: .mediaDurationSec)
        hasMedia = try c.decodeIfPresent(Bool.self, forKey: .hasMedia)
        if let s = try c.decodeIfPresent(String.self, forKey: .senderID) {
            senderID = s
        } else {
            senderID = try c.decode(String.self, forKey: .senderId)
        }
        if let r = try c.decodeIfPresent(String.self, forKey: .receiverID) {
            receiverID = r
        } else {
            receiverID = try c.decode(String.self, forKey: .receiverId)
        }
    }
}
