import Foundation
import Observation

@MainActor
@Observable
public final class ProductionV4Adapter: V4AppAdapter {
    // Inject existing services here. Do not duplicate network clients.
    private let roomService: RoomService
    private let mediaService: MediaService
    private let friendManager: FriendManager
    private let authService: AuthService
    private let aiService: PlinkAIService

    public private(set) var currentUser: V4User
    public private(set) var liveRooms: [V4Room] = []
    public private(set) var trending: [V4MediaCard] = []
    public private(set) var friends: [V4User] = []
    public private(set) var services: [V4VideoService] = []
    public private(set) var serviceCategories: [V4ServiceCategory] = []

    public init(roomService: RoomService, mediaService: MediaService, friendManager: FriendManager, authService: AuthService, aiService: PlinkAIService) {
        self.roomService=roomService;self.mediaService=mediaService;self.friendManager=friendManager;self.authService=authService;self.aiService=aiService
        self.currentUser=V4User(id:"loading",displayName:"…",avatarURL:nil,subtitle:"",isOnline:true)
        // GLM: map the EXISTING service catalog and current-user model here.
    }

    public func refreshHome() async { /* map existing room/media results to V4 DTOs */ }
    public func openRoom(id: String) { /* route through existing PlinkAppShell callback */ }
    public func openDM(userID: String) { /* existing DM route */ }
    public func invite(userID: String) { /* existing invite */ }
    public func searchYouTube(query:String,pageToken:String?) async throws -> ([V4MediaCard],String?) { fatalError("Map existing MediaService search result") }
    public func browse(serviceID:String) async throws -> [V4MediaCard] { fatalError("Map existing provider browser") }
    public func validateDirectLink(_ value:String) async throws -> (token:String,title:String) { fatalError("Map existing validated-link endpoint") }
    public func createRoom(draft:V4RoomDraft) async throws -> String { fatalError("Map existing RoomService create") }
    public func sendAI(_ text:String) async throws -> String { try await aiService.send(text) }
    public func confirmAITool(token:String) async throws { try await aiService.confirm(token) }
    public func signOut() async { await authService.signOut() }
    public func deleteAccount() async throws { try await authService.deleteAccount() }
}
