// Plink/Features/AI/PlinkAIService.swift — GPT-5.6 §12
import Foundation

actor PlinkAIService {
    static let shared = PlinkAIService()
    private let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app"

    struct AIResponse: Decodable { let message: String; let actions: [String] }

    func send(message: String, roomId: String? = nil) async throws -> AIResponse {
        guard let url = URL(string: "\(apiBaseURL)/api/ai/chat") else { throw AIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(for: "rave_auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = ["message": message, "context": ["roomId": roomId ?? ""]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.serverError }
        return try JSONDecoder().decode(AIResponse.self, from: data)
    }

    enum AIError: Error { case invalidURL, serverError }
}
