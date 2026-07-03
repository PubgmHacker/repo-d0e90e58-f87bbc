import SwiftUI

// MARK: - AI Assistant View (полноэкранный чат с ИИ)
/// Отдельная вкладка TabBar. ИИ рекомендует контент по текстовым запросам.
/// История диалогов сохраняется локально в UserDefaults.
struct AIAssistantView: View {
    @State private var messages: [AIMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

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
                                    AIMessageBubble(message: msg)
                                        .id(msg.id)
                                }

                                if isLoading {
                                    HStack {
                                        AITypingIndicator()
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: messages.count) { _, _ in
                            withAnimation {
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

    private var welcomeSection: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.bioCyan, Color.raveAccent],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.ravePrimary.opacity(0.4), radius: 20, y: 8)

            VStack(spacing: 8) {
                Text("Что посмотреть?")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Text("Опиши настроение — подберу идеальный фильм")
                    .font(.subheadline)
                    .foregroundColor(.raveTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Quick Chips

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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassCard(cornerRadius: 16, opacity: 0.06)
                            .overlay(
                                Capsule()
                                    .stroke(Color.ravePrimary.opacity(0.2), lineWidth: 0.5)
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Спросите что угодно...", text: $inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundColor(.raveTextPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 22, opacity: 0.06)
                .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.raveGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: .ravePrimary.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let query = inputText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isLoading else { return }

        let userMsg = AIMessage(id: UUID().uuidString, role: .user, text: query, timestamp: Date())
        messages.append(userMsg)
        inputText = ""
        saveHistory()

        isLoading = true
        Task {
            let response = await getAIResponse(for: query)
            await MainActor.run {
                let aiMsg = AIMessage(id: UUID().uuidString, role: .ai, text: response, timestamp: Date())
                self.messages.append(aiMsg)
                self.isLoading = false
                self.saveHistory()
            }
        }
    }

    // MARK: - AI Response (mock + ready for real API)

    private func getAIResponse(for query: String) async -> String {
        // TODO: подключить реальный API (POST /api/ai/ask)
        // Структура готова — достаточно заменить этот метод на:
        // struct Body: Encodable { let query: String }
        // let resp: AIResponse = try await api.request("ai/ask", method: .post, body: Body(query: query))
        // return resp.answer

        try? await Task.sleep(nanoseconds: 800_000_000)  // имитация задержки

        return MockAIResponses.response(for: query)
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
    let text: String
    let timestamp: Date
}

// MARK: - AI Message Bubble
struct AIMessageBubble: View {
    let message: AIMessage

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
                    }
                    .foregroundColor(.ravePrimary)
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(message.role == .user ? .white : .raveTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.raveGradient)
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        // Тонкая стеклянная обводка для AI-сообщений
                        Group {
                            if message.role == .ai {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            }
                        }
                    )
            }

            if message.role == .ai { Spacer() }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - AI Typing Indicator
struct AITypingIndicator: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.ravePrimary)
                    .frame(width: 8, height: 8)
                    .offset(y: offset)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: offset
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .onAppear {
            offset = -6
        }
    }
}

// MARK: - Mock AI Responses
enum MockAIResponses {
    static func response(for query: String) -> String {
        let lower = query.lowercased()

        if lower.contains("ужас") || lower.contains("хоррор") {
            return """
            🎬 Вот отличные фильмы ужасов 2024:

            **«Длинные ноги» (Longlegs)**
            Триллер с Николасом Кейджем. Мрачная атмосфера Финча, FBI расследует серию убийств. Озноб guaranteed.

            **«Тихое место: День первый»**
            Приквел культового фильма. Как всё началось в Нью-Йорке. Менее страшно, но очень напряжно.

            **«Прорва» (Oddity)**
            Ирландский хоррор. Женщина с даром ясновидения расследует смерть сестры. Жуткий и стильный.
            """
        }

        if lower.contains("новинк") || lower.contains("2025") || lower.contains("лучшие") {
            return """
            🔥 Топ новинок 2025:

            **«Дюна: Часть третья»**
            Завершение эпопеи Вильнёва. Визуальный шедевр — стоит смотреть в 4K с друзьями.

            **«Миссия невыполнима: Финал»**
            Последняя часть с Томом Крузом. Трюки, которых ещё не было в кино.

            **«Зверополис 2»**
            Долгожданное продолжение. Отлично для просмотра всей семьёй.

            Создай комнату и смотри с друзьями! 🍿
            """
        }

        if lower.contains("вечер") || lower.contains("сегодня") || lower.contains("посмотреть") {
            return """
            🎯 Подобрал для вечера:

            **«Интерстеллар»** — если хочется подумать и поплакать. 3 часа чистого восторга.

            **«Омерзительная восьмёрка»** — диалоги Тарантино, снег, интрига. Идеально для компании.

            **«Гордость и предубеждение»** — если нужен уютный вечер.

            Что из этого ближе? 🎬
            """
        }

        if lower.contains("комеди") || lower.contains("смешн") {
            return """
            😂 Лучшие комедии:

            **«Евротур»** — классика, всегда смешно.

            **«Отель "Гранд Будапешт"»** — эстетика Андерсона + юмор.

            **«Достать ножи»** — детективная комедия, держит до конца.
            """
        }

        // Default
        return """
        Расскажи подробнее, что хочется посмотреть! 🎬

        Могу подобрать по жанру, настроению или году. Например:
        • «Посоветуй фантастический фильм»
        • «Хочу плакать весь вечер»
        • «Что-то лёгкое и весёлое»
        """
    }
}
