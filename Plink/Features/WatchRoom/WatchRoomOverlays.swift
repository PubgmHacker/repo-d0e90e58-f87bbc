// Plink/Features/WatchRoom/WatchRoomOverlays.swift — PATCH 02
//
// Extracted from WatchRoomSupportTypes.swift per PATCH 02 spec.
//
// Contains:
//   - RoomToastView          (toast notification)
//   - WatchChatSheet         (modal chat sheet for portrait)
//   - LandscapeChatDrawer    (slide-in chat for landscape)
//   - WatchChatHeader        (chat header with title + watcher count)
//   - ChatAvatar             (small avatar in chat bubble)
//   - ParticipantAvatar      (larger avatar in presence bar)
//   - DanmakuCanvasLayer     (flying comments overlay)
//   - VoiceActionButton      (mic toggle)
//   - CameraActionButton     (camera toggle)
//
// All chrome uses .ultraThinMaterial + subtle strokes for depth.

import SwiftUI

// MARK: - Toast

struct RoomToastView: View {
    let toast: RoomToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForKind)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colorForKind)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlinkRave.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(colorForKind.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 8)
    }

    private var colorForKind: Color {
        switch toast.kind {
        case .info: return PlinkRave.cyan
        case .success: return PlinkRave.success
        case .warning: return PlinkRave.warning
        case .error: return PlinkRave.danger
        }
    }

    private var iconForKind: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Chat containers

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
            WatchChatHeader(model: model, closable: true, onClose: {
                withAnimation(.plinkDrawer) {
                    isVisible = false
                }
            })
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(PlinkRave.divider.opacity(0.5))
                .frame(width: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 16, x: -4, y: 0)
    }
}

struct WatchChatHeader: View {
    let model: WatchRoomModel
    var closable: Bool = false
    var onClose: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text("Chat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PlinkRave.text)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .medium))
                Text("\(model.participants.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(PlinkRave.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PlinkRave.raised.opacity(0.6), in: Capsule())

            if closable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PlinkRave.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(PlinkRave.raised, in: Circle())
                }
                .accessibilityLabel("Close chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PlinkRave.surface.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlinkRave.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Avatars

struct ChatAvatar: View {
    let message: ChatMessageInfo

    var body: some View {
        Circle()
            .fill(avatarBackground)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(avatarForeground)
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var avatarBackground: Color {
        if message.isAdmin { return PlinkRave.gold.opacity(0.18) }
        if message.isPremium { return PlinkRave.hotPink.opacity(0.18) }
        return PlinkRave.raised
    }

    private var avatarForeground: Color {
        if message.isAdmin { return PlinkRave.gold }
        if message.isPremium { return PlinkRave.hotPink }
        return PlinkRave.text
    }
}

struct ParticipantAvatar: View {
    let participant: ParticipantInfo
    let hostId: String?
    var isSpeaking: Bool = false

    private var isHost: Bool { participant.userId == hostId }

    var body: some View {
        Circle()
            .fill(PlinkRave.raised)
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(participant.username.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlinkRave.text)
            )
            .overlay(
                Circle()
                    .stroke(ringColor, lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if isHost {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(PlinkRave.gold)
                        .background(PlinkRave.void, in: Circle())
                        .frame(width: 14, height: 14)
                        .offset(x: 1, y: 1)
                }
            }
    }

    private var ringColor: Color {
        if isSpeaking { return PlinkRave.success }
        if isHost { return PlinkRave.gold.opacity(0.6) }
        return PlinkRave.success.opacity(0.18)
    }
}

// MARK: - Danmaku

struct DanmakuCanvasLayer: View {
    let messages: [DanmakuMessage]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(messages) { msg in
                Text(msg.text)
                    .font(.system(size: msg.isPremium ? 17 : 14, weight: .medium))
                    .foregroundStyle(msg.isAdmin ? PlinkRave.gold : msg.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(PlinkRave.void.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.05), lineWidth: 0.5))
                    .offset(x: 0, y: CGFloat(msg.track) * 32)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, 8)
        .allowsHitTesting(true)
    }
}

// MARK: - Voice / Camera buttons

struct VoiceActionButton: View {
    let state: MicrophoneUIState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
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
        case .talking: return PlinkRave.success.opacity(0.16)
        default: return .clear
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
                .foregroundStyle(state == .on ? PlinkRave.success : PlinkRave.secondaryText)
                .frame(width: 38, height: 38)
                .background(.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Camera off" : "Camera on")
    }

    private var iconName: String {
        state == .on ? "video.fill" : "video.slash.fill"
    }
}
