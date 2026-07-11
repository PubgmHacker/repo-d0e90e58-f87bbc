import SwiftUI

struct PlayerStage: View {
    enum Style { case portrait, landscape, tablet }

    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let style: Style

    var body: some View {
        ZStack {
            PlinkRave.void
            PlayerSurfaceView(coordinator: model.coordinator)

            if model.coordinator.isPreparing {
                PlayerLoadingView()
                    .transition(.opacity)
            }

            if model.coordinator.isBuffering {
                BufferingOverlay()
                    .transition(.opacity)
            }

            if ui.controlsVisible {
                PlayerTopChrome(model: model, style: style)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                PlayerCenterControl(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                PlayerBottomControls(model: model, ui: $ui, style: style)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            DanmakuCanvasLayer(messages: model.danmakuMessages)
        }
        .clipShape(RoundedRectangle(cornerRadius: style == .landscape ? 0 : 12, style: .continuous))
        .overlay {
            if style != .landscape {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PlinkRave.magenta.opacity(0.34), lineWidth: 1)
            }
        }
        .shadow(
            color: style == .landscape ? .clear : PlinkRave.magenta.opacity(0.20),
            radius: 8
        )
        .animation(.easeInOut(duration: 0.22), value: ui.controlsVisible)
    }
}

struct PlayerTopChrome: View {
    let model: WatchRoomModel
    let style: PlayerStage.Style

    var body: some View {
        VStack {
            HStack {
                PlayerChromeButton(systemName: "xmark", action: model.leaveRoom)
                Spacer()
                SyncHealthPill(driftMs: model.lastDriftMs, connected: model.connectionState == .connected)
                PlayerChromeButton(systemName: "ellipsis", action: model.openPlayerSettings)
            }
            .padding(.horizontal, 12)
            .padding(.top, style == .landscape ? 10 : 8)
            Spacer()
        }
    }
}

struct PlayerCenterControl: View {
    let model: WatchRoomModel

    var body: some View {
        Button {
            Task {
                if model.coordinator.isPlaying {
                    model.sendPauseCommand()
                } else {
                    await model.sendPlayCommand()
                }
            }
        } label: {
            Image(systemName: model.coordinator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(PlinkRave.text)
                .offset(x: model.coordinator.isPlaying ? 0 : 1.5)
                .frame(width: 58, height: 58)
                .background(PlinkRave.surface.opacity(0.92), in: Circle())
                .overlay(Circle().stroke(PlinkRave.magenta.opacity(0.55), lineWidth: 1))
                .plinkGlow(PlinkRave.magenta, radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!model.isHost || model.connectionState != .connected)
        .opacity(model.isHost ? 1 : 0)
        .accessibilityLabel(model.coordinator.isPlaying ? "Pause" : "Play")
    }
}
