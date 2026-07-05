import SwiftUI

// MARK: - Room Chat View
/// Чат для экрана комнаты. Два режима layout:
/// - `.portrait`: занимает оставшееся пространство под видео (всегда виден)
/// - `.landscape`: выезжает справа поверх видео (280pt), сворачиваемый
struct RoomChatView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    let messages: [ChatMessage]
    @Binding var chatText: String
    var onSend: () -> Void
    var currentUserID: String?

    /// Layout mode (передаётся из RoomView на основе ориентации)
    let mode: LayoutMode

    /// Только для landscape: привязка видимости
    @Binding var isPanelOpen: Bool

    /// Показывать ли эмодзи-пикер
    @State private var showEmojiPicker = false

    /// Фокус на текстовом поле (чтобы убирать клавиатуру)
    @FocusState private var isInputFocused: Bool

    /// 🔧 CHAR LIMIT: 150 chars max per chat message — prevents spam
    private let charLimit = 150
    /// 🔧 RATE LIMIT: min 1s between chat messages
    @State private var lastSendTime: Date = .distantPast

    // 🔧 Pack v3: Custom init — portrait mode doesn't require isPanelOpen
    init(messages: [ChatMessage], chatText: Binding<String>, onSend: @escaping () -> Void,
         currentUserID: String? = nil, mode: LayoutMode, isPanelOpen: Binding<Bool> = .constant(false)) {
        self.messages = messages
        self._chatText = chatText
        self.onSend = onSend
        self.currentUserID = currentUserID
        self.mode = mode
        self._isPanelOpen = isPanelOpen
    }

    enum LayoutMode {
        case portrait   // снизу под видео
        case landscape  // справа поверх видео
    }

    init(messages: [ChatMessage],
         chatText: Binding<String>,
         onSend: @escaping () -> Void,
         mode: LayoutMode,
         isPanelOpen: Binding<Bool> = .constant(true)) {
        self.messages = messages
        self._chatText = chatText
        self.onSend = onSend
        self.mode = mode
        self._isPanelOpen = isPanelOpen
    }

    var body: some View {
        switch mode {
        case .portrait:
            portraitLayout
        case .landscape:
            landscapeLayout
        }
    }

    // MARK: - Portrait (always visible, bottom of screen)

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // Заголовок
            chatHeader

            // Лента сообщений
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            RoomChatBubble(message: msg, currentUserID: currentUserID)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let lastID = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            // Эмодзи-пикер (показывается по кнопке)
            if showEmojiPicker {
                EmojiPickerGrid(chatText: $chatText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Поле ввода
            chatInputField
                .focused($isInputFocused)
        }
        .background(Color.black.opacity(0.15))
        .background(.ultraThinMaterial)
    }

    // MARK: - Landscape (slide-over from right)

    private var landscapeLayout: some View {
        GeometryReader { geo in
                let panelWidth: CGFloat = 260

            HStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    chatHeader
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(messages) { msg in
                                    RoomChatBubble(message: msg, compact: true, currentUserID: currentUserID)
                                        .id(msg.id)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastID = messages.last?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }

                    // Эмодзи-пикер для landscape
                    if showEmojiPicker {
                        EmojiPickerGrid(chatText: $chatText, compact: true)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    chatInputField
                        .focused($isInputFocused)
                }
                .frame(width: panelWidth)
                .background(Color.black.opacity(0.15))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .offset(x: isPanelOpen ? 0 : panelWidth + 16)
                .shadow(color: .black.opacity(0.3), radius: 8, x: -3)
                // 🔧 FIX CHAT SWIPE: Add drag gesture directly on the panel so it
                // can be swiped closed (rightward) even when it overlaps the video area.
                // The RoomView-level drag gesture doesn't fire here because the panel
                // intercepts touch events.
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            // Only close on rightward swipe (push panel back to the right)
                            if isPanelOpen && value.translation.width > 25 {
                                HapticManager.impact(.light)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isPanelOpen = false
                                }
                            }
                        }
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPanelOpen)
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack {
            Text(loc.string(.roomChat))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            if mode == .landscape {
                Button {
                    withAnimation(.spring()) { isPanelOpen = false }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Input Field

    private var chatInputField: some View {
        HStack(spacing: 8) {
            // Кнопка эмодзи
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmojiPicker.toggle()
                }
                // Скрываем клавиатуру при открытии пикера
                if showEmojiPicker { isInputFocused = false }
            } label: {
                Image(systemName: showEmojiPicker ? "keyboard.fill" : "face.smiling.fill")
                    .font(.system(size: 20))
                    .foregroundColor(showEmojiPicker ? .raveAccent : .white.opacity(0.6))
            }

            TextField(loc.string(.roomMessagePlaceholder), text: $chatText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .onSubmit {
                    // 🔧 RATE LIMIT: min 1s between chat messages
                    let now = Date()
                    guard now.timeIntervalSince(lastSendTime) >= 1 else { return }
                    lastSendTime = now
                    onSend()
                }
                .onChange(of: chatText) { _, newValue in
                    // 🔧 CHAR LIMIT: Truncate at 200 chars
                    if newValue.count > charLimit {
                        chatText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(chatText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .gray : .raveAccent)
            }
            .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Chat Bubble

struct RoomChatBubble: View {
    let message: ChatMessage
    var compact: Bool = false
    var currentUserID: String?

    /// True если сообщение от текущего пользователя
    private var isMyMessage: Bool {
        message.senderID == (currentUserID ?? UserDefaults.standard.string(forKey: "plink_current_user_id"))
    }

    private var avatarSize: CGFloat { compact ? 24 : 36 }
    private var textSize: CGFloat { compact ? 13 : 16 }
    private var nameSize: CGFloat { compact ? 11 : 14 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMyMessage {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        if message.isSenderAdmin {
                            AdminBadgeChip(compact: true)
                            Text(message.senderName)
                                .font(.system(size: nameSize, weight: .bold))
                                .adminShimmerText()
                        } else {
                            Text(message.senderName)
                                .font(.system(size: nameSize, weight: .bold))
                                .foregroundColor(.bioCyan)
                        }
                    }
                    Text(message.text)
                        .font(.system(size: textSize, weight: .medium))
                        .foregroundColor(.white)
                }
                myAvatar
            } else {
                otherAvatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if message.isSenderAdmin {
                            Text(message.senderName)
                                .font(.system(size: nameSize, weight: .bold))
                                .adminShimmerText()
                            AdminBadgeChip(compact: true)
                        } else {
                            Text(message.senderName)
                                .font(.system(size: nameSize, weight: .bold))
                                .foregroundColor(.bioCyan)
                        }
                    }
                    Text(message.text)
                        .font(.system(size: textSize, weight: .medium))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 10)
        // 🔧 FIX: simple background — no telegramGlass, no colored borders
        .background(
            isMyMessage
                ? Color.bioCyan.opacity(0.12)
                : Color.white.opacity(0.06)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16))
    }

    // MARK: - Avatars

    private var myAvatar: some View {
        avatarView
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
    }

    private var otherAvatar: some View {
        avatarView
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = message.senderAvatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    /// Fallback-аватарка с инициалами на цветном фоне
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: message.senderID))
            Text(message.initials)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundColor(.white)
        }
    }

    /// Детерминированный цвет аватарки по ID пользователя
    private func avatarColor(for id: String) -> Color {
        let palette: [Color] = [.ravePrimary, .raveAccent, .raveGreen, .raveWarning, .raveCyan, .raveSecondary]
        let hash = abs(id.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - Emoji Picker Grid
/// Сетка эмодзи для вставки в текст сообщения.
struct EmojiPickerGrid: View {
    @Binding var chatText: String
    var compact: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 36), spacing: 4)
    ]

    private let emojis: [String] = [
        "😀", "😂", "🥰", "😍", "😎", "🤔", "😴", "🥳",
        "😭", "😡", "🤯", "🤩", "😇", "🤗", "🤫", "😬",
        "👍", "👎", "👏", "🙌", "🙏", "💪", "🤝", "✌️",
        "🔥", "💯", "✨", "⚡", "🎉", "🎊", "🎁", "💎",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💔",
        "👀", "🍿", "🥤", "🍕", "🎵", "🎮", "📱", "💻",
        "⭐", "🌟", "🌈", "☀️", "🌙", "⚡", "💥", "💫",
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        HapticManager.impact(.light)
                        chatText += emoji
                    } label: {
                        Text(emoji)
                            .font(.system(size: compact ? 20 : 24))
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: compact ? 120 : 180)
        .background(Color.black.opacity(0.4))
        .background(.ultraThinMaterial)
    }
}
