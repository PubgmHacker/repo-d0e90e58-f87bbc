import SwiftUI

// MARK: - DM Chat View v7 — Telegram glassmorphism + reactions

struct DMChatView: View {
    @EnvironmentObject private var dmService: DMChatService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friendManager = FriendManager.shared

    let friend: Friend
    @State private var messageText = ""
    @State private var showEmojiPicker = false
    @State private var showWatchTogether = false
    @State private var showPeerProfile = false
    @State private var showChatActions = false
    @State private var confirmDeleteChat = false
    @State private var confirmBlockUser = false
    @State private var reactionTarget: DirectMessage?
    @FocusState private var isInputFocused: Bool
    private let charLimit = 280
    @State private var lastSendTime: Date = .distantPast
    @State private var wallpaper = PlinkChatWallpaperPrefs.current
    @State private var voiceRecorder = VoiceNoteRecorder()
    @State private var voiceError: String?
    @State private var voiceStartInFlight = false
    @ObservedObject private var blockManager = UserBlockManager.shared

    /// Telegram iOS 2026 private-chat navigation metrics.
    private enum TGHeader {
        /// Avatar sits on the right (Telegram 2025–26 chat header)
        static let avatar: CGFloat = 40
        static let barHeight: CGFloat = 52
        static let nameSize: CGFloat = 16
        static let statusSize: CGFloat = 12
        /// Classic Telegram “online” green
        static let online = Color(red: 0.20, green: 0.78, blue: 0.35)
    }

    private var chatsUnreadBadge: Int {
        max(0, dmService.totalUnread - dmService.unreadCount(for: friend.id))
    }

    private var headerPresence: String {
        FriendPresence.headerStatus(
            isOnline: liveFriend.isOnline,
            lastSeenAt: liveFriend.lastSeenAt
        )
    }

    private var headerIsOnline: Bool {
        if liveFriend.deleted { return false }
        return liveFriend.isOnline || headerPresence == "в сети"
    }

    /// Live friend snapshot (avatarURL updates when they change photo).
    private var liveFriend: Friend {
        friendManager.friends.first(where: { $0.id == friend.id }) ?? friend
    }

    private var peerAvatarURL: URL? {
        // Touch epoch so Observation / ObservedObject refresh re-renders avatar
        _ = friendManager.avatarEpoch
        // Uses per-user ?v= so a friend photo update reloads without flicker thrash
        return PlinkAvatarURL.stable(userId: liveFriend.id, stored: liveFriend.avatarURL)
    }

    private var peerLetter: String {
        PlinkAvatarURL.letter(from: liveFriend.displayTitle)
    }

    private var meId: String {
        dmService.currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? ""
    }

    private var meLetter: String {
        let name = UserDefaults.standard.string(forKey: "plink_current_display_name")
            ?? UserDefaults.standard.string(forKey: "plink_current_username")
            ?? "?"
        return PlinkAvatarURL.letter(from: name)
    }

    private var meAvatarURL: URL? {
        PlinkAvatarURL.stable(userId: meId.isEmpty ? nil : meId, stored: nil)
    }

    private var messages: [DirectMessage] {
        dmService.messages(for: friend.id)
    }

