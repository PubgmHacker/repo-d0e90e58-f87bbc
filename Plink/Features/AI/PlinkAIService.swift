// Plink/Features/AI/PlinkAIService.swift — simple service for V4 adapter
import Foundation

struct PlinkAIService: Sendable {
    static let shared = PlinkAIService()

    struct AIResponse: Decodable { let message: String; let actions: [String] }

    func send(message: String, roomId: String? = nil) async throws -> AIResponse {
        // Placeholder — real backend call when /api/ai/chat is ready
        return AIResponse(message: "Я помогу найти видео и создать комнату.", actions: [])
    }

    func confirm(token: String) async throws {
        // Placeholder
    }
}
