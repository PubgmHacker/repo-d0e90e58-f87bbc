import Foundation

// MARK: - SignalingMessage (Stub)
/// Заглушка без WebRTC. При подключении GoogleWebRTC заменить на полную версию.
struct SignalingMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case offer
        case answer
        case iceCandidate
        case joinRoom
        case leaveRoom
    }

    public let kind: Kind
    public let sdp: String?
    public let candidateData: [String: AnyCodable]?
    public let senderId: String
    public let roomId: String
    public let targetId: String?

    public init(kind: Kind,
                sdp: String? = nil,
                candidateData: [String: AnyCodable]? = nil,
                senderId: String,
                roomId: String,
                targetId: String? = nil) {
        self.kind = kind
        self.sdp = sdp
        self.candidateData = candidateData
        self.senderId = senderId
        self.roomId = roomId
        self.targetId = targetId
    }

    public static func joinRoom(senderId: String, roomId: String) -> SignalingMessage {
        SignalingMessage(kind: .joinRoom, senderId: senderId, roomId: roomId)
    }

    public static func leaveRoom(senderId: String, roomId: String) -> SignalingMessage {
        SignalingMessage(kind: .leaveRoom, senderId: senderId, roomId: roomId)
    }

    public static func decode(from raw: String) -> SignalingMessage? {
        guard raw.contains("\"kind\"") else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SignalingMessage.self, from: data)
    }
}

// MARK: - AnyCodable helper
struct AnyCodable: Codable, Sendable, Equatable {
    let value: String?
    init(value: String? = nil) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - RTCICECandidateDTO (Stub)
struct RTCICECandidateDTO: Codable, Sendable, Equatable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32

    init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}
