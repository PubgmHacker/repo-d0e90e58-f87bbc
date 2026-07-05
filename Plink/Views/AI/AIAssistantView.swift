import SwiftUI

// MARK: - AI Assistant View (полноэкранный чат с ИИ)
/// Отдельная вкладка TabBar. ИИ рекомендует контент по текстовым запросам.
/// История диалогов сохраняется локально в UserDefaults.
struct AIAssistantView: View {
    @State private var messages: [AIMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    /// 🔧 CHAR LIMIT: 150 chars max per message — prevents spam + API abuse
    private let charLimit = 150
    /// 🔧 RATE LIMIT: min 2s between messages — prevents spam
    @State private var lastSendTime: Date = .distantPast

    private let storageKey = "ai_chat_history"

    var body: some View {
        NavigationStack {
            ZStack {
                // Живой фон ЗА карточками
                AnimatedGradientBackground(orbColors: [Color(hex: 0x7B2CBF), Color.bioCyan, Color.raveAccent])

                // Лёгкое затемнение для читаемости сообщений
                Color.black.opacity(0.3).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Чат
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 14) {
                                if messages.isEmpty {
                                    welcomeSection
                                }

                                ForEach(messages) { msg in
                                    AIMessageBubble(message: msg, isStreaming: isLoading && msg.id == messages.last?.id && msg.role == .ai)
                                        .id(msg.id)
                                }

                                // 🔧 Removed AITypingIndicator — the streaming
                                // AI message itself shows a pulsing cursor while
                                // tokens arrive. No separate typing bubble needed.
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: messages.count) { _, _ in
                            withAnimation {
                                proxy.scrollTo(messages.last?.id, anchor: .bottom)
                            }
                        }
                        // 🔧 Scroll while streaming — when text grows, keep pinned to bottom
                        .onChange(of: messages.last?.text) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(messages.last?.id, anchor: .bottom)
                            }
                        }
                    }

                    // Быстрые подсказки
                    if messages.isEmpty {
                        quickChips
                    }

