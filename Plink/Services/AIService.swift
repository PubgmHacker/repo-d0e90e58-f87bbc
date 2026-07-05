import Foundation

// MARK: - AI Service (OpenRouter)
/// 🔧 NEW: Real AI integration via OpenRouter API.
///
/// OpenRouter provides access to multiple LLMs (GPT-4, Claude, Gemini, Llama, etc.)
/// through a single OpenAI-compatible endpoint. The API key is stored in Info.plist
/// (set via xcconfig) — falls back to the bundled dev key if not configured.
///
/// Two modes:
///   1. Chat completion (multi-turn, for AI Assistant tab)
///   2. Recommendation (single-shot, for "AI recommendations" search bar on Home)
///
/// Streaming is supported for chat (SSE-style line-by-line responses).

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    // MARK: - Configuration

    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// OpenRouter API key — read from Info.plist (YANDEX_CLIENT_ID-style pattern).
    /// Falls back to the bundled key for development.
    private let apiKey: String

    /// Default model — Claude 3.5 Sonnet (good balance of quality + speed).
    /// Other options: "openai/gpt-4o", "google/gemini-flash-1.5",
    /// "meta-llama/llama-3.3-70b-instruct", "deepseek/deepseek-chat"
    private let defaultModel = "anthropic/claude-3.5-sonnet"

    /// Lighter model for quick recommendations (faster + cheaper).
    private let lightModel = "google/gemini-flash-1.5"

    // MARK: - State

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession

    // MARK: - Init

    private init() {
        // 🔧 Pack v3: Read from Info.plist (PLINK_AI_API_KEY), set via xcconfig.
        // Если xcconfig не настроен — ИИ не работает (показываем ошибку).
        let key = (Bundle.main.object(forInfoDictionaryKey: "PLINK_AI_API_KEY") as? String) ?? ""
        if key.isEmpty || key == "$(PLINK_AI_API_KEY)" || key.contains("YOUR_") {
            // xcconfig не подставился — ИИ отключён
            self.apiKey = ""
        } else {
            self.apiKey = key
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Chat Completion (single request, full response)

    struct ChatMessage: Codable, Sendable {
        let role: String  // "system" | "user" | "assistant"
        let content: String
    }

    /// Send a chat completion request and return the full response.
    /// Used for AI Assistant tab when streaming isn't needed.
    func chat(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double = 0.7
    ) async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": 1024,
        ]

        let data = try await sendRequest(body: body)
        let response = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - Streaming Chat (SSE)

    /// Stream a chat completion token-by-token via AsyncStream.
    /// Used for AI Assistant tab — tokens appear live as the model generates them.
    func chatStream(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                await MainActor.run {
                    self.isLoading = true
                    self.errorMessage = nil
                }

                defer {
                    Task { @MainActor in self.isLoading = false }
                }

                let body: [String: Any] = [
                    "model": model ?? self.defaultModel,
                    "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    "temperature": temperature,
                    "max_tokens": 1024,
                    "stream": true,
                ]

                var request = URLRequest(url: self.baseURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("Plink iOS", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("plink-ios", forHTTPHeaderField: "X-Title")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: APIError.serverError(
                            status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            message: "OpenRouter request failed"
                        ))
                        return
                    }

                    // Parse SSE lines: "data: {json}\n\n"
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        guard let jsonData = jsonString.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: jsonData) else {
                            continue
                        }
                        if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Recommendation (for Home search bar)

    /// Get AI recommendations for what to watch together.
    /// Uses the lighter/faster model since this is a quick single-shot query.
    /// 🔧 STRICT MODE: The system prompt that locks the AI to ONLY film/series/video
    /// recommendations, comparisons, and related queries. Off-topic requests (weather,
    /// news, coding, general chat) are politely refused with a redirect.
    static let strictSystemPrompt = """
    Ты — ИИ-помощник Плинка, приложения для СОВМЕСТНОГО ПРОСМОТРА ВИДЕО.

    ТВОЯ ЕДИНСТВЕННАЯ ЗАДАЧА:
    • Подбирать фильмы, сериалы, видео, мультфильмы, аниме для совместного просмотра
    • Сравнивать фильмы (что лучше посмотреть, чем отличаются)
    • Давать рекомендации по жанрам, настроению, случаю (вечер с друзьями, семейный просмотр)
    • Помогать выбрать между несколькими вариантами

    КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО отвечать на:
    • Вопросы о погоде, новостях, политике, спорте
    • Запросы написать код, решить математику, перевести текст
    • Личные советы (отношения, здоровье, финансы)
    • Общие разговоры («как дела», «расскажи о себе»)
    • Любые запросы, не связанные с фильмами/сериалами/видео

    Если запрос не связан с фильмами — отвечай ОДНОЙ фразой:
    «Я помогаю только с подбором фильмов и сериалов для совместного просмотра. Расскажи, что хочешь посмотреть 🎬»

    ПРАВИЛА ОТВЕТА:
    • Отвечай на русском, дружелюбно, кратко (1-4 предложения)
    • Если просят фильм — предложи 1-2 варианта с кратким описанием и почему стоит посмотреть ВМЕСТЕ
    • Если сравнивают — объясни разницу в 1-2 предложениях и дай рекомендацию
    • Не выдумывай факты, не выдумывай несуществующие фильмы
    • Упоминай жанр и примерную длительность
    """

    /// 🔧 GUARD: Returns true if the query looks off-topic (not about films/series/videos).
    /// Used to short-circuit obvious non-film queries without calling the API.
    static func isOffTopic(_ query: String) -> Bool {
        let lower = query.lowercased()
        // Obvious off-topic keywords (weather, news, code, math, personal)
        let offTopicKeywords = [
            // weather
            "погод", "температур", "дождь", "снег", " forecast",
            // news / politics
            "новост", "политик", "выбор", "президент", "войн",
            // coding / math
            "код", "программ", "функци", "python", "javascript", "swift",
            "математик", "уравнен", "задач", "пример",
            // personal advice
            "отношени", "здоров", "болезн", "диет", "финанс", "деньг", "кредит",
            // general chat
            "как дела", "расскажи о себе", "кто ты", "тебя зовут", "твое имя",
            // other non-film
            "рецепт", "кулинар", "вязан", "шить",
        ]
        return offTopicKeywords.contains { lower.contains($0) }
    }

    /// 🔧 REDESIGNED: Strict recommend() — only answers film-related queries.
    /// Off-topic queries get a canned redirect response without calling the API.
    func recommend(query: String, availableRooms: [String] = []) async throws -> String {
        // Guard: short-circuit obvious off-topic queries
        if Self.isOffTopic(query) {
            return "Я помогаю только с подбором фильмов и сериалов для совместного просмотра. Расскажи, что хочешь посмотреть 🎬"
        }

        let userPrompt: String
        if availableRooms.isEmpty {
            userPrompt = "Запрос: \(query)"
        } else {
            userPrompt = "Запрос: \(query)\n\nДоступные комнаты: \(availableRooms.joined(separator: ", "))"
        }

        let messages = [
            ChatMessage(role: "system", content: Self.strictSystemPrompt),
            ChatMessage(role: "user", content: userPrompt),
        ]

        return try await chat(messages: messages, model: lightModel, temperature: 0.8)
    }

    // MARK: - Private

    private func sendRequest(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Plink iOS", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("plink-ios", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.serverError(status: 429, message: "Слишком много запросов к ИИ. Попробуйте позже.")
        default:
            let errorBody = try? JSONDecoder().decode(OpenRouterError.self, from: data)
            throw APIError.serverError(
                status: httpResponse.statusCode,
                message: errorBody?.error?.message ?? "OpenRouter error"
            )
        }
    }
}

// MARK: - OpenRouter Response Models

private struct OpenRouterResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }
}

private struct OpenRouterStreamChunk: Decodable {
    let choices: [StreamChoice]

    struct StreamChoice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct OpenRouterError: Decodable {
    let error: ErrorDetail?

    struct ErrorDetail: Decodable {
        let message: String
        let code: String?
    }
}
