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
        VStack(spacing: 12) {
            ProgressView()
                .tint(PlinkRave.magenta)
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(PlinkRave.textSecondary)
        }
    }
}

struct BufferingOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(PlinkRave.cyan)
            Text("Buffering")
                .font(.caption2)
                .foregroundStyle(PlinkRave.textSecondary)
        }
        .padding(16)
        .background(PlinkRave.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    private var color: Color {
        guard connected else { return PlinkRave.danger }
        if driftMs < 80 { return PlinkRave.success }
        if driftMs < 250 { return PlinkRave.cyan }
        if driftMs < 750 { return PlinkRave.warning }
        return PlinkRave.danger
    }

    private var label: String {
        guard connected else { return "Offline" }
        if driftMs < 80 { return "Synced" }
        if driftMs < 250 { return "Syncing" }
        if driftMs < 750 { return "Lagging" }
        return "Resync"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PlinkRave.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PlinkRave.surface.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct PlayerChromeButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PlinkRave.text)
                .frame(width: 36, height: 36)
                .background(PlinkRave.surface.opacity(0.72), in: Circle())
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PlinkRave.textSecondary)
                .frame(width: 32, height: 32)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
                .background(bgColor, in: Circle())
                .overlay(Circle().stroke(borderColor.opacity(0.4), lineWidth: 1))
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
        case .talking: return PlinkRave.success.opacity(0.15)
        default: return PlinkRave.raised
        }
    }
    private var borderColor: Color {
        switch state {
        case .talking: return PlinkRave.success
        default: return PlinkRave.divider
        }
    }
    private var accessibilityLabel: String {
        switch state {
        case .off: return "Unmute microphone"
        case .on: return "Mute microphone"
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == .on ? PlinkRave.success : PlinkRave.textSecondary)
                .frame(width: 38, height: 38)
                .background(PlinkRave.raised, in: Circle())
                .overlay(Circle().stroke(PlinkRave.divider.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Turn camera off" : "Turn camera on")
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
                    .font(.system(size: msg.isPremium ? 20 : 16, weight: .bold))
                    .foregroundStyle(msg.isAdmin ? Color(hex: 0xFFD700) : msg.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PlinkRave.void.opacity(0.4), in: Capsule())
                    .offset(x: 0, y: CGFloat(msg.track) * 32)
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
        .overlay(alignment: .leading) {
            Capsule()
                .fill(PlinkRave.divider.opacity(0.5))
                .frame(width: 3, height: 40)
                .gesture(
                    DragGesture().onChanged { _ in }
                )
        }
    }
}

struct WatchChatHeader: View {
    let model: WatchRoomModel

    var body: some View {
        HStack {
            Text("Chat")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PlinkRave.text)
            Spacer()
            Text("\(model.participants.count) watching")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PlinkRave.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PlinkRave.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PlinkRave.divider.opacity(0.4)).frame(height: 1)
        }
    }
}

struct RoomIdentityBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack {
            Text(model.roomId.isEmpty ? "Plink Room" : "Room")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PlinkRave.text)
            Spacer()
            if model.isHost {
                Text("HOST")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xFFD700))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xFFD700).opacity(0.15), in: Capsule())
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PlinkRave.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(toastColor.opacity(0.9), in: Capsule())
            .padding(.top, 8)
    }

    private var toastColor: Color {
        switch toast.kind {
        case .info: return PlinkRave.raised
        case .success: return PlinkRave.success.opacity(0.3)
        case .warning: return PlinkRave.warning.opacity(0.3)
        case .error: return PlinkRave.danger.opacity(0.3)
        }
    }
}

// MARK: - Chat Avatar
struct ChatAvatar: View {
    let message: ChatMessageInfo

    var body: some View {
        Circle()
            .fill(message.isPremium ? PlinkRave.hotPink.opacity(0.3) : PlinkRave.cyan.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(message.isPremium ? PlinkRave.hotPink : PlinkRave.cyan)
            )
            .overlay(
                Circle()
                    .stroke(message.isPremium ? PlinkRave.hotPink.opacity(0.5) : PlinkRave.cyan.opacity(0.3), lineWidth: 1)
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
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(participant.username.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PlinkRave.text)
            )
            .overlay(
                Circle()
                    .stroke(participant.userId == hostId ? Color(hex: 0xFFD700) : PlinkRave.success.opacity(0.4), lineWidth: 2)
            )
            .overlay(alignment: .bottomTrailing) {
                if participant.userId == hostId {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(hex: 0xFFD700))
                        .background(PlinkRave.void, in: Circle())
                        .frame(width: 14, height: 14)
                        .offset(x: 2, y: 2)
                }
            }
    }
}
