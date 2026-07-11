import SwiftUI

struct PlayerStage: View {
    enum Style { case portrait, landscape, tablet }

    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let style: Style

    var body: some View {
        ZStack {
            Color.black
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
        .clipShape(RoundedRectangle(cornerRadius: style == .landscape ? 0 : 10, style: .continuous))
        .overlay {
            if style != .landscape {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PlinkRave.primary.opacity(0.15), lineWidth: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ui.controlsVisible)
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
            .padding(.horizontal, 10)
            .padding(.top, style == .landscape ? 8 : 6)
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: model.coordinator.isPlaying ? 0 : 1.5)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!model.isHost || model.connectionState != .connected)
        .opacity(model.isHost ? 1 : 0)
        .accessibilityLabel(model.coordinator.isPlaying ? "Pause" : "Play")
    }
}
