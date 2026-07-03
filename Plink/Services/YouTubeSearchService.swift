import Foundation

// MARK: - YouTube Search Service
/// Поиск роликов на YouTube через backend (GET /api/media/search?q=...).
/// Возвращает лёгкие метаданные без извлечения потока — поток извлекается
/// когда пользователь выбирает конкретный ролик.
@MainActor
final class YouTubeSearchService {

    private let apiBaseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(apiBaseURL: String = "https://raveclone.app/api") {
        self.apiBaseURL = URL(string: apiBaseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Auth

    private var authToken: String?

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Search

    /// Поиск роликов. Возвращает массив результатов (без потока).
    func search(query: String) async throws -> [YouTubeSearchResult] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("media/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "12")
        ]

        guard let url = components.url else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let payload = try decoder.decode(SearchResponse.self, from: data)
            return payload.results
        case 429:
            throw SearchError.rateLimited
        default:
            let errBody = try? decoder.decode(ErrorBody.self, from: data)
            throw SearchError.serverError(http.statusCode, errBody?.error)
        }
    }
}

// MARK: - Models

struct YouTubeSearchResult: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String?
    let thumbnailURL: String?
    let duration: Double?
    let url: String

    /// Форматированная длительность "M:SS" / "H:MM:SS".
    var formattedDuration: String? {
        guard let d = duration, d > 0 else { return nil }
        let total = Int(d)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct SearchResponse: Codable {
    let results: [YouTubeSearchResult]
}

private struct ErrorBody: Codable {
    let error: String
}

// MARK: - Errors

enum SearchError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case rateLimited
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Empty search query."
        case .invalidResponse:
            return "Invalid server response."
        case .rateLimited:
            return "Too many requests. Try again later."
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg ?? "unknown")"
        }
    }
}
