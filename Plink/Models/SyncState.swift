import Foundation

// MARK: - Sync State
struct SyncState: Codable, Sendable {
    let isPlaying: Bool
    let currentTime: TimeInterval     // Media time in seconds
    let timestamp: TimeInterval        // Server/network time when state was captured
    let mediaItemID: String?

    /// Estimated drift in milliseconds between this state and local playback
    var driftMs: TimeInterval {
        let elapsed = Date().timeIntervalSince1970 - timestamp
        return elapsed * 1000
    }

    static var idle: SyncState {
        SyncState(
            isPlaying: false,
            currentTime: 0,
            timestamp: Date().timeIntervalSince1970,
            mediaItemID: nil
        )
    }

    static var playing: SyncState {
        SyncState(
            isPlaying: true,
            currentTime: 0,
            timestamp: Date().timeIntervalSince1970,
            mediaItemID: nil
        )
    }
}

// MARK: - Playback Command (sent over WebSocket)
enum SyncCommand: String, Codable, Sendable {
    case play
    case pause
    case seek
    case changeMedia
    case stateRequest   // Client asks host for current state
    case stateResponse  // Host responds with current state
    case correction     // Host tells client to seek to exact position
    case ping
    case pong
}

// MARK: - Sync Message (WebSocket payload)
struct SyncMessage: Codable, Sendable {
    let command: SyncCommand
    let roomID: String
    let senderID: String
    let mediaTime: TimeInterval?     // For play/pause/seek
    let mediaItem: MediaItem?        // For changeMedia
    /// Server wall-clock time when the event was issued. Set by the host/sender
    /// using the synchronized server clock so receivers can compensate for
    /// network latency. `var` so the SyncEngine can inject the server time.
    var timestamp: TimeInterval

    init(command: SyncCommand, roomID: String, senderID: String,
         mediaTime: TimeInterval? = nil, mediaItem: MediaItem? = nil,
         timestamp: TimeInterval = 0) {
        self.command = command
        self.roomID = roomID
        self.senderID = senderID
        self.mediaTime = mediaTime
        self.mediaItem = mediaItem
        // 0 = "unset"; the SyncEngine will fill in synchronized server time on send.
        self.timestamp = timestamp
    }
}

// MARK: - Sync Quality Indicator
enum SyncQuality: String, Sendable {
    case perfect = "perfect"       // < 100ms drift
    case good = "good"             // 100-300ms
    case syncing = "syncing"      // 300-1000ms (show indicator)
    case poor = "poor"             // > 1000ms (show warning)

    var icon: String {
        switch self {
        case .perfect: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .poor: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .perfect: return "green"
        case .good: return "yellow"
        case .syncing: return "orange"
        case .poor: return "red"
        }
    }

    static func fromDrift(_ driftMs: TimeInterval) -> SyncQuality {
        switch driftMs {
        case ..<100: return .perfect
        case 100..<300: return .good
        case 300..<1000: return .syncing
        default: return .poor
        }
    }
}
