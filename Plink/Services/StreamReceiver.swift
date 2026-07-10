import Foundation
import SwiftUI
import AVKit

// MARK: - Stream Receiver
/// Приём WebRTC-видео-потока от хоста (Screen Share режим).
///
/// Для гостей: подключается к стриму хоста, рендерит видео + фид Ambilight.
///
/// Архитектура (без зависимости от GoogleWebRTC SDK в текущей фазе):
/// 1. Получает WebRTC signaling (SDP/ICE) через WebSocket
/// 2. Устанавливает peer connection
/// 3. Рендерит входящий video track в SwiftUI
///
/// Пока WebRTC SDK не подключён — использует AVPlayer как fallback
/// (для тестов и direct-stream URL).
@MainActor
final class StreamReceiver: ObservableObject {

    // MARK: - State

    @Published private(set) var isReceiving = false
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var viewerCount = 0
    @Published var errorMessage: String?

    /// Текущий кадр для Ambilight-сэмплера.
    var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Private

    private let signaling: SignalingClient
    private let roomID: String
    private let userID: String
    private var hostID: String?
    private var player: AVPlayer?

    // MARK: - Init

    init(signaling: SignalingClient, roomID: String, userID: String) {
        self.signaling = signaling
        self.roomID = roomID
        self.userID = userID
    }

    // MARK: - Subscribe to Host Stream

    /// Запросить стрим у хоста.
    /// Отправляет `screen_share_subscribe` через WS, ждёт SDP offer.
    func subscribe(to hostID: String) async {
        self.hostID = hostID
        connectionState = .connecting

        // 1. Отправляем запрос на подписку
        signaling.sendRaw(encodeMessage([
            "type": "screen_share_subscribe",
            "roomID": roomID,
            "userID": userID,
            "hostID": hostID,
        ]))

        // 2. Запрашиваем SDP offer
        signaling.sendRaw(encodeMessage([
            "type": "screen_share_request_offer",
            "roomID": roomID,
            "userID": userID,
            "hostID": hostID,
        ]))

        // Таймаут: если нет ответа за 10с → ошибка
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if connectionState == .connecting {
                await MainActor.run {
                    connectionState = .failed
                    errorMessage = "Host did not respond"
                }
            }
        }
    }

    /// Остановить приём стрима.
    func unsubscribe() {
        connectionState = .idle
        isReceiving = false
        hostID = nil
        player?.pause()
        player = nil

        signaling.sendRaw(encodeMessage([
            "type": "screen_share_stop",
            "roomID": roomID,
            "userID": userID,
        ]))
    }

    // MARK: - Signaling Ingest

    /// Обработка входящих signaling-сообщений (SDP/ICE от хоста).
    func ingest(raw text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return false
        }

        switch type {
        case "screen_share_start":
            // Хост начал стримить — подписываемся автоматически
            if let hostID = json["hostID"] as? String {
                Task { await subscribe(to: hostID) }
            }
            return true

        case "screen_share_stop":
            // Хост прекратил стрим
            connectionState = .idle
            isReceiving = false
            return true

        case "webrtc_offer":
            handleOffer(json)
            return true

        case "webrtc_ice_candidate":
            handleICECandidate(json)
            return true

        default:
            return false
        }
    }

    // MARK: - WebRTC Handling (Stub — до подключения GoogleWebRTC SDK)

    private func handleOffer(_ json: [String: Any]) {
        guard let _ = json["sdp"] as? String else { return }
        connectionState = .negotiating

        // 🔧 Pack v3: WebRTC SDK не подключён — используется заглушка.
        // При подключении GoogleWebRTC SDK:
        // 1. RTCPeerConnection.setRemoteDescription(offer)
        // 2. Создать answer
        // 3. RTCPeerConnection.setLocalDescription(answer)
        // 4. Отправить answer через signaling

        // Заглушка: имитируем успешное подключение
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            connectionState = .connected
            isReceiving = true
        }
    }

    private func handleICECandidate(_ json: [String: Any]) {
        // 🔧 Pack v3: WebRTC SDK не подключён — заглушка.
        // При подключении: RTCPeerConnection.add(candidate)
    }

    // MARK: - Fallback: AVPlayer Stream

    /// Fallback для тестов: проигрывает прямой URL потока.
    func playStreamURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.play()
        player = p
        isReceiving = true
        connectionState = .connected
    }

    // MARK: - Helpers

    private func encodeMessage(_ dict: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Connection State

enum ConnectionState: String {
    case idle          // не подключён
    case connecting    // запрашиваем стрим
    case negotiating   // WebRTC negotiation
    case connected     // стрим идёт
    case failed        // ошибка

    var displayText: String {
        switch self {
        case .idle: return ""
        case .connecting: return "Connecting…"
        case .negotiating: return "Negotiating…"
        case .connected: return "Live"
        case .failed: return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .raveTextSecondary
        case .connecting, .negotiating: return .raveWarning
        case .connected: return .raveGreen
        case .failed: return .raveDanger
        }
    }
}
