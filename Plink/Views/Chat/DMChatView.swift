import SwiftUI

// MARK: - DM Chat View v4 (Telegram-style left/right + live poll)
struct DMChatView: View {
    @EnvironmentObject private var dmService: DMChatService
    @Environment(\.dismiss) private var dismiss

    let friend: Friend
    @State private var messageText = ""
    @State private var showEmojiPicker = false
    @State private var showWatchTogether = false
    @FocusState private var isInputFocused: Bool
    private let charLimit = 150
    @State private var lastSendTime: Date = .distantPast

    private var friendAvatarURL: URL? {
        PlinkAvatarURL.resolve(userId: friend.id, stored: friend.avatarURL)
    }

    private var messages: [DirectMessage] {
        dmService.messages(for: friend.id)
    }

    var body: some View {
        ZStack {
            Cinema2026.background

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            DMDayDivider(label: "Сегодня")

                            ForEach(messages) { msg in
                                DMBubble(
                                    message: msg,
                                    isOwn: msg.isOwnMessage,
                                    peerAvatarURL: friendAvatarURL,
                                    peerInitials: friend.initials
                                )
                                .id(msg.id)
                                .padding(.horizontal, 10)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: dmService.historyEpoch) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }

                if showEmojiPicker {
                    EmojiPickerGrid(chatText: $messageText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                inputBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Cinema2026.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Group {
                        if let url = friendAvatarURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    avatarHeader
                                }
                            }
                        } else {
                            avatarHeader
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(friend.username)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(friend.isOnline ? Cinema2026.accent : Cinema2026.tertiary)
                                .frame(width: 6, height: 6)
                            Text(friend.isOnline ? "в сети" : "не в сети")
                                .font(.system(size: 12))
                                .foregroundColor(Cinema2026.secondary)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWatchTogether = true
                } label: {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Cinema2026.accent)
                }
                .accessibilityLabel("Смотреть вместе")
            }
        }
        .sheet(isPresented: $showWatchTogether) {
            RoomCreationView { room in
                showWatchTogether = false
                let code = room.code
                let name = room.name
                dmService.sendMessage("Мы создали комнату «\(name)» · код \(code). Смотрим вместе!", to: friend)
            }
            .environmentObject(APIClient.shared)
        }
        .preferredColorScheme(.dark)
        .task {
            await dmService.loadHistory(
                friendId: friend.id,
                friendName: friend.username,
                friendAvatarURL: friend.avatarURL,
                quiet: false
            )
            // Quiet poll while chat is open — new messages without re-enter
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: friend.username,
                    friendAvatarURL: friend.avatarURL,
                    quiet: true
                )
            }
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

    private var avatarHeader: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(friend.initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmojiPicker.toggle()
                }
                if showEmojiPicker { isInputFocused = false }
            } label: {
                Image(systemName: showEmojiPicker ? "keyboard.fill" : "face.smiling.fill")
                    .font(.system(size: 22))
                    .foregroundColor(showEmojiPicker ? Cinema2026.accent : Cinema2026.secondary)
            }

            TextField("Сообщение...", text: $messageText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .focused($isInputFocused)
                .onSubmit { sendAction() }
                .onChange(of: messageText) { _, newValue in
                    if newValue.count > charLimit {
                        messageText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }

            Button(action: sendAction) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(messageText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Cinema2026.tertiary : Cinema2026.accent)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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

// MARK: - DM Bubble (Telegram: own right / peer left)

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var peerAvatarURL: URL?
    var peerInitials: String = "?"

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 48)
            } else {
                peerAvatar
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isOwn ? Cinema2026.accent.opacity(0.92) : Color.white.opacity(0.10))
                    .clipShape(ChatBubbleShapeDM(isOwn: isOwn))

                Text(message.timeString)
                    .font(.system(size: 11))
                    .foregroundColor(Cinema2026.tertiary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: isOwn ? .trailing : .leading)

            if !isOwn {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    @ViewBuilder
    private var peerAvatar: some View {
        let size: CGFloat = 28
        if let url = peerAvatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
                .frame(width: size, height: size)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Cinema2026.accent.opacity(0.55))
            Text(String(peerInitials.prefix(2)))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Day Divider
private struct DMDayDivider: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Cinema2026.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

// MARK: - Bubble Shape
private struct ChatBubbleShapeDM: Shape {
    let isOwn: Bool

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight, isOwn ? .bottomLeft : .bottomRight],
            cornerRadii: CGSize(width: 16, height: 16)
        )
        return Path(path.cgPath)
    }
}
