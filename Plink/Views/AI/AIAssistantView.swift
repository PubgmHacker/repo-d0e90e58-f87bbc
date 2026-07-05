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
    @State private var showHistory = false  // 🔧 NEW: AI history sheet

    /// 🔧 CHAR LIMIT: 150 chars max per message — prevents spam + API abuse
    private let charLimit = 150
    /// 🔧 RATE LIMIT: min 2s between messages — prevents spam
    @State private var lastSendTime: Date = .distantPast

    private let storageKey = "ai_chat_history"
    /// 🔧 NEW: separate key for ALL past sessions (history of queries)
    private let allHistoryKey = "ai_all_queries_history"

    var body: some View {
        NavigationStack {
            ZStack {
                // 🔧 AI: собственная amber-палитра (отличается от Home/Rooms)
                // Тёплые янтарные/золотые орбы — премиум-чувство
                BioluminescentBackground(energy: 0.75, dimming: 0, palette: .amber)
                    .ignoresSafeArea()

                // Лёгкое затемнение для читаемости сообщений
                Color.black.opacity(0.25).ignoresSafeArea()

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
            .toolbar {
                // 🔧 NEW: left — history of all AI queries
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.raveTextSecondary)
                    }
                }
                // 🔧 NEW: right — new chat (clears current, starts fresh)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.impact(.medium)
                        // Save current queries to all-history before clearing
                        saveToAllHistory()
                        withAnimation {
                            messages.removeAll()
                            UserDefaults.standard.removeObject(forKey: storageKey)
                        }
                    } label: {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.bioAmber)
                    }
                    .disabled(messages.isEmpty)
                    .opacity(messages.isEmpty ? 0.4 : 1)
                }
            }
            .sheet(isPresented: $showHistory) {
                AIHistorySheet(allHistoryKey: allHistoryKey) { selectedQuery in
                    // 🔧 Load query from history into chat
                    inputText = selectedQuery
                    sendMessage()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadHistory() }
    }

    // MARK: - Welcome Section
    //
    // 🔧 PREMIUM AI: стеклянная карточка с amber акцентом + премиум-иконка
    private var welcomeSection: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            VStack(spacing: 18) {
                ZStack {
                    // 🔧 Premium: двойное кольцо вокруг иконки
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
            // 🔧 TELEGRAM-STYLE: прозрачное стекло + металлическая обводка
            .telegramGlass(cornerRadius: 24, borderColor: Color.bioAmber.opacity(0.3))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Quick Chips
    //
    // 🔧 PREMIUM: telegram-glass chips с amber tintом
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
                            // 🔧 TELEGRAM-STYLE glass chips
                            .telegramGlass(cornerRadius: 18, borderColor: Color.bioAmber.opacity(0.25))
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
    // 🔧 PREMIUM: telegram-glass input + amber send button
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Спросите что угодно...", text: $inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundColor(.raveTextPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // 🔧 TELEGRAM-STYLE glass input
                .telegramGlass(cornerRadius: 22, borderColor: Color.bioAmber.opacity(0.2))
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
                    // 🔧 AI: amber→coral gradient (matches welcome card)
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
            // 🔧 Top edge accent — amber gradient line
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
            var gotTokens = false
            for try await token in stream {
                gotTokens = true
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[idx].text += token
                    }
                }
            }
            // 🔧 FALLBACK: if streaming returned no tokens, try non-streaming
            if !gotTokens {
                let response = try await AIService.shared.chat(messages: allMessages)
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[idx].text = response
                    }
                    self.isLoading = false
                    self.saveHistory()
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.saveHistory()
                }
            }
        } catch {
            // 🔧 FALLBACK: streaming failed → try non-streaming
            do {
                let response = try await AIService.shared.chat(messages: allMessages)
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[idx].text = response
                    }
                    self.isLoading = false
                    self.saveHistory()
                }
            } catch {
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                        if self.messages[idx].text.isEmpty {
                            self.messages[idx].text = "⚠️ Не удалось получить ответ от ИИ. Попробуйте ещё раз."
                        }
                    }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
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

    /// 🔧 NEW: Save all user queries to persistent all-history.
    /// Called when starting a new chat — preserves past queries for history view.
    private func saveToAllHistory() {
        let userQueries = messages.filter { $0.role == .user }.map { $0.text }
        var existing = UserDefaults.standard.array(forKey: allHistoryKey) as? [[String: String]] ?? []
        let now = ISO8601DateFormatter().string(from: Date())
        for query in userQueries {
            existing.append(["query": query, "date": now])
        }
        // Keep last 100 queries
        if existing.count > 100 {
            existing = Array(existing.suffix(100))
        }
        UserDefaults.standard.set(existing, forKey: allHistoryKey)
    }
}

