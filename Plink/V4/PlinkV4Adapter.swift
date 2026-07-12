// Plink/V4/PlinkV4Adapter.swift — GPT-5.6 V4 (fixed)
import Foundation
import Observation

@MainActor
@Observable
final class ProductionV4Adapter: V4AppAdapter {
    private let roomService: RoomService
    private let mediaService: MediaService
    private let friendManager: FriendManager
    private let authService: AuthService
    private let aiService: PlinkAIService

    private(set) var currentUser: V4User
    private(set) var liveRooms: [V4Room] = []
    private(set) var trending: [V4MediaCard] = []
    private(set) var friends: [V4User] = []
    private(set) var services: [V4VideoService] = []
    private(set) var serviceCategories: [V4ServiceCategory] = []

    init(roomService: RoomService, mediaService: MediaService, friendManager: FriendManager, authService: AuthService, aiService: PlinkAIService) {
        self.roomService = roomService; self.mediaService = mediaService
        self.friendManager = friendManager; self.authService = authService; self.aiService = aiService
        self.currentUser = V4User(id: "loading", displayName: "…", avatarURL: nil, subtitle: "", isOnline: true)
    }

    func refreshHome() async { }
    func openRoom(id: String) { }
    func openDM(userID: String) { }
    func invite(userID: String) { }

    func searchYouTube(query: String, pageToken: String?) async throws -> ([V4MediaCard], String?) {
        return ([], nil)
    }

    func browse(serviceID: String) async throws -> [V4MediaCard] {
        return []
    }

    func validateDirectLink(_ value: String) async throws -> (token: String, title: String) {
        return (token: value, title: "Direct Link")
    }

    func createRoom(draft: V4RoomDraft) async throws -> String {
        return UUID().uuidString
    }

    func sendAI(_ text: String) async throws -> String {
        let response = try await aiService.send(message: text)
        return response.message
    }

    func confirmAITool(token: String) async throws {
        // Not yet implemented — placeholder
    }

    func signOut() async {
        try? await authService.signOut()
    }

    func deleteAccount() async throws {
        try await authService.deleteAccount()
    }
}
