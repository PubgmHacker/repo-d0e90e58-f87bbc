// Plink/Protocols/ServiceProtocol.swift — minimal protocols (legacy WebSocket removed)
// Only AuthServiceProtocol and RoomServiceProtocol remain.

import Foundation

protocol AuthServiceProtocol: AnyObject {
    var currentUser: User? { get }
    var authToken: String? { get }
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String, username: String) async throws -> User
    func signOut() async
    func restoreSession() async
}

protocol RoomServiceProtocol: AnyObject {
    func loadRooms() async throws -> [Room]
    func loadMyRooms() async throws -> [Room]
    func createRoom(name: String, mediaItem: MediaItem?, password: String?) async throws -> Room
    func joinRoom(code: String, password: String?) async throws -> Room
    func leaveRoom(roomId: String) async throws
    func deleteRoom(roomId: String) async throws
}