                    // Поле ввода
                    inputBar
                }
            }
            .navigationTitle("ИИ-помощник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadHistory() }
    }

    // MARK: - Welcome Section
    //
    // 🔧 STYLED: was plain VStack with bare circle + text. Now: glass card
    // with gradient border + warm amber accent (was cyan-only) for visual
    // diversity across tabs.
    private var welcomeSection: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            VStack(spacing: 18) {
                ZStack {
                    // 🔧 DIVERSITY: warm amber→coral gradient (was cyan-only)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.bioAmber, Color.bioCoral],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 84, height: 84)
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.bioAmber.opacity(0.5), radius: 18, y: 6)
                .glowPulse(color: Color.bioAmber, minRadius: 14, maxRadius: 26, minOpacity: 0.2, maxOpacity: 0.6, period: 2.4)

                VStack(spacing: 8) {
                    Text("Что посмотреть?")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.raveTextPrimary)
                    Text("Спроси ИИ — подберёт фильм, сериал или видео для совместного просмотра")
                        .font(.subheadline)
                        .foregroundColor(.raveTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.bioObsidian.opacity(0.3))
                    )
            )
            .overlay(
                // 🔧 DIVERSITY: amber→coral gradient border (was cyan)
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.bioAmber.opacity(0.35),
                                Color.bioCoral.opacity(0.15),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.bioAmber.opacity(0.12), radius: 16, y: 4)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Quick Chips
    //
    // 🔧 STYLED: was plain glass capsules with cyan border. Now: warm amber
    // accent gradient border for diversity (matches welcome card palette).
    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        inputText = prompt
                        sendMessage()
                    } label: {
                        Text(prompt)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.raveTextPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .background(
                                        Capsule().fill(Color.bioObsidian.opacity(0.3))
                                    )
                            )
                            .overlay(
                                // 🔧 DIVERSITY: amber→emerald gradient border (was cyan-only)
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.bioAmber.opacity(0.4),
                                                Color.bioEmerald.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private let quickPrompts = [
        "Что посмотреть сегодня?",
        "Лучшие новинки 2025",
        "Подбери фильм на вечер",
        "Фильм ужасов 2024",
    ]

    // MARK: - Input Bar
    //
    // 🔧 STYLED: was plain `.ultraThinMaterial`. Now: glass with warm amber
    // gradient border on top edge (subtle accent, matches welcome card).
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Спросите что угодно...", text: $inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundColor(.raveTextPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.bioObsidian.opacity(0.3))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.bioAmber.opacity(0.25),
                                    Color.bioEmerald.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .focused($isInputFocused)
                .onChange(of: inputText) { _, newValue in
                    if newValue.count > charLimit {
                        inputText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }

            Button {
                sendMessage()
            } label: {
                ZStack {
                    // 🔧 DIVERSITY: amber→coral gradient (was cyan-only raveGradient)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.bioAmber, Color.bioCoral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.bioAmber.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            // 🔧 Top edge accent — subtle warm gradient line
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.bioAmber.opacity(0.4),
                        Color.bioCoral.opacity(0.2),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 0.5)
                Spacer()
            }
        )
        .background(.ultraThinMaterial)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let query = inputText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isLoading else { return }

        // 🔧 RATE LIMIT: min 2s between messages
        let now = Date()
        if now.timeIntervalSince(lastSendTime) < 2 {
            HapticManager.impact(.light)
            return
        }
        lastSendTime = now

        let userMsg = AIMessage(id: UUID().uuidString, role: .user, text: query, timestamp: Date())
        messages.append(userMsg)
        inputText = ""
        saveHistory()

        isLoading = true

        // 🔧 REAL AI: Create an empty AI message and stream tokens into it
        let aiMsgId = UUID().uuidString
        let aiMsg = AIMessage(id: aiMsgId, role: .ai, text: "", timestamp: Date())
        messages.append(aiMsg)

        Task {
            await streamAIResponse(into: aiMsgId, userQuery: query)
        }
    }

    // MARK: - AI Response (real OpenRouter API with streaming)

    /// 🔧 NEW: Real AI integration via OpenRouter. Streams tokens live into the
    /// AI message bubble identified by `messageId` — tokens appear as they're
    /// generated, like ChatGPT.
    ///
    /// 🔧 STRICT MODE: Uses AIService.strictSystemPrompt — only film/series/video
    /// queries are answered. Off-topic queries get a canned redirect response.
    private func streamAIResponse(into messageId: String, userQuery: String) async {
        // 🔧 Guard: short-circuit obvious off-topic queries without calling the API
        if AIService.isOffTopic(userQuery) {
            await MainActor.run {
                if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[idx].text = "Я помогаю только с подбором фильмов и сериалов для совместного просмотра. Расскажи, что хочешь посмотреть 🎬"
                }
                self.isLoading = false
                self.saveHistory()
            }
            return
        }

        // Build conversation context from history (last 10 messages)
        let historyMessages = messages.suffix(10).map { msg in
            AIService.ChatMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.text
            )
        }

        // 🔧 STRICT: Use the locked-down system prompt (films only)
        let systemMessage = AIService.ChatMessage(
            role: "system",
            content: AIService.strictSystemPrompt
        )

        let allMessages = [systemMessage] + historyMessages

        do {
            let stream = AIService.shared.chatStream(messages: allMessages)
            for try await token in stream {
                await MainActor.run {
                    // Append token to the AI message's text
                    if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[idx].text += token
                    }
                }
            }
            await MainActor.run {
                self.isLoading = false
                self.saveHistory()
            }
        } catch {
            await MainActor.run {
                // If we got no tokens at all, show the error in the message bubble
                if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                    if self.messages[idx].text.isEmpty {
                        self.messages[idx].text = "⚠️ Не удалось получить ответ от ИИ. Проверьте интернет-соединение и попробуйте снова."
                    }
                }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func saveHistory() {
        let data = messages.map { msg in
            ["id": msg.id, "role": msg.role.rawValue, "text": msg.text]
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.array(forKey: storageKey) as? [[String: String]] else { return }
        messages = data.compactMap { dict in
            guard let id = dict["id"], let roleStr = dict["role"], let text = dict["text"],
                  let role = AIMessage.Role(rawValue: roleStr) else { return nil }
            return AIMessage(id: id, role: role, text: text, timestamp: Date())
        }
    }
}

// MARK: - AI Message Model
struct AIMessage: Identifiable {
    enum Role: String {
        case user, ai
    }

    let id: String
    let role: Role
    /// 🔧 Made `var` so streaming can append tokens live without creating a new AIMessage.
    var text: String
    let timestamp: Date
}

// MARK: - AI Message Bubble
struct AIMessageBubble: View {
    let message: AIMessage
    /// 🔧 When true, shows a pulsing cursor at the end of the text (streaming).
    var isStreaming: Bool = false

    @State private var cursorVisible: Bool = true

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .ai {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("ИИ")
                            .font(.system(size: 11, weight: .bold))
                        if isStreaming {
                            Text("печатает…")
                                .font(.system(size: 10))
                                .foregroundColor(.raveTextTertiary)
                        }
                    }
                    .foregroundColor(.ravePrimary)
                }

                HStack(alignment: .bottom, spacing: isStreaming ? 2 : 0) {
                    Text(message.text.isEmpty && isStreaming ? " " : message.text)
                        .font(.system(size: 15))
                        .foregroundColor(message.role == .user ? .white : .raveTextPrimary)

                    // 🔧 Streaming cursor — pulsing block at the end of text
                    if isStreaming && !message.text.isEmpty {
                        Rectangle()
                            .fill(Color.bioAmber)  // 🔧 DIVERSITY: amber cursor (was cyan)
                            .frame(width: 2, height: 16)
                            .opacity(cursorVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                            .onAppear { cursorVisible = false }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(
                            // 🔧 DIVERSITY: user bubble — amber→coral gradient (was cyan raveGradient)
                            LinearGradient(
                                colors: [Color.bioAmber, Color.bioCoral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    // 🔧 DIVERSITY: AI bubble — amber tint border (was white-only)
                    Group {
                        if message.role == .ai {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.bioAmber.opacity(0.25),
                                            Color.bioEmerald.opacity(0.1),
                                            Color.white.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                    }
                )
            }

            if message.role == .ai { Spacer() }
        }
        .padding(.horizontal, 20)
    }
}
