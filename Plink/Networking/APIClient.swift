import Foundation

// MARK: - REST API Client
/// Generic REST client for room CRUD, user management, etc.
final class APIClient: Sendable {
    private let baseURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Auth token — set after login
    var authToken: String?

    init(baseURL: String = "https://xpkcakpkfewp-ofewk-pkv-production.up.railway.app/api") {
        self.baseURL = URL(string: baseURL)!
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        query: [String: String]? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let query {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try decoder.decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 409:
            // Парсим реальное сообщение сервера ("email already taken" и т.п.)
            let serverMsg = Self.parseErrorMessage(data: data)
            throw APIError.conflict(message: serverMsg ?? "Конфликт данных")
        default:
            let errorBody = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw APIError.serverError(
                status: httpResponse.statusCode,
                message: errorBody?.message ?? Self.parseErrorMessage(data: data) ?? "Unknown error"
            )
        }
    }

    /// Извлекает человекочитаемое сообщение из тела ошибки.
    /// Сервер шлёт {"error": "..."} или {"message": "..."}.
    static func parseErrorMessage(data: Data) -> String? {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return body.error ?? body.message
        }
        return nil
    }

    func requestNoBody(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        query: [String: String]? = nil
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let query {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(status: httpResponse.statusCode, message: "Request failed")
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case conflict(message: String)
    case serverError(status: Int, message: String)
    case decodingError
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Сессия истекла. Войдите заново."
        case .notFound: return "Ресурс не найден"
        case .conflict(let msg): return msg
        case .serverError(let status, let msg): return "Ошибка сервера (\(status)): \(msg)"
        case .decodingError: return "Не удалось обработать ответ сервера"
        case .networkError(let msg): return "Ошибка сети: \(msg)"
        }
    }
}

struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}
