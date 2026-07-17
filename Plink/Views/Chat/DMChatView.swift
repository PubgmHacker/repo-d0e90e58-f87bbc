import SwiftUI

// MARK: - DM Chat View v7 — Telegram glassmorphism + reactions

struct DMChatView: View {
    @EnvironmentObject private var dmService: DMChatService
    @Environment(\.dismiss) private var dismiss

    let friend: Friend
    @State private var messageText = ""
    @State private var showEmojiPicker = false
    @State private var showWatchTogether = false
    @State private var reactionTarget: DirectMessage?
    @FocusState private var isInputFocused: Bool
    private let charLimit = 280
    @State private var lastSendTime: Date = .distantPast
    @State private var avatarBust = PlinkAvatarURL.sessionBust

    private var peerAvatarURL: URL? {
        PlinkAvatarURL.resolve(userId: friend.id, stored: friend.avatarURL)
    }

    private var peerLetter: String {
        PlinkAvatarURL.letter(from: friend.displayTitle)
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
        PlinkAvatarURL.resolve(userId: meId.isEmpty ? nil : meId, stored: nil)
    }

    private var messages: [DirectMessage] {
        dmService.messages(for: friend.id)
    }

    var body: some View {
        ZStack {
            // Layered glass background
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.07, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft orbs (glass depth)
            Circle()
                .fill(Cinema2026.accent.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -120, y: -180)
            Circle()
                .fill(Color.purple.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 140, y: 320)

            VStack(spacing: 0) {
                glassHeader

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
                                .padding(.horizontal, 12)
                                .padding(.top, cluster.topPadding)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
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
        .onReceive(NotificationCenter.default.publisher(for: .plinkAvatarsDidChange)) { n in
            avatarBust = (n.object as? Int) ?? PlinkAvatarURL.sessionBust
        }
        .task {
            dmService.chatDidOpen(friendId: friend.id)
            await dmService.loadHistory(
                friendId: friend.id,
                friendName: friend.displayTitle,
                friendAvatarURL: friend.avatarURL,
                quiet: false
            )
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { break }
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: friend.displayTitle,
                    friendAvatarURL: friend.avatarURL,
                    quiet: true
                )
            }
        }
    }

    // MARK: - Glass header (Telegram-style)

    private var glassHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            DMCircleAvatar(url: peerAvatarURL, letter: peerLetter, size: 40)
                .id("dm-header-av-\(friend.id)-\(avatarBust)")
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(friend.isOnline
                              ? Color(red: 0.3, green: 0.9, blue: 0.55)
                              : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                    Text(friend.presenceText)
                        .font(.system(size: 12, weight: friend.isOnline ? .semibold : .regular))
                        .foregroundStyle(friend.isOnline
                                         ? Color(red: 0.3, green: 0.9, blue: 0.55)
                                         : Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                showWatchTogether = true
            } label: {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Смотреть вместе")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: Rectangle()
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Glass input

    private var glassInputBar: some View {
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
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
                .focused($isInputFocused)
                .onSubmit { sendAction() }
                .onChange(of: messageText) { _, newValue in
                    if newValue.count > charLimit {
                        messageText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }

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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
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

    private let avatarSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 44)
            } else {
                avatarSlot
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                PlinkMessageBubble(
                    text: message.text,
                    isOwn: isOwn,
                    styleID: message.bubbleStyle,
                    fontSize: 16,
                    isLastInGroup: cluster.isLastInGroup
                )
                .contextMenu {
                    Button {
                        onReact()
                    } label: {
                        Label("Реакция", systemImage: "face.smiling")
                    }
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
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
                    Text(message.timeString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 290, alignment: isOwn ? .trailing : .leading)

            if isOwn {
                avatarSlot
            } else {
                Spacer(minLength: 44)
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
            DMCircleAvatar(url: avatarURL, letter: letter, size: avatarSize)
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        } else {
            Color.clear.frame(width: avatarSize, height: avatarSize)
        }
    }
}

// MARK: - Day Divider (glass capsule)

private struct DMDayDivider: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}


