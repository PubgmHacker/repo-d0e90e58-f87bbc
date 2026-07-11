import SwiftUI

// MARK: - Danmaku (flying comments)
struct DanmakuMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color
    let senderName: String
    let track: Int
    let createdAt: Date
    let isPremium: Bool
    let isAdmin: Bool
}

// MARK: - RTC UI States
enum MicrophoneUIState: Equatable {
    case off
    case on
    case talking
    case pushToTalk
}

enum CameraUIState: Equatable {
    case off
    case on
    case loading
}

// MARK: - Player UI helpers
struct PlayerLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(PlinkRave.primary)
                .scaleEffect(1.1)
        }
    }
}

struct BufferingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(0.9)
            .padding(14)
            .background(PlinkRave.surface.opacity(0.7), in: Circle())
    }
}

struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    private var color: Color {
        guard connected else { return PlinkRave.danger }
        if driftMs < 80 { return PlinkRave.success }
        if driftMs < 250 { return PlinkRave.secondary }
        if driftMs < 750 { return PlinkRave.warning }
        return PlinkRave.danger
    }

    private var label: String {
        guard connected else { return "Offline" }
        if driftMs < 80 { return "In sync" }
        if driftMs < 250 { return "Syncing" }
        if driftMs < 750 { return "Lagging" }
        return "Resync"
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PlinkRave.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PlinkRave.surface.opacity(0.8), in: Capsule())
    }
}

struct PlayerChromeButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlinkRave.textSecondary)
                .frame(width: 32, height: 32)
                .background(PlinkRave.surface.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct PlayerSmallButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PlinkRave.textSecondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice / Camera action buttons
struct VoiceActionButton: View {
    let state: MicrophoneUIState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(bgColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .off: return "mic.slash.fill"
        case .on: return "mic.fill"
        case .talking: return "mic.fill"
        case .pushToTalk: return "mic.fill"
        }
    }
    private var iconColor: Color {
        switch state {
        case .off: return PlinkRave.danger
        case .on: return PlinkRave.text
        case .talking: return PlinkRave.success
        case .pushToTalk: return PlinkRave.warning
        }
    }
    private var bgColor: Color {
        switch state {
        case .talking: return PlinkRave.success.opacity(0.12)
        default: return PlinkRave.raised
        }
    }
    private var accessibilityLabel: String {
        switch state {
        case .off: return "Unmute"
        case .on: return "Mute"
        case .talking: return "Talking"
        case .pushToTalk: return "Hold to talk"
        }
    }
}

struct CameraActionButton: View {
    let state: CameraUIState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state == .on ? PlinkRave.success : PlinkRave.textSecondary)
                .frame(width: 34, height: 34)
                .background(PlinkRave.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Camera off" : "Camera on")
    }

    private var iconName: String {
        state == .on ? "video.fill" : "video.slash.fill"
    }
}

// MARK: - Danmaku Canvas
struct DanmakuCanvasLayer: View {
    let messages: [DanmakuMessage]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(messages) { msg in
                Text(msg.text)
                    .font(.system(size: msg.isPremium ? 18 : 15, weight: .medium))
                    .foregroundStyle(msg.isAdmin ? PlinkRave.gold : msg.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PlinkRave.void.opacity(0.5), in: Capsule())
                    .offset(x: 0, y: CGFloat(msg.track) * 30)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, 8)
        .allowsHitTesting(true)
    }
}

// MARK: - Chat supporting views
struct WatchChatSheet: View {
    let model: WatchRoomModel

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model)
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .background(PlinkRave.void)
    }
}

struct LandscapeChatDrawer: View {
    let model: WatchRoomModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model)
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .background(PlinkRave.void.opacity(0.92))
    }
}

struct WatchChatHeader: View {
    let model: WatchRoomModel

    var body: some View {
        HStack {
            Text("Chat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PlinkRave.text)
            Spacer()
            Text("\(model.participants.count) watching")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PlinkRave.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PlinkRave.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PlinkRave.divider.opacity(0.3)).frame(height: 0.5)
        }
    }
}

struct RoomIdentityBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack {
            Text((model.roomId ?? "Plink Room"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PlinkRave.text)
            Spacer()
            if model.isHost {
                Text("HOST")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(PlinkRave.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PlinkRave.gold.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct RoomToastView: View {
    let toast: RoomToast

    var body: some View {
        Text(toast.text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PlinkRave.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(toastColor.opacity(0.85), in: Capsule())
            .padding(.top, 8)
    }

    private var toastColor: Color {
        switch toast.kind {
        case .info: return PlinkRave.raised
        case .success: return PlinkRave.success.opacity(0.25)
        case .warning: return PlinkRave.warning.opacity(0.25)
        case .error: return PlinkRave.danger.opacity(0.25)
        }
    }
}

// MARK: - Chat Avatar
struct ChatAvatar: View {
    let message: ChatMessageInfo

    var body: some View {
        Circle()
            .fill(message.isPremium ? PlinkRave.accent.opacity(0.2) : PlinkRave.primary.opacity(0.15))
            .frame(width: 26, height: 26)
            .overlay(
                Text(String(message.senderName.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.isPremium ? PlinkRave.accent : PlinkRave.primary)
            )
    }
}

// MARK: - Participant Avatar
struct ParticipantAvatar: View {
    let participant: ParticipantInfo
    let hostId: String?

    var body: some View {
        Circle()
            .fill(PlinkRave.raised)
            .frame(width: 34, height: 34)
            .overlay(
                Text(String(participant.username.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlinkRave.text)
            )
            .overlay(
                Circle()
                    .stroke(participant.userId == hostId ? PlinkRave.gold.opacity(0.5) : PlinkRave.success.opacity(0.25), lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if participant.userId == hostId {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(PlinkRave.gold)
                        .background(PlinkRave.void, in: Circle())
                        .frame(width: 12, height: 12)
                        .offset(x: 1, y: 1)
                }
            }
    }
}
