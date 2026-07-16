import SwiftUI

// MARK: - DM Chat View v5 — per-user avatars + Telegram left/right
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

    private var peerAvatarURL: URL? {
        PlinkAvatarURL.resolve(userId: friend.id, stored: friend.avatarURL)
    }

    private var peerLetter: String {
        PlinkAvatarURL.letter(from: friend.displayTitle)
    }

    private var meId: String {
        UserDefaults.standard.string(forKey: "plink_current_user_id") ?? ""
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
            Cinema2026.background

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            DMDayDivider(label: "Сегодня")

                            ForEach(messages) { msg in
                                let own = msg.isOwnMessage
                                DMBubble(
                                    message: msg,
                                    isOwn: own,
                                    avatarURL: own ? meAvatarURL : peerAvatarURL,
                                    letter: own ? meLetter : peerLetter
                                )
                                .id(msg.id)
                                .padding(.horizontal, 10)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: dmService.historyEpoch) { _, _ in
                        // Delay so LazyVStack has registered new message ids
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: messages.count) { oldCount, newCount in
                        guard newCount > oldCount else { return }
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
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
                    DMCircleAvatar(url: peerAvatarURL, letter: peerLetter, size: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(friend.displayTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if friend.displayName != nil {
                            Text("@\(friend.username)")
                                .font(.system(size: 11))
                                .foregroundColor(Cinema2026.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(friend.isOnline ? Cinema2026.accent : Cinema2026.tertiary)
                                .frame(width: 6, height: 6)
                            Text(friend.presenceText)
                                .font(.system(size: 12, weight: friend.isOnline ? .semibold : .regular))
                                .foregroundColor(friend.isOnline ? Cinema2026.accent : Cinema2026.secondary)
                                .lineLimit(1)
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
        .onAppear {
            dmService.chatDidOpen(friendId: friend.id)
        }
        .onDisappear {
            dmService.chatDidClose(friendId: friend.id)
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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

// MARK: - Circle avatar (photo or letter of THIS user only)

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
    }

    private var letterView: some View {
        ZStack {
            Circle().fill(Cinema2026.accent.opacity(0.55))
            Text(letter)
                .font(.system(size: max(10, size * 0.38), weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - DM Bubble (Telegram: own right / peer left)

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 48)
            } else {
                DMCircleAvatar(url: avatarURL, letter: letter, size: 28)
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                PlinkMessageBubble(
                    text: message.text,
                    isOwn: isOwn,
                    styleID: isOwn ? PlinkBubbleStylePrefs.currentID : nil,
                    fontSize: 16
                )

                Text(message.timeString)
                    .font(.system(size: 11))
                    .foregroundColor(Cinema2026.tertiary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)

            if isOwn {
                DMCircleAvatar(url: avatarURL, letter: letter, size: 28)
            } else {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
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