// MARK: - AI History Sheet
/// 🔧 Shows all past AI queries in glass cards. Tap to reload, swipe to delete.
struct AIHistorySheet: View {
    let allHistoryKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var queries: [(query: String, date: String)] = []
    var onSelectQuery: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BioluminescentBackground(energy: 0.4, dimming: 0, palette: .amber)
                    .ignoresSafeArea()

                if queries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundColor(.raveTextTertiary)
                        Text("История запросов пуста")
                            .font(.subheadline)
                            .foregroundColor(.raveTextSecondary)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(queries.enumerated()), id: \.offset) { index, item in
                                Button {
                                    onSelectQuery?(item.query)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        // 🔧 Glass circle icon
                                        ZStack {
                                            Circle()
                                                .fill(Color.bioAmber.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 14))
                                                .foregroundColor(.bioAmber)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.query)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.raveTextPrimary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            if !item.date.isEmpty {
                                                Text(formatDate(item.date))
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.raveTextTertiary)
                                            }
                                        }

                                        Spacer(minLength: 4)

                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.raveTextTertiary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    // 🔧 LIQUID GLASS card
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        Color.bioAmber.opacity(0.2),
                                                        Color.white.opacity(0.04)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.5
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        _ = withAnimation(.easeOut(duration: 0.25)) {
                                            queries.remove(at: index)
                                        }
                                        saveQueries()
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.bioAmber)
                }
                if !queries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                queries.removeAll()
                            }
                            saveQueries()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.raveDanger)
                        }
                    }
                }
            }
            .onAppear { loadQueries() }
        }
        .preferredColorScheme(.dark)
    }

    private func loadQueries() {
        let data = UserDefaults.standard.array(forKey: allHistoryKey) as? [[String: String]] ?? []
        queries = data.reversed().compactMap { dict in
            guard let q = dict["query"] else { return nil }
            let d = dict["date"] ?? ""
            return (query: q, date: d)
        }
    }

    private func saveQueries() {
        let toSave = queries.reversed().map { ["query": $0.query, "date": $0.date] }
        UserDefaults.standard.set(toSave, forKey: allHistoryKey)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        return date.formatted(.relative(presentation: .named))
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
                .modifier(AIBubbleBackground(role: message.role))
            }

            if message.role == .ai { Spacer() }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - AI Bubble Background Modifier
//
// 🔧 PREMIUM: раздельные стили для user / AI bubble.
// User — amber→coral gradient fill (premium-look).
// AI — telegram-glass (прозрачное стекло + металлическая обводка).
private struct AIBubbleBackground: ViewModifier {
    let role: AIMessage.Role

    func body(content: Content) -> some View {
        switch role {
        case .user:
            content
                .background(
                    LinearGradient(
                        colors: [Color.bioAmber, Color.bioCoral],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: Color.bioAmber.opacity(0.3), radius: 6, y: 2)
        case .ai:
            content
                .telegramGlass(cornerRadius: 18, borderColor: Color.bioAmber.opacity(0.25))
        }
    }
}
