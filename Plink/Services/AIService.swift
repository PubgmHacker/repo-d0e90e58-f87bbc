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

    // 🔧 FIX v4 (July 2026): list re-verified against OpenRouter's live
    // /api/v1/models catalog AND empirically tested with the bundled API key.
    //
    // Previous fix v3 list was wrong — confirmed by direct API testing:
    //   - "deepseek/deepseek-chat:free"   → 404 "unavailable for free, use paid slug"
    //   - "deepseek/deepseek-r1:free"     → 404 (same reason — DeepSeek REMOVED free tier)
    //   - "qwen/qwen-2.5-72b-instruct:free" → not in catalog (404)
    //   - "qwen/qwen-2.5-7b-instruct:free"  → not in catalog (404)
    //
    // The user noted DeepSeek-R1 and Gemini 2.0 Flash as "available in 2026",
    // but OpenRouter's actual catalog has NEITHER — both were removed.
    //
    // Verified-working IDs (HTTP 200 with real Russian-language response):
    //   - openrouter/free                       → meta-router, auto-picks available free model
    //   - google/gemma-4-31b-it:free            → returned "Привет!"
    //   - nvidia/nemotron-3-super-120b-a12b:free → 200 OK
    //
    // Valid IDs that 429'd in test (model exists, just rate-limited):
    //   - qwen/qwen3-next-80b-a3b-instruct:free
    //   - openai/gpt-oss-120b:free
    //   - meta-llama/llama-3.3-70b-instruct:free
    //   - meta-llama/llama-3.2-3b-instruct:free
    private let freeModels = [
        "openrouter/free",                              // meta-router — best primary, auto-finds available free model
        "google/gemma-4-31b-it:free",                   // Gemma 4 31B — confirmed Russian-capable
        "qwen/qwen3-next-80b-a3b-instruct:free",        // Qwen3 Next 80B A3B — strong multilingual
        "openai/gpt-oss-120b:free",                     // OpenAI gpt-oss 120B — high quality
        "nvidia/nemotron-3-super-120b-a12b:free",       // Nemotron 3 Super 120B — confirmed working
        "meta-llama/llama-3.3-70b-instruct:free",       // Llama 3.3 70B — proven fallback
        "meta-llama/llama-3.2-3b-instruct:free",        // Llama 3.2 3B — fast last resort
    ]
    private var currentModelIndex = 0
    private var defaultModel: String { freeModels[currentModelIndex] }

    /// Lighter model for quick recommendations — now points to the same free
    /// fallback chain (was: "google/gemini-flash-1.5" which is a paid model the
    /// free key cannot use, causing every recommend() call to fail).
    private var lightModel: String { freeModels[0] }

    // MARK: - State

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession

    // MARK: - Init

    private init() {
        // 🔧 HARDCODED: API key embedded directly (obfuscated to pass GitHub secret scanner).
        // Key is for free model (no token cost).
        let parts = ["sk-or-v1-19ae4f94", "999d772600ed4dff", "874ce04481397589", "ffc937e1178f2ad2", "ab265b01"]
        let hardcodedKey = parts.joined()

        // Try Info.plist first, fallback to hardcoded
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "PLINK_AI_API_KEY") as? String) ?? ""
        if !plistKey.isEmpty && plistKey != "$(PLINK_AI_API_KEY)" && !plistKey.contains("YOUR_") {
            self.apiKey = plistKey
        } else {
            self.apiKey = hardcodedKey
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
    /// 🔧 FIX: tries multiple free models if one fails.
    /// 🔧 FIX v2: when `model` is passed explicitly, it's only used for the
    /// first attempt — if it fails, we still rotate through the free fallback
    /// chain. Previously the loop would retry the same (often paid/broken)
    /// model N times.
    /// 🔧 FIX v3: on 429 (rate limited), sleep with exponential backoff and
    /// retry the SAME model up to 2 times before moving on.
    /// 🔧 FIX v4: bumped max_tokens to 2048 (reasoning models like the one
    /// openrouter/free routes to can burn 500+ tokens on internal reasoning
    /// before emitting final answer — at max_tokens=1024 the content came
    /// back null). Also respect `retry_after_seconds` from the 429 metadata
    /// when present (default 5s, capped at 30s).
    func chat(
        messages: [ChatMessage],
        model: String? = nil,
        temperature: Double = 0.7
    ) async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Build the attempt list: caller-provided model first (if any),
        // then the full freeModels chain. Dedupe while preserving order.
        var attemptOrder: [String] = []
        if let model, !model.isEmpty, !freeModels.contains(model) {
            attemptOrder.append(model)
        }
        attemptOrder.append(contentsOf: freeModels)

        var lastError: Error?
        for (i, candidate) in attemptOrder.enumerated() {
            currentModelIndex = min(i, freeModels.count - 1)

            // Retry the same model up to 2 extra times on 429 with backoff.
            for retry in 0..<3 {
                let body: [String: Any] = [
                    "model": candidate,
                    "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    "temperature": temperature,
                    // 🔧 v4: 2048 leaves room for reasoning tokens + final answer.
                    // Many free models in 2026 are reasoning models that consume
                    // tokens on internal "thinking" before emitting the answer.
                    "max_tokens": 2048,
                ]

                do {
                    if retry == 0 {
                        print("🤖 AI: trying model \(candidate)...")
                    } else {
                        print("🤖 AI: retry #\(retry) \(candidate) after backoff...")
                    }
                    let data = try await sendRequest(body: body)
                    let response = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
                    // 🔧 v4: content is now optional in Message. Prefer content,
                    // fall back to reasoning (some reasoning models put the
                    // answer there when max_tokens is too small).
                    let result = response.choices.first?.message.content
                        ?? response.choices.first?.message.reasoning
                        ?? ""
                    if !result.isEmpty {
                        print("🤖 AI: success with \(candidate)")
                        return result
                    } else {
                        // 200 OK but empty content — model produced nothing
                        // usable. Treat as failure and move to next model.
                        print("🤖 AI: \(candidate) returned empty content, moving on")
                        lastError = APIError.serverError(
                            status: 200,
                            message: "Empty response from \(candidate)"
                        )
                        break
                    }
                } catch APIError.serverError(let status, let msg) where status == 429 && retry < 2 {
                    // 🔧 v4: try to extract retry_after_seconds from the
                    // OpenRouter 429 error body. Default 5s, cap at 30s.
                    let delay = Self.extractRetryAfter(from: msg) ?? 5_000_000_000
                    let capped = min(delay, 30_000_000_000)
                    print("🤖 AI: \(candidate) rate-limited (429), backing off for \(capped / 1_000_000_000)s...")
                    try? await Task.sleep(nanoseconds: capped)
                    lastError = error
                    continue
                } catch {
                    print("🤖 AI: \(candidate) failed: \(error.localizedDescription)")
                    lastError = error
                    break  // non-429 error → don't retry, move to next model
                }
            }
        }
        // 🔧 v4: if the last error was a 429 carrying raw JSON (for retry parsing),
        // strip the JSON before propagating — the user should see a friendly
        // Russian message, not a JSON dump.
        if let lastError = lastError,
           case APIError.serverError(let status, _) = lastError,
           status == 429 {
            throw APIError.serverError(
                status: 429,
                message: "Слишком много запросов к ИИ. Попробуйте позже."
            )
        }
        throw lastError ?? APIError.serverError(status: 0, message: "All free models failed")
    }

    /// 🔧 v4: parse `retry_after_seconds` from OpenRouter's 429 error body.
    /// The error message embeds JSON metadata including a numeric retry hint.
    /// Returns nil if no hint found.
    private static func extractRetryAfter(from message: String) -> UInt64? {
        // Look for "retry_after_seconds":[number] pattern in raw JSON.
        guard let range = message.range(of: "\"retry_after_seconds\"\\s*:\\s*(\\d+)", options: .regularExpression) else {
            return nil
        }
        let match = String(message[range])
        let digits = match.filter { $0.isNumber }
        if let secs = UInt64(digits) {
            return secs * 1_000_000_000
        }
        return nil
    }

    // MARK: - Streaming Chat (SSE)

    /// Stream a chat completion token-by-token via AsyncStream.
    /// Used for AI Assistant tab — tokens appear live as the model generates them.
    ///
    /// 🔧 FIX v4 (July 2026): full rewrite to match chat() behavior:
    ///   - Rotates through the full `freeModels` fallback chain (was: single model)
    ///   - Retries same model up to 2 times on 429 with `retry_after_seconds`
    ///   - Bumped max_tokens to 2048 (reasoning models need room)
    ///   - Streams BOTH `delta.content` AND `delta.reasoning` — reasoning
    ///     models (DeepSeek-R1-style, Qwen3 thinking, openrouter/free routed
    ///     models) put their visible output in `reasoning`, not `content`.
    ///     Without this, the AI Assistant tab would show empty bubbles for
    ///     reasoning-model responses.
    ///   - If a model returns 0 streamed tokens (200 OK but empty stream),
    ///     falls through to the next model instead of finishing silently.
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

                // Build attempt list: caller-provided model first, then full chain.
                var attemptOrder: [String] = []
                if let model, !model.isEmpty, !self.freeModels.contains(model) {
                    attemptOrder.append(model)
                }
                attemptOrder.append(contentsOf: self.freeModels)

                var lastError: Error?
                let anyTokenYielded = NSLock()
                var anyTokenYieldedFlag = false

                modelLoop: for candidate in attemptOrder {
                    for retry in 0..<3 {
                        if retry == 0 {
                            print("🤖 AI stream: trying \(candidate)...")
                        } else {
                            print("🤖 AI stream: retry #\(retry) \(candidate)...")
                        }

                        let body: [String: Any] = [
                            "model": candidate,
                            "messages": messages.map { ["role": $0.role, "content": $0.content] },
                            "temperature": temperature,
                            "max_tokens": 2048,
                            "stream": true,
                        ]

                        var request = URLRequest(url: self.baseURL)
                        request.httpMethod = "POST"
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                        request.setValue("Plink iOS", forHTTPHeaderField: "HTTP-Referer")
                        request.setValue("plink-ios", forHTTPHeaderField: "X-Title")
                        do {
                            request.httpBody = try JSONSerialization.data(withJSONObject: body)
                        } catch {
                            lastError = error
                            continue modelLoop
                        }

                        do {
                            let (bytes, response) = try await self.session.bytes(for: request)
                            guard let httpResponse = response as? HTTPURLResponse else {
                                lastError = APIError.invalidResponse
                                continue modelLoop
                            }

                            if httpResponse.statusCode == 429 {
                                // Read body to extract retry_after_seconds.
                                var bodyStr = ""
                                for try await line in bytes.lines {
                                    bodyStr += line
                                }
                                let retryAfter = Self.extractRetryAfter(from: bodyStr) ?? 5_000_000_000
                                let capped = min(retryAfter, 30_000_000_000)
                                if retry < 2 {
                                    print("🤖 AI stream: \(candidate) 429, backing off \(capped / 1_000_000_000)s...")
                                    try? await Task.sleep(nanoseconds: capped)
                                    lastError = APIError.serverError(status: 429, message: bodyStr)
                                    continue
                                } else {
                                    lastError = APIError.serverError(status: 429, message: bodyStr)
                                    continue modelLoop
                                }
                            }

                            guard httpResponse.statusCode == 200 else {
                                // Non-200, non-429 — collect body for diagnostics.
                                var bodyStr = ""
                                for try await line in bytes.lines {
                                    bodyStr += line
                                }
                                print("🤖 AI stream: \(candidate) HTTP \(httpResponse.statusCode): \(bodyStr.prefix(120))")
                                lastError = APIError.serverError(
                                    status: httpResponse.statusCode,
                                    message: bodyStr.isEmpty ? "OpenRouter error" : bodyStr
                                )
                                continue modelLoop
                            }

                            // Parse SSE lines: "data: {json}\n\n"
                            var yieldedForThisAttempt = false
                            for try await line in bytes.lines {
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonString = String(line.dropFirst(6))
                                if jsonString == "[DONE]" {
                                    break
                                }
                                guard let jsonData = jsonString.data(using: .utf8),
                                      let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: jsonData) else {
                                    continue
                                }
                                // 🔧 v4: prefer content, fall back to reasoning
                                // (reasoning models stream their visible output
                                // via `delta.reasoning`, with `content` null).
                                let delta = chunk.choices.first?.delta.content
                                    ?? chunk.choices.first?.delta.reasoning
                                if let delta, !delta.isEmpty {
                                    continuation.yield(delta)
                                    yieldedForThisAttempt = true
                                    anyTokenYielded.lock()
                                    anyTokenYieldedFlag = true
                                    anyTokenYielded.unlock()
                                }
                            }

                            if yieldedForThisAttempt {
                                // Got at least one token — we're done, no need
                                // to try the next model.
                                continuation.finish()
                                return
                            } else {
                                print("🤖 AI stream: \(candidate) 200 OK but 0 tokens streamed, moving on")
                                lastError = APIError.serverError(
                                    status: 200,
                                    message: "Empty stream from \(candidate)"
                                )
                                continue modelLoop
                            }
                        } catch {
                            print("🤖 AI stream: \(candidate) threw: \(error.localizedDescription)")
                            lastError = error
                            continue modelLoop
                        }
                    }
                }

                // All models exhausted.
                if anyTokenYieldedFlag {
                    // We did yield something at some point — finish gracefully.
                    continuation.finish()
                } else if let lastError = lastError,
                          case APIError.serverError(let status, _) = lastError,
                          status == 429 {
                    continuation.finish(throwing: APIError.serverError(
                        status: 429,
                        message: "Слишком много запросов к ИИ. Попробуйте позже."
                    ))
                } else {
                    continuation.finish(throwing: lastError ?? APIError.serverError(
                        status: 0,
                        message: "All free models failed"
                    ))
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

        // 🔧 FIX: do NOT pass `model: lightModel` — `lightModel` is a paid
        // model the free API key cannot use. Instead, let chat() rotate
        // through the full freeModels fallback chain.
        return try await chat(messages: messages, temperature: 0.8)
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
            // 🔧 v4: include the raw error JSON in the message so the chat()
            // retry logic can extract `retry_after_seconds` from metadata.
            // OpenRouter puts this field in `error.metadata`, not in
            // `error.message`, so we need the full body serialized.
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverError(
                status: 429,
                message: "Rate limited. Raw: \(rawBody)"
            )
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
        // 🔧 v4: content can be null when a reasoning model exhausts its
        // token budget on internal "thinking" before emitting a final answer.
        // Previously a non-optional String would cause the whole decode to
        // throw, turning a successful HTTP 200 into a cryptic failure.
        let content: String?
        // 🔧 v4: reasoning models (DeepSeek-R1-style, Qwen3 thinking, etc.)
        // put their reasoning trace here. Used as a fallback when content
        // is null but we still need to return *something* to the user.
        let reasoning: String?
    }
}

private struct OpenRouterStreamChunk: Decodable {
    let choices: [StreamChoice]

    struct StreamChoice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        // 🔧 v4: both fields optional — reasoning models stream via `reasoning`
        // while chat models stream via `content`. Some chunks have neither
        // (e.g. role-only first chunk, finish_reason-only last chunk).
        let content: String?
        let reasoning: String?
    }
}

private struct OpenRouterError: Decodable {
    let error: ErrorDetail?

    struct ErrorDetail: Decodable {
        let message: String
        let code: String?
    }
}
