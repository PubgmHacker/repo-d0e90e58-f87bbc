import SwiftUI

struct PlayerBottomControls: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let style: PlayerStage.Style

    @State private var preview: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Spacer()

            PlinkSeekBar(
                value: Binding(
                    get: { ui.isScrubbing ? preview : model.coordinator.position },
                    set: { preview = $0 }
                ),
                buffered: model.bufferedFraction,
                duration: max(model.coordinator.duration, 1),
                isScrubbing: $ui.isScrubbing,
                enabled: model.isHost && model.connectionState == .connected,
                onCommit: { value in
                    Task { await model.sendSeekCommand(to: value) }
                }
            )

            HStack(spacing: 10) {
                Text("\(format(model.coordinator.position)) / \(format(model.coordinator.duration))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlinkRave.cyan)

                Text(model.qualityLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PlinkRave.textSecondary)

                Spacer()

                if model.coordinator.capabilities.supportsPiP {
                    PlayerSmallButton(systemName: "pip", action: model.startPiP)
                }

                if style == .portrait {
                    PlayerSmallButton(systemName: "arrow.up.left.and.arrow.down.right", action: model.enterFullscreen)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, style == .landscape ? 10 : 8)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
