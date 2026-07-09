import AVFoundation
import Foundation

// MARK: - VoiceChatService (Stub)
/// Заглушка без WebRTC. Голосовой чат будет работать после подключения GoogleWebRTC SDK.
@MainActor
final class VoiceChatService: ObservableObject, VoiceChatServiceProtocol {

    @Published private(set) var isMuted = false
    @Published private(set) var isActive = false
    @Published private(set) var activePeers: Set<String> = []

    var onParticipantMutedChanged: ((String, Bool) -> Void)?

    private let localPeerId: String
    private var currentRoomId: String?

    init(signaling: SignalingClient, localPeerId: String) {
        self.localPeerId = localPeerId
    }

    func startCall(roomId: String) async throws {
        guard !isActive else { return }
        currentRoomId = roomId
        isActive = true
    }

    func endCall() async {
        guard isActive else { return }
        currentRoomId = nil
        isActive = false
        isMuted = false
        activePeers.removeAll()
    }

    func toggleMute() {
        guard isActive else { return }
        isMuted.toggle()
    }

    func ingest(message: SignalingMessage) async throws {
        // Stub: no-op without WebRTC
    }

    @discardableResult
    func ingest(raw text: String) -> Bool {
        guard let message = SignalingMessage.decode(from: text) else { return false }
        Task { try? await ingest(message: message) }
        return true
    }
}
