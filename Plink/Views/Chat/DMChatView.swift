import SwiftUI
import PhotosUI

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
    /// Finger is currently holding the mic (Telegram hold-to-record).
    @State private var voiceFingerDown = false
    /// Drag left past threshold → cancel (VK / Telegram).
    @State private var voiceCancelArmed = false
    @State private var voiceDragX: CGFloat = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoDraft: ChatPhotoDraft?
    @State private var photoCaption = ""
    @State private var photoError: String?
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
                                DMMessageRow(
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
                                .padding(.horizontal, 8)
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
        .sheet(item: $photoDraft) { draft in
            PhotoSendPreviewSheet(
                draft: draft,
                caption: $photoCaption,
                onCancel: {
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                },
                onSend: {
                    dmService.sendPhoto(
                        dataURL: draft.compressed.dataURL,
                        previewImage: draft.compressed.image,
                        caption: photoCaption,
                        to: liveFriend
                    )
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                    HapticManager.impact(.medium)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await preparePhotoDraft(from: item) }
        }
        .alert("Фото", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
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
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await friendManager.loadFriends()
                // Quiet polling prevents full-list visual churn and reduces chat lag.
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: liveFriend.displayTitle,
                    friendAvatarURL: liveFriend.avatarURL,
                    quiet: true
                )
            }
        }
    }

    // MARK: - Telegram 2026 glass chat header

    /// Layout: [← Чаты · badge]  [  ник / online  ]  [ avatar ⋯ ]
    private func preparePhotoDraft(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "Не удалось прочитать фото"
                return
            }
            let compressed = try ChatImageCompressor.compress(data)
            await MainActor.run {
                photoCaption = ""
                photoDraft = ChatPhotoDraft(compressed: compressed)
            }
        } catch {
            await MainActor.run {
                photoError = "Не удалось подготовить фото: \(error.localizedDescription)"
                selectedPhotoItem = nil
            }
        }
    }

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
        .alert("Внести в чёрный список?", isPresented: $confirmBlockUser) {
            Button("Заблокировать", role: .destructive) {
                Task {
                    await blockManager.blockAndDeleteChat(
                        userId: liveFriend.id,
                        friend: liveFriend
                    )
                    HapticManager.impact(.heavy)
                    await MainActor.run { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Точно хотите внести \(liveFriend.displayTitle) в чёрный список? Пользователь не сможет отправлять вам сообщения и приглашать в комнаты. Переписка будет удалена.")
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
                // Stable layout: left content changes, mic keeps the same identity
                // so hold-gesture is not cancelled when recording UI appears.
                HStack(spacing: 10) {
                    if voiceRecorder.isRecording || voiceFingerDown {
                        voiceRecordingLeading
                    } else {
                        composerLeading
                    }

                    // Empty text → mic (hold). Has text → send (tap). While recording always mic.
                    if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || voiceRecorder.isRecording || voiceFingerDown {
                        voiceMicButton
                    } else {
                        Button(action: sendAction) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Cinema2026.accent))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Отправить")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .onChange(of: voiceRecorder.durationSec) { _, dur in
                    if dur >= VoiceNoteRecorder.maxDuration {
                        finishVoiceRecording(send: true)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
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

    // MARK: - Voice recording (Telegram / VK style)

    private var composerLeading: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Cinema2026.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Галерея")
            .simultaneousGesture(TapGesture().onEnded { Task { await PlinkPermissions.preparePhotoPicker() } })

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmojiPicker.toggle()
                }
                if showEmojiPicker { isInputFocused = false }
            } label: {
                Image(systemName: showEmojiPicker ? "keyboard.fill" : "face.smiling.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(showEmojiPicker ? Cinema2026.accent : Color.white.opacity(0.55))
                    .frame(width: 34, height: 36)
            }

            TextField("Сообщение", text: $messageText, axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .lineLimit(1...5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
        }
    }

    /// Left side of bar while holding: cancel hint + levels + timer.
    private var voiceRecordingLeading: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                Text(voiceCancelArmed ? "Отмена" : "Влево")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(voiceCancelArmed ? Color.red.opacity(0.95) : Color.white.opacity(0.45))

            Spacer(minLength: 4)

            VoiceLevelBars(level: voiceRecorder.peakLevel, active: true)
                .frame(width: 64, height: 22)

            Text(PlinkVoiceWire.formatDuration(voiceRecorder.durationSec))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    /// Mic stays mounted while recording so the hold gesture never drops.
    private var voiceMicButton: some View {
        let recording = voiceRecorder.isRecording || voiceFingerDown
        return ZStack {
            Circle()
                .fill(
                    voiceCancelArmed
                    ? Color.red.opacity(0.35)
                    : (recording ? Cinema2026.accent.opacity(0.28) : Color.white.opacity(0.10))
                )
                .frame(width: recording ? 58 : 44, height: recording ? 58 : 44)
                .scaleEffect(recording ? 1.0 + CGFloat(voiceRecorder.peakLevel) * 0.12 : 1)
            Circle()
                .fill(voiceCancelArmed ? Color.red : (recording ? Cinema2026.accent : Color.white.opacity(0.14)))
                .frame(width: recording ? 46 : 40, height: recording ? 46 : 40)
            Image(systemName: voiceCancelArmed ? "trash.fill" : "mic.fill")
                .font(.system(size: recording ? 20 : 18, weight: .semibold))
                .foregroundStyle(recording || voiceCancelArmed ? Color.white : Color.white.opacity(0.85))
        }
        .offset(x: max(-80, min(0, voiceDragX * 0.3)))
        .contentShape(Circle().scale(1.6))
        .gesture(voiceHoldGesture)
        .animation(.easeOut(duration: 0.08), value: voiceRecorder.peakLevel)
        .accessibilityLabel("Удерживайте для голосового сообщения")
        .accessibilityHint("Отпустите, чтобы отправить. Сдвиньте влево, чтобы отменить")
    }

    private var voiceHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                voiceFingerDown = true
                voiceDragX = value.translation.width
                let cancel = value.translation.width < -55
                if cancel != voiceCancelArmed {
                    voiceCancelArmed = cancel
                    HapticManager.impact(cancel ? .rigid : .light)
                }
                if voiceRecorder.isRecording {
                    return
                }
                guard !voiceStartInFlight else { return }
                voiceStartInFlight = true
                isInputFocused = false
                showEmojiPicker = false
                Task {
                    HapticManager.impact(.medium)
                    let ok = await voiceRecorder.start()
                    await MainActor.run {
                        voiceStartInFlight = false
                        // Finger already up while permission sheet was open → drop
                        if !voiceFingerDown {
                            if ok { voiceRecorder.cancel() }
                            resetVoiceGestureUI()
                            return
                        }
                        if !ok {
                            resetVoiceGestureUI()
                            if case .failed(let m) = voiceRecorder.state {
                                voiceError = m
                            } else {
                                voiceError = "Нет доступа к микрофону. Разрешите в окне iOS или в Настройках."
                            }
                        }
                    }
                }
            }
            .onEnded { _ in
                voiceFingerDown = false
                voiceStartInFlight = false
                let shouldCancel = voiceCancelArmed
                // If still starting (permission), cancel is handled when start returns
                if voiceRecorder.isRecording || {
                    if case .encoding = voiceRecorder.state { return true }
                    return false
                }() {
                    finishVoiceRecording(send: !shouldCancel)
                } else {
                    // Never got to recording (permission / short tap)
                    if case .failed(let m) = voiceRecorder.state {
                        voiceError = m
                    }
                    voiceRecorder.cancel()
                }
                resetVoiceGestureUI()
            }
    }

    private func resetVoiceGestureUI() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            voiceCancelArmed = false
            voiceDragX = 0
            voiceFingerDown = false
        }
    }

    private func finishVoiceRecording(send: Bool) {
        guard voiceRecorder.isRecording || {
            if case .encoding = voiceRecorder.state { return true }
            return false
        }() else {
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            voiceRecorder.cancel()
            resetVoiceGestureUI()
            return
        }

        if !send {
            voiceRecorder.cancel()
            HapticManager.impact(.light)
            resetVoiceGestureUI()
            return
        }

        guard let exported = voiceRecorder.stopAndExport() else {
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            resetVoiceGestureUI()
            return
        }
        HapticManager.impact(.medium)
        dmService.sendVoiceNote(
            dataURL: exported.dataURL,
            durationSec: exported.duration,
            to: friend
        )
        resetVoiceGestureUI()
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

private struct DMMessageRow: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"
    var cluster: ChatClusterLayout
    var onReact: () -> Void
    var onToggleChip: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            DMBubble(
                message: message,
                isOwn: isOwn,
                avatarURL: avatarURL,
                letter: letter,
                cluster: cluster,
                maxBubbleWidth: min(
                    PlinkTelegramBubbleMetrics.maxBubbleWidth,
                    geo.size.width * PlinkTelegramBubbleMetrics.maxWidthRatio
                ),
                onReact: onReact,
                onToggleChip: onToggleChip
            )
        }
        .frame(minHeight: 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"
    var cluster: ChatClusterLayout
    var maxBubbleWidth: CGFloat = PlinkTelegramBubbleMetrics.maxBubbleWidth
    var onReact: () -> Void
    var onToggleChip: (String) -> Void

    private let avatarSize: CGFloat = PlinkTelegramBubbleMetrics.avatarSize

    private var photoURL: URL? {
        APIClient.shared.baseURL.appendingPathComponent("messages/photo/\(message.id)")
    }

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
                            isOwn: isOwn,
                            maxWidth: maxBubbleWidth
                        )
                    } else if message.isPhotoMessage {
                        PlinkPhotoMessageBubble(
                            imageURL: photoURL,
                            localImage: ChatPhotoCache.shared.image(for: message.id),
                            caption: message.text,
                            isOwn: isOwn,
                            styleID: message.bubbleStyle,
                            isLastInGroup: cluster.isLastInGroup
                        )
                        .frame(maxWidth: min(maxBubbleWidth, PlinkTelegramBubbleMetrics.maxPhotoBubbleWidth), alignment: isOwn ? .trailing : .leading)
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
                // Removed onLongPressGesture — conflicts with .contextMenu causing flicker.
                // contextMenu already provides long-press behaviour.

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
            .frame(maxWidth: maxBubbleWidth, alignment: isOwn ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)

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

// MARK: - Photo preview sheet

struct ChatPhotoDraft: Identifiable {
    let id = UUID()
    let compressed: ChatCompressedImage
}

struct PhotoSendPreviewSheet: View {
    let draft: ChatPhotoDraft
    @Binding var caption: String
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: draft.compressed.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

                TextField("Добавить подпись…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 16))
                    .foregroundStyle(Cinema2026.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Cinema2026.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: caption) { _, value in
                        if value.count > 240 { caption = String(value.prefix(240)) }
                    }

                Text("Сжато до \(max(1, draft.compressed.byteCount / 1024)) KB")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Cinema2026.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Cinema2026.background.ignoresSafeArea())
            .navigationTitle("Отправить фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить", action: onSend)
                        .fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - Voice note bubble (play real audio)

private struct VoiceNoteBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var maxWidth: CGFloat = PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth
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
        // Voice notes always try play — local cache or server stream
        message.isVoiceNote || message.hasMedia || message.mediaType == "voice"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard canPlay else { return }
                HapticManager.impact(.light)
                playError = nil
                player.toggle(messageId: message.id)
                // Surface player errors shortly after tap
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if player.playingMessageId == nil,
                       let err = player.errorMessage, !err.isEmpty {
                        playError = err
                    }
                }
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
                // Static fake waveform + progress overlay (Telegram-like)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        VoiceWaveformStrip(seed: message.id, progress: isThisPlaying ? player.progress : 0)
                            .frame(height: 22)
                        // scrub progress line
                        Rectangle()
                            .fill(isOwn ? Color.white.opacity(0.55) : Cinema2026.accent.opacity(0.9))
                            .frame(width: 2, height: 22)
                            .offset(x: max(0, geo.size.width * (isThisPlaying ? player.progress : 0) - 1))
                    }
                }
                .frame(height: 22)

                HStack {
                    Text(durationLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                    if let playError {
                        Text("· \(playError)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(
                minWidth: PlinkTelegramBubbleMetrics.minVoiceBubbleWidth,
                idealWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth),
                maxWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth),
                alignment: .leading
            )
        }
        .frame(maxWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth), alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, PlinkTelegramBubbleMetrics.padV)
        .background(
            ZStack {
                Color(hex: "#1A1C20")
                if isOwn {
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.64, blue: 1.0),
                            Color(red: 0.11, green: 0.78, blue: 0.48)
                        ],
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
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - Voice UI helpers

/// Live mic level bars while recording (VK / TG style).
private struct VoiceLevelBars: View {
    var level: Float
    var active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let phase = abs(sin(Double(i) * 0.9 + Double(level) * 8))
                let h = active
                    ? 4 + CGFloat(level) * 16 * CGFloat(0.35 + phase * 0.65)
                    : 4
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 3.5, height: max(4, h))
            }
        }
        .animation(.easeOut(duration: 0.06), value: level)
    }
}

/// Decorative waveform for a voice bubble (deterministic from message id).
private struct VoiceWaveformStrip: View {
    let seed: String
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let count = 28
            let w = max(2, (geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count))
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let h = barHeight(index: i)
                    let filled = Double(i) / Double(count) <= progress
                    Capsule()
                        .fill(Color.white.opacity(filled ? 0.95 : 0.28))
                        .frame(width: w, height: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        // Stable pseudo-random heights from seed
        var hash: UInt64 = 5381
        for u in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(u.value)
        }
        hash = hash &+ UInt64(index) &* 2654435761
        let n = Double((hash % 1000)) / 1000.0
        return 5 + CGFloat(n) * 16
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


