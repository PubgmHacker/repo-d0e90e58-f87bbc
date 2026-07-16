// Plink/Features/WatchRoom/PlayerStage.swift — GPT-5.6 V4 Rescue §7
//
// Neutral player stage. NO decoration: no glow, no border, no glass,
// no theme stroke, no theme shadow, no theme corner radius.
// Background: plain black. Provider owns controls.

import SwiftUI

struct PlayerStage: View {
    @Bindable var model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant

    var body: some View {
        ZStack {
            // GPT-5.6 §3: plain black background, nothing else
            Color.black

            // Player surface — never decorated
            PlayerSurfaceView(coordinator: model.coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Danmaku layer (above video, below chrome)
            DanmakuCanvasLayer(
                placements: model.danmakuPlacements,
                laneCount: model.danmakuLaneCount,
                opacity: model.danmakuOpacity
            )
            .padding(.horizontal, 8)
            .padding(.top, 60)
            .padding(.bottom, 80)

            // Functional overlays only (no decorative)
            if model.coordinator.isPreparing {
                PlayerLoadingView()
                    .transition(.opacity)
            }
            if model.coordinator.isBuffering && !model.coordinator.isPreparing {
                BufferingOverlay()
                    .transition(.opacity)
            }

            // Top chrome only (functional, not decorative)
            if ui.controlsVisible {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)

                PlayerTopChrome(model: model, variant: variant)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                // Host sync control — ensures multi-device play/pause even when
                // YouTube chrome events are missed (MVP reliability).
                if model.isHost {
                    PlayerCenterControl(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        // FORBIDDEN: PlinkLivingBackground, glassCard, neonGlow, theme stroke,
        // theme shadow, theme corner radius. None of these appear here.
    }
}
