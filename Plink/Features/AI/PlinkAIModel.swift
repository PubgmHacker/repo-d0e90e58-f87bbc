// Plink/Features/AI/PlinkAIModel.swift — GPT-5.6 §9
import Foundation

enum PlinkAIVisualState: String, Sendable {
    case idle, listening, thinking, speaking, moderating, offline, failed
}

struct PlinkAIMessage: Identifiable, Codable, Sendable {
    enum Role: String, Codable { case user, assistant, system }
    let id: UUID; let role: Role; let text: String; let createdAt: Date; let actions: [AIAction]
    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date(), actions: [AIAction] = []) {
        self.id = id; self.role = role; self.text = text; self.createdAt = createdAt; self.actions = actions
    }
}

enum AIAction: Codable, Sendable {
    case previewQueue([String])
    case confirmCreateRoom(draftID: String)
    case confirmInvite(userIDs: [String])
    case retry
}
