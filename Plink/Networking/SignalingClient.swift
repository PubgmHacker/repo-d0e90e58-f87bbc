import Foundation

// MARK: - SignalingClient (Stub)
/// Заглушка без WebRTC. При подключении SDK заменить на полную версию.
//
/// 🔧 SWIFT 6: marked @MainActor because it holds a reference to WebSocketClient
/// (which is @MainActor via the WebSocketClientProtocol). Without this, accessing
/// ws.send() crosses isolation. All call sites already run on MainActor.
@MainActor
final class SignalingClient {

    private weak var ws: WebSocketClient?
    var onMessage: ((SignalingMessage) -> Void)?

    private let encoder = JSONEncoder()

    init(ws: WebSocketClient) {
        self.ws = ws
    }

    func decode(_ raw: String) -> SignalingMessage? {
        SignalingMessage.decode(from: raw)
    }

    @discardableResult
    func handleInbound(_ raw: String) -> Bool {
        guard let message = decode(raw) else { return false }
        onMessage?(message)
        return true
    }

    func send(_ message: SignalingMessage) {
        guard let ws else { return }
        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }
        // 🔧 SWIFT 6: now that SignalingClient is @MainActor, no need for Task hop.
        ws.send(json)
    }

    /// Отправка raw JSON (для Screen Share команд вне SignalingMessage enum).
    func sendRaw(_ jsonString: String) {
        guard let ws else { return }
        // 🔧 SWIFT 6: now that SignalingClient is @MainActor, no need for Task hop.
        ws.send(jsonString)
    }

    func sendJoinRoom(senderId: String, roomId: String) {
        send(.joinRoom(senderId: senderId, roomId: roomId))
    }

    func sendLeaveRoom(senderId: String, roomId: String) {
        send(.leaveRoom(senderId: senderId, roomId: roomId))
    }
}