    var body: some View {
        ZStack {
            wallpaper.background

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            DMDayDivider(label: "Сегодня")

                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                                let own = msg.isFromCurrentUser(currentUserId: meId)
                                let prevId = index > 0 ? messages[index - 1].senderID : nil
                                let nextId = index + 1 < messages.count ? messages[index + 1].senderID : nil
                                let cluster = ChatClusterLayout.compute(
                                    senderId: msg.senderID,
                                    previousSenderId: prevId,
                                    nextSenderId: nextId,
                                    isOwn: own
                                )
                                DMBubble(
                                    message: msg,
                                    isOwn: own,
                                    avatarURL: own ? meAvatarURL : peerAvatarURL,
                                    letter: own ? meLetter : peerLetter,
                                    cluster: cluster,
                                    onReact: { reactionTarget = msg },
                                    onToggleChip: { emoji in
                                        Task {
                                            await dmService.toggleReaction(
                                                emoji: emoji,
                                                on: msg,
                                                friendId: friend.id
                                            )
                                        }
                                    }
                                )
                                .id(msg.id)
                                .padding(.horizontal, 10)
                                .padding(.top, cluster.topPadding)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                // Swipe down to hide keyboard (Telegram-like)
                                if value.translation.height > 40 {
                                    isInputFocused = false
                                    showEmojiPicker = false
                                }
                            }
                    )
                    .onChange(of: dmService.historyEpoch) { _, _ in
                        DispatchQueue.main.async { scrollToBottom(proxy: proxy) }
                    }
                    .onChange(of: messages.count) { oldCount, newCount in
                        guard newCount > oldCount else { return }
                        DispatchQueue.main.async { scrollToBottom(proxy: proxy) }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }

