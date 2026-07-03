import Foundation

// MARK: - WebRTC Configuration
struct WebRTCConfig: Sendable {
    let iceServers: [ICEServer]
    let audioConstraints: AudioConstraints

    static var defaultConfig: WebRTCConfig {
        WebRTCConfig(
            iceServers: [
                ICEServer(
                    urls: ["stun:stun.l.google.com:19302"],
                    username: nil,
                    credential: nil
                ),
                ICEServer(
                    urls: ["stun:stun1.l.google.com:19302"],
                    username: nil,
                    credential: nil
                ),
                // Open Relay (бесплатный TURN для NAT traversal)
                ICEServer(
                    urls: ["turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"],
                    username: "openrelayproject",
                    credential: "openrelayproject"
                ),
            ],
            audioConstraints: .default
        )
    }
}

struct ICEServer: Codable, Sendable {
    let urls: [String]
    let username: String?
    let credential: String?
}

struct AudioConstraints: Sendable {
    let echoCancellation: Bool
    let noiseSuppression: Bool
    let autoGainControl: Bool
    let highPassFilter: Bool

    static var `default`: AudioConstraints {
        AudioConstraints(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            highPassFilter: true
        )
    }
}
