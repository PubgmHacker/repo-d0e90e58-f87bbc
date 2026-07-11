// Plink/Features/WatchRoom/PlayerBottomControls.swift — PATCH 02 polish
//
// Professional sizing:
//   - Seek bar height: 28pt touch zone (was 24pt)
//   - Time labels: 13pt monospaced (was 12pt)
//   - Quality badge as pill (was floating text)
//   - PiP/fullscreen buttons use PlayerSmallButton (32pt, was 30pt)
//   - Proper spacing: 16pt horizontal (was 14pt)

import SwiftUI

struct PlayerBottomControls: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant

    @State private var preview: Double = 0

    var body: some View {
        VStack(spacing: 8) {
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
            .frame(height: 28)

            HStack(spacing: 12) {
                Text("\(format(model.coordinator.position)) / \(format(model.coordinator.duration))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlinkRave.text)

                QualityBadge(label: model.qualityLabel)

                Spacer()

                if model.coordinator.capabilities.supportsPiP {
                    PlayerSmallButton(systemName: "pip") {
                        model.startPiP()
                    }
                    .accessibilityLabel("Picture in Picture")
                }

                if variant == .portrait {
                    PlayerSmallButton(systemName: "arrow.up.left.and.arrow.down.right") {
                        model.enterFullscreen()
                    }
                    .accessibilityLabel("Fullscreen")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, variant == .landscape ? 14 : 12)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Quality badge

private struct QualityBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(PlinkRave.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}
