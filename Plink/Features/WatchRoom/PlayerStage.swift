// Plink/Features/WatchRoom/PlayerStage.swift — PATCH 02 + 04
//
// Stable player surface root. Holds the AVPlayer/UIViewRepresentable at the
// top of its ZStack so orientation changes do NOT recreate it. Layouts
// position this view; they never own or replace it.
//
// Visual design (professional polish):
//   - Player viewport: Cinema2026.background (not pure black) — letterbox bars
//     are purple-tinted, matching the room's ambient tone.
//   - Chrome: .ultraThinMaterial over void for depth, not flat color.
//   - Top gradient: 0→0.55 opacity void, gives top chrome legibility
//     without darkening the video.
//   - Bottom gradient: 0→0.7 opacity void, same purpose.
//   - Center control: 64pt circle (was 52pt) with proper backdrop.
//   - Danmaku layer above video but below chrome.
//
// PATCH 04: this view does NOT observe orientation. The `variant` parameter
// only affects corner radius (0 for landscape fullscreen, 14 for portrait/
// tablet). The underlying PlayerSurfaceView is the same instance across
// rotations because PlayerStage itself has a stable .id in WatchRoomScreen.

import SwiftUI

struct PlayerStage: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant

    private var cornerRadius: CGFloat {
        switch variant {
        case .landscape: return 0
        case .portrait, .tablet: return 14
        }
    }

    var body: some View {
        ZStack {
            // Viewport — purple-tinted void, NOT pure black
            Cinema2026.background.ignoresSafeArea()

            // The actual player surface — never recreated
            PlayerSurfaceView(coordinator: model.coordinator)
                .ignoresSafeArea(variant == .landscape ? .all : [])

            // Danmaku layer above video, below chrome
            DanmakuCanvasLayer(
                placements: model.danmakuPlacements,
                laneCount: model.danmakuLaneCount,
                opacity: model.danmakuOpacity
            )
            .padding(.horizontal, 8)
            .padding(.top, 60)
            .padding(.bottom, 80)

            // Loading state (initial buffer)
            if model.coordinator.isPreparing {
                PlayerLoadingView()
                    .transition(.opacity)
            }

            // Buffering state (mid-playback rebuffer)
            if model.coordinator.isBuffering && !model.coordinator.isPreparing {
                BufferingOverlay()
                    .transition(.opacity)
            }

            // Chrome — only visible when controls are shown
            if ui.controlsVisible {
                // Top legibility gradient
                LinearGradient(
                    colors: [Cinema2026.background.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)

                // Bottom legibility gradient
                LinearGradient(
                    colors: [.clear, Cinema2026.background.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)

                PlayerTopChrome(model: model, variant: variant)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                PlayerCenterControl(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))

                PlayerBottomControls(model: model, ui: $ui, variant: variant)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if variant != .landscape {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Cinema2026.divider.opacity(0.4), lineWidth: 0.5)
            }
        }
        .animation(.plinkControls, value: ui.controlsVisible)
        .animation(.plinkControls, value: model.coordinator.isPreparing)
        .animation(.plinkControls, value: model.coordinator.isBuffering)
    }
}
