import SwiftUI

// MARK: - DM Chat View v3 (Telegram/WhatsApp style)
/// Полноэкранный чат: свои сообщения справа (ледяной голубой),
/// чужие слева (тёмно-серый). Аватарки 28pt у чужих. Время 12pt.
/// Разделители по дням. Шрифт 16pt.
struct DMChatView: View {
    // 🔧 FIX C4: DMChatService injected from RaveCloneApp via EnvironmentObject
    // (was: @StateObject DMChatService() — created own unauth APIClient)
    @EnvironmentObject private var dmService: DMChatService
    @Environment(\.dismiss) private var dismiss

    let friend: Friend
    @State private var messageText = ""
    @State private var showEmojiPicker = false
    @State private var showWatchTogether = false
    @FocusState private var isInputFocused: Bool
    /// 🔧 CHAR LIMIT: 150 chars max per DM — prevents spam
    private let charLimit = 150
    /// 🔧 RATE LIMIT: min 1s between DMs
    @State private var lastSendTime: Date = .distantPast

    var body: some View {
        ZStack {
            Cinema2026.background

            VStack(spacing: 0) {
                // ── Лента сообщений ───────────────────────────────────
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            // Дата-разделитель
                            DMDayDivider(label: "Сегодня")

                            ForEach(dmService.messages(for: friend.id)) { msg in
                                DMBubble(message: msg)
                                    .id(msg.id)
                                    .padding(.horizontal, 14)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: dmService.messages(for: friend.id).count) { _, _ in
                        if let lastID = dmService.messages(for: friend.id).last?.id {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                // ── Эмодзи-пикер ─────────────────────────────────────
                if showEmojiPicker {
                    EmojiPickerGrid(chatText: $messageText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Поле ввода ───────────────────────────────────────
                inputBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Cinema2026.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    if let urlStr = friend.avatarURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                avatarHeader
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    } else {
                        avatarHeader
                            .frame(width: 32, height: 32)
                    }

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
                // Notify friend in DM that a room was created
                let code = room.code
                let name = room.name
                dmService.sendMessage("Мы создали комнату «\(name)» · код \(code). Смотрим вместе!", to: friend)
            }
            .environmentObject(APIClient.shared)
        }
        .preferredColorScheme(.dark)
        .task {
            await dmService.loadHistory(friendId: friend.id, friendName: friend.username)
            // Poll so messages from the other phone appear without push/WS
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await dmService.loadHistory(friendId: friend.id, friendName: friend.username)
            }
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

    // MARK: - Input Bar (ледяной голубой)

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Эмодзи
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

            // Текстовое поле 16pt
            TextField("Сообщение...", text: $messageText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .onSubmit { sendAction() }
                .onChange(of: messageText) { _, newValue in
                    // 🔧 CHAR LIMIT: Truncate at 200 chars
                    if newValue.count > charLimit {
                        messageText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }

            // Кнопка отправки — ледяной голубой
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

        // 🔧 RATE LIMIT: min 1s between DMs
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) >= 1 else {
            HapticManager.impact(.light)
            return
        }
        lastSendTime = now

        dmService.sendMessage(text, to: friend)
        messageText = ""
        HapticManager.impact(.light)
    }
}

// MARK: - DM Bubble v3 (Telegram style)

private struct DMBubble: View {
    let message: DirectMessage
    @State private var shimmer: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isOwnMessage {
                Spacer(minLength: 60)
            } else {
                // Аватарка 28pt только у чужих
                avatarView
            }

            VStack(alignment: message.isOwnMessage ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(messageBackground)
                    .clipShape(ChatBubbleShapeDM(isOwn: message.isOwnMessage))
                    .overlay(
                        ChatBubbleShapeDM(isOwn: message.isOwnMessage)
                            .stroke(
                                message.isOwnPremium
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(message.isOwnMessage ? 0 : 0.06),
                                lineWidth: message.isOwnPremium ? 0.8 : 0.5
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if message.isOwnPremium {
                            // Лёгкие плавающие искры для премиум-сообщений
                            PremiumMessageSparks()
                                .allowsHitTesting(false)
                        }
                    }
                    .onAppear {
                        if message.isOwnPremium {
                            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                                shimmer = 1
                            }
                        }
                    }

                // Время 12pt
                Text(message.timeString)
                    .font(.system(size: 12))
                    .foregroundColor(Cinema2026.tertiary)
                    .padding(.trailing, message.isOwnMessage ? 4 : 0)
                    .padding(.leading, message.isOwnMessage ? 0 : 4)
            }
        }
    }

    @ViewBuilder
    private var messageBackground: some View {
        if message.isOwnPremium {
            // Анимированный градиент для премиум-сообщений
            LinearGradient(
                colors: [
                    Cinema2026.accent,
                    Cinema2026.accent,
                    Cinema2026.accent,
                ],
                startPoint: UnitPoint(x: shimmer, y: 0),
                endPoint: UnitPoint(x: shimmer + 1, y: 1)
            )
        } else if message.isOwnMessage {
            Cinema2026.accent.opacity(0.85)
        } else {
            Color.white.opacity(0.08)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        let size: CGFloat = 28
        if let avatarURL = message.senderAvatarURL, let url = URL(string: avatarURL) {
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
            Circle()
                .fill(avatarColor)
            Text(message.initials)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var avatarColor: Color {
        let palette: [Color] = [Cinema2026.accent, Cinema2026.accent, Cinema2026.accent, Cinema2026.accent, Cinema2026.accent, Cinema2026.accent]
        let hash = abs(message.senderID.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - Day Divider
private struct DMDayDivider: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Cinema2026.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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

// MARK: - Premium Message Sparks (плавающие искры для премиум-сообщений)
/// Лёгкие плавающие эмодзи ✨🌟💫 с низкой интенсивностью.
struct PremiumMessageSparks: View {
    @State private var phase: CGFloat = 0

    private let sparks: [(emoji: String, xOffset: CGFloat, yOffset: CGFloat, delay: Double)] = [
        ("✨", 0.85, 0.15, 0),
        ("🌟", 0.5, 0.2, 0.4),
        ("💫", 0.15, 0.1, 0.8),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(sparks.indices, id: \.self) { i in
                Text(sparks[i].emoji)
                    .font(.system(size: 8))
                    .opacity(0.55)
                    .position(
                        x: geo.size.width * sparks[i].xOffset,
                        y: geo.size.height * sparks[i].yOffset + sin(phase + sparks[i].delay) * 2
                    )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}