                if showEmojiPicker {
                    EmojiPickerGrid(chatText: $messageText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .background(.ultraThinMaterial)
                }

                glassInputBar
            }
        }
        // Telegram: fixed top bar over chat (safe-area aware)
        .safeAreaInset(edge: .top, spacing: 0) {
            telegramNavBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showWatchTogether) {
            RoomCreationView { room in
                showWatchTogether = false
                let code = room.code
                let name = room.name
                dmService.sendMessage("Мы создали комнату «\(name)» · код \(code). Смотрим вместе!", to: friend)
            }
            .environmentObject(APIClient.shared)
        }
        .sheet(isPresented: $showPeerProfile) {
            NavigationStack {
                FriendProfileView(
                    userId: liveFriend.id,
                    usernameHint: liveFriend.deleted ? "Удалённый аккаунт" : liveFriend.username,
                    onWatchTogether: liveFriend.deleted ? nil : {
                        showPeerProfile = false
                        showWatchTogether = true
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { showPeerProfile = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $reactionTarget) { msg in
            DMReactionPickerSheet(
                message: msg,
                onPick: { emoji in
                    reactionTarget = nil
                    Task {
                        await dmService.toggleReaction(emoji: emoji, on: msg, friendId: friend.id)
                    }
                },
                onDismiss: { reactionTarget = nil }
            )
            .presentationDetents([.height(160)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            dmService.chatDidOpen(friendId: friend.id)
            Task { await dmService.refreshUnread() }
        }
        .onDisappear {
            dmService.chatDidClose(friendId: friend.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkChatWallpaperChanged)) { _ in
            wallpaper = PlinkChatWallpaperPrefs.current
        }
        .task {
            dmService.chatDidOpen(friendId: friend.id)
            // Seed live friends so avatar / last-seen stay fresh
            await friendManager.loadFriends()
            // Force full history apply (newest window) — fixes preview vs open mismatch
            await dmService.loadHistory(
                friendId: friend.id,
                friendName: liveFriend.displayTitle,
                friendAvatarURL: liveFriend.avatarURL,
                quiet: false
            )
            while !Task.isCancelled {
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
            }
        }
    }

    // MARK: - Telegram 2026 glass chat header

    /// Layout: [← Чаты · badge]  [  ник / online  ]  [ avatar ⋯ ]
    private var telegramNavBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // ── Left: back to all chats (glass pill + unread indicator)
                Button {
                    HapticManager.selection()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text("Чаты")
                            .font(.system(size: 16, weight: .semibold))
                        if chatsUnreadBadge > 0 {
                            Text(chatsUnreadBadge > 99 ? "99+" : "\(chatsUnreadBadge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Cinema2026.accent, in: Capsule())
                        }
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    chatsUnreadBadge > 0
                    ? "К чатам, непрочитанных \(chatsUnreadBadge)"
                    : "К чатам"
                )

                Spacer(minLength: 4)

                // ── Center: glass capsule with nick + presence (tap → profile)
                Button {
                    HapticManager.impact(.light)
                    showPeerProfile = true
                } label: {
                    VStack(spacing: 1) {
                        Text(liveFriend.displayTitle)
                            .font(.system(size: TGHeader.nameSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(headerPresence)
                            .font(.system(size: TGHeader.statusSize, weight: headerIsOnline ? .semibold : .regular))
                            .foregroundStyle(
                                headerIsOnline
                                ? TGHeader.online
                                : Color.white.opacity(0.55)
                            )
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .frame(minWidth: 120, maxWidth: 200)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(liveFriend.displayTitle), \(headerPresence)")
                .accessibilityHint("Открыть профиль")

                Spacer(minLength: 4)

                // ── Right: avatar + more
                HStack(spacing: 8) {
                    Button {
                        HapticManager.impact(.light)
                        showPeerProfile = true
                    } label: {
                        Group {
                            if liveFriend.deleted {
                                PlinkDeletedAvatar(size: TGHeader.avatar)
                            } else {
                                PlinkStableAvatar(
                                    url: peerAvatarURL,
                                    letter: peerLetter,
                                    size: TGHeader.avatar,
                                    userId: liveFriend.id
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    if headerIsOnline {
                                        Circle()
                                            .fill(TGHeader.online)
                                            .frame(width: 11, height: 11)
                                            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.5))
                                            .offset(x: 1, y: 1)
                                    }
                                }
                            }
                        }
                        .id("tg-av-\(liveFriend.id)-\(friendManager.avatarEpoch)-\(peerAvatarURL?.absoluteString ?? "")")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Профиль \(liveFriend.displayTitle)")

                    Button {
                        HapticManager.impact(.light)
                        showChatActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ещё")
                }
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: TGHeader.barHeight)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .background {
            // Glass curtain under status bar (Telegram 2026 liquid glass)
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
        }
        .confirmationDialog(
            liveFriend.displayTitle,
            isPresented: $showChatActions,
            titleVisibility: .visible
        ) {
            Button("Профиль") { showPeerProfile = true }
            if !liveFriend.deleted {
                Button("Смотреть вместе") { showWatchTogether = true }
            }
            Button("Удалить чат", role: .destructive) {
                confirmDeleteChat = true
            }
            if blockManager.isBlocked(liveFriend.id) {
                Button("Разблокировать") {
                    blockManager.unblockUser(liveFriend.id)
                    HapticManager.impact(.light)
                }
            } else {
                Button("Заблокировать", role: .destructive) {
                    confirmBlockUser = true
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить чат?", isPresented: $confirmDeleteChat) {
            Button("Удалить", role: .destructive) {
                Task {
                    await dmService.deleteChat(with: liveFriend)
                    await MainActor.run { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История переписки с \(liveFriend.displayTitle) будет удалена. Это действие нельзя отменить.")
        }
        .alert("Заблокировать \(liveFriend.displayTitle)?", isPresented: $confirmBlockUser) {
            Button("Заблокировать", role: .destructive) {
                Task {
                    await blockManager.blockAndDeleteChat(
                        userId: liveFriend.id,
                        friend: liveFriend
                    )
                    await MainActor.run { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Пользователь не сможет писать вам. Чат будет удалён, как в Telegram.")
        }
    }

    // MARK: - Glass input

    private var glassInputBar: some View {
        Group {
            if liveFriend.deleted {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Нельзя отправить сообщение удалённому аккаунту")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            } else if blockManager.isBlocked(friend.id) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange.opacity(0.9))
                    Text("Вы заблокировали \(liveFriend.displayTitle)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button("Разблок.") {
                        blockManager.unblockUser(friend.id)
                        HapticManager.impact(.light)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Cinema2026.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            } else {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showEmojiPicker.toggle()
                        }
                        if showEmojiPicker { isInputFocused = false }
                    } label: {
                        Image(systemName: showEmojiPicker ? "keyboard.fill" : "face.smiling.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(showEmojiPicker ? Cinema2026.accent : Color.white.opacity(0.55))
                            .frame(width: 36, height: 36)
                    }

                    TextField("Сообщение", text: $messageText)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 42)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                        )
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendAction() }
                        .onChange(of: messageText) { _, newValue in
                            if newValue.count > charLimit {
                                messageText = String(newValue.prefix(charLimit))
                                HapticManager.impact(.light)
                            }
                        }

                    voiceMicButton

                    Button(action: sendAction) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(
                                messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.white.opacity(0.35)
                                : Color.black.opacity(0.85)
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(
                                    messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.white.opacity(0.10)
                                    : Cinema2026.accent
                                )
                            )
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var voiceMicButton: some View {
        Image(systemName: voiceRecorder.isRecording ? "waveform.circle.fill" : "mic.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(voiceRecorder.isRecording ? Cinema2026.accent : Color.white.opacity(0.65))
            .frame(width: 36, height: 36)
            .scaleEffect(voiceRecorder.isRecording ? 1.12 + CGFloat(voiceRecorder.peakLevel) * 0.2 : 1)
            .animation(.easeOut(duration: 0.08), value: voiceRecorder.peakLevel)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if voiceRecorder.isRecording {
                            // Auto-send at max duration
                            if voiceRecorder.durationSec >= VoiceNoteRecorder.maxDuration {
                                finishVoiceRecording(send: true)
                            }
                            return
                        }
                        guard !voiceStartInFlight else { return }
                        voiceStartInFlight = true
                        Task {
                            HapticManager.impact(.medium)
                            let ok = await voiceRecorder.start()
                            voiceStartInFlight = false
                            if !ok {
                                if case .failed(let m) = voiceRecorder.state {
                                    voiceError = m
                                } else {
                                    voiceError = "Нет доступа к микрофону"
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        voiceStartInFlight = false
                        // Swipe up ≈ cancel (Telegram-like)
                        if value.translation.height < -50 {
                            finishVoiceRecording(send: false)
                        } else {
                            finishVoiceRecording(send: true)
                        }
                    }
            )
            .accessibilityLabel("Удерживайте для голосового")
            .overlay(alignment: .top) {
                if voiceRecorder.isRecording {
                    Text(PlinkVoiceWire.formatDuration(voiceRecorder.durationSec))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Cinema2026.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .offset(y: -28)
                        .transition(.opacity)
                }
            }
            .alert("Голосовое", isPresented: Binding(
                get: { voiceError != nil },
                set: { if !$0 { voiceError = nil } }
            )) {
                Button("OK", role: .cancel) { voiceError = nil }
            } message: {
                Text(voiceError ?? "")
            }
    }

    private func finishVoiceRecording(send: Bool) {
        guard voiceRecorder.isRecording || {
            if case .encoding = voiceRecorder.state { return true }
            return false
        }() else {
            // Permission failed mid-gesture
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            voiceRecorder.cancel()
            return
        }

        if !send {
            voiceRecorder.cancel()
            HapticManager.impact(.light)
            return
        }

        guard let exported = voiceRecorder.stopAndExport() else {
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            return
        }
        HapticManager.impact(.medium)
        dmService.sendVoiceNote(
            dataURL: exported.dataURL,
            durationSec: exported.duration,
            to: friend
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func sendAction() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) >= 0.4 else {
            HapticManager.impact(.light)
            return
        }
        lastSendTime = now
        dmService.sendMessage(text, to: friend)
        messageText = ""
        HapticManager.impact(.light)
    }
}

// MARK: - Reaction picker (Telegram quick bar)

private struct DMReactionPickerSheet: View {
    let message: DirectMessage
    let onPick: (String) -> Void
    let onDismiss: () -> Void

    private let emojis = ["❤️", "👍", "😂", "😮", "😢", "🔥", "👏", "🎉", "💯", "🥰"]

    var body: some View {
        VStack(spacing: 14) {
            Text("Реакция")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        HapticManager.impact(.light)
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Circle avatar

private struct DMCircleAvatar: View {
    let url: URL?
    let letter: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letterView
                    }
                }
            } else {
                letterView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .id(url?.absoluteString ?? "letter-\(letter)")
    }

    private var letterView: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Cinema2026.accent.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(letter)
                .font(.system(size: max(10, size * 0.38), weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - DM Bubble (Telegram clusters + reactions + glass capsules)

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"
    var cluster: ChatClusterLayout
    var onReact: () -> Void
    var onToggleChip: (String) -> Void

    private let avatarSize: CGFloat = PlinkTelegramBubbleMetrics.avatarSize

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 36)
            } else {
                avatarSlot
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
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
                        Label("Реакция", systemImage: "face.smiling")
                    }
                    if !message.isVoiceNote {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    HapticManager.impact(.medium)
                    onReact()
                }

                // Reaction chips under bubble (Telegram)
                if !message.reactions.isEmpty {
                    reactionChips
                }

                if cluster.isLastInGroup {
                    HStack(spacing: 3) {
                        Text(message.timeString)
                            .font(.system(size: 11, weight: .semibold))
                            // Time sits on wallpaper — use solid pill so it never vanishes
                            .foregroundStyle(Color.white.opacity(0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.42)))
                        if isOwn {
                            // Telegram ticks: one gray = sent, two blue = read
                            TelegramReadTicks(isRead: message.isRead)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: PlinkTelegramBubbleMetrics.maxBubbleWidth, alignment: isOwn ? .trailing : .leading)

            if isOwn {
                avatarSlot
            } else {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    private var reactionChips: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions, id: \.emoji) { chip in
                Button {
                    HapticManager.impact(.light)
                    onToggleChip(chip.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(chip.emoji)
                            .font(.system(size: 13))
                        if chip.count > 1 {
                            Text("\(chip.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chip.includesMe
                                  ? Cinema2026.accent.opacity(0.35)
                                  : Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                chip.includesMe
                                ? Cinema2026.accent.opacity(0.55)
                                : Color.white.opacity(0.12),
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if cluster.showAvatar {
            PlinkStableAvatar(
                url: avatarURL,
                letter: letter,
                size: avatarSize,
                userId: message.senderID
            )
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        } else {
            Color.clear.frame(width: avatarSize, height: avatarSize)
        }
    }
}

// MARK: - Voice note bubble (play real audio)

private struct VoiceNoteBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    @State private var player = VoiceNotePlayer.shared

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
        message.hasMedia || message.mediaType == "voice"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard canPlay else { return }
                HapticManager.impact(.light)
                player.toggle(messageId: message.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(isOwn ? Color.black.opacity(0.22) : Cinema2026.accent.opacity(0.85))
                        .frame(width: 44, height: 44)
                    if player.isLoading && isThisPlaying {
                        ProgressView()
                            .tint(isOwn ? .white : .black)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isOwn ? Color.white : Color.black.opacity(0.85))
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)

            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 5)
                        Capsule()
                            .fill(isOwn ? Color.white.opacity(0.85) : Cinema2026.accent)
                            .frame(
                                width: geo.size.width * (isThisPlaying ? max(0.04, player.progress) : 0.04),
                                height: 5
                            )
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(durationLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                    if !canPlay {
                        Text("· нет аудио")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 140, maxWidth: 200)
        }
        .padding(.horizontal, PlinkTelegramBubbleMetrics.padH)
        .padding(.vertical, PlinkTelegramBubbleMetrics.padV)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isOwn
                      ? Cinema2026.accent
                      : Color(hex: "#2E333A"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isOwn ? 0.20 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

// MARK: - Telegram read ticks (✓ / ✓✓)

/// Exact Telegram semantics:
///  - not read → single gray check
///  - read by peer → two blue checks (slightly overlapping)
private struct TelegramReadTicks: View {
    let isRead: Bool

    private var tickColor: Color {
        isRead ? Color(red: 0.34, green: 0.78, blue: 1.0) : Color.white.opacity(0.45)
    }

    var body: some View {
        HStack(spacing: isRead ? -4.5 : 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            if isRead {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(tickColor)
        .accessibilityLabel(isRead ? "Прочитано" : "Отправлено")
    }
}

// MARK: - Day Divider (glass capsule)

private struct DMDayDivider: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.48))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}


