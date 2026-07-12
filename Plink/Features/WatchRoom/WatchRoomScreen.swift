// Plink/Features/WatchRoom/WatchRoomScreen.swift — GPT-5.6 Final §2-3
//
// Player viewport is NEVER decorated. Theme applies only to social region.
// NeutralPlayerContainer wraps PlayerStage with plain black background.
// WatchRoomSocialRegion wraps chat/presence/AI with living theme.

import SwiftUI

struct WatchRoomScreen: View {
    @Bindable var model: WatchRoomModel

    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?

    private var layoutVariant: WatchRoomLayoutState.Variant {
        if widthClass == .regular && heightClass != .compact { return .tablet }
        if heightClass == .compact { return .landscape }
        return .portrait
    }

    var body: some View {
        ZStack {
            Cinema2026.void.ignoresSafeArea()

            // GPT-5.6 Final §2: playerRegion — NEUTRAL, no decoration
            NeutralPlayerContainer {
                PlayerStage(model: model, ui: $ui, variant: ui.variant)
                    .id(model.roomID ?? "plink.player.stage")
            }

            // GPT-5.6 Final §4: themedSocialRegion — theme applies ONLY here
            WatchRoomSocialRegion(model: model)

            WatchReactionLayer(events: model.reactions, reduceMotion: reduceMotion)
                .allowsHitTesting(false)

            if let toast = ui.activeToast {
                RoomToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }

            if model.requiresRutubeFallback {
                RutubeFallbackToast(onOpen: { model.openInRutubeExternal() })
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(101)
            }
        }
        .background(Cinema2026.void.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: layoutVariant) { _, newVariant in
            ui.variant = newVariant
            let laneCount: Int
            switch newVariant {
            case .portrait:  laneCount = 5
            case .landscape: laneCount = 7
            case .tablet:    laneCount = 5
            }
            model.updateDanmakuLaneCount(laneCount)
        }
        .onAppear { ui.variant = layoutVariant }
        .task { await model.connect() }
        .onDisappear {
            controlsHideTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OrientationManager.shared.unlockOrientation()
            }
        }
        .onChange(of: model.connectionState) { _, newState in
            if newState == .idle { dismiss() }
        }
        .onTapGesture {
            guard !ui.chatPresented else { return }
            withAnimation(.plinkControls) { ui.controlsVisible.toggle() }
            scheduleControlsHide()
        }
        .sheet(isPresented: $ui.chatPresented) {
            WatchChatSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Cinema2026.background)
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        guard ui.controlsVisible, model.coordinator.isPlaying, !ui.isScrubbing else { return }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.plinkControls) { ui.controlsVisible = false }
        }
    }
}
