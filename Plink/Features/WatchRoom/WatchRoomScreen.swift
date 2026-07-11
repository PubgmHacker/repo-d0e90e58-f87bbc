// Plink/Features/WatchRoom/WatchRoomScreen.swift — PATCH 02 + 04
//
// Commit Group 2: full PATCH 02 view hierarchy split + PATCH 04 stable
// rotation.
//
// Layout variant is derived purely from size classes — no
// OrientationCoordinator forcing, no .onAppear orientation lock. System
// rotation drives layout; the user's fullscreen action is a separate
// presentation, not a forced interface rotation.
//
// Player identity stability (PATCH 04):
//   - PlaybackCoordinator owns the AVPlayer; EmbeddedPlaybackController
//     owns the WKWebView. SwiftUI may rebuild PlayerStage's view tree on
//     layout switch, but the underlying player is NEVER recreated.
//   - PlayerStage uses .id("plink.player.stage") so SwiftUI's diff treats
//     it as the same view across layout switches where possible.
//   - prepare() is only called once by the coordinator, never by the view.
//
// Animation: .plinkLayout (0.42s smooth spring, damping 0.92).

import SwiftUI

struct WatchRoomScreen: View {
    @Bindable var model: WatchRoomModel

    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?

    private var layoutVariant: WatchRoomLayoutState.Variant {
        if widthClass == .regular && heightClass != .compact { return .tablet }
        if heightClass == .compact { return .landscape }
        return .portrait
    }

    var body: some View {
        ZStack {
            PurpleAmbientBackdrop(state: ui.ambient)

            switch layoutVariant {
            case .portrait:
                PortraitWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            case .landscape:
                LandscapeWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            case .tablet:
                TabletWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            }

            WatchReactionLayer(events: model.reactions, reduceMotion: reduceMotion)
                .allowsHitTesting(false)

            if let toast = ui.activeToast {
                RoomToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }
        }
        .background(PlinkRave.void.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.plinkLayout, value: layoutVariant)
        .task { await model.connect() }
        .onDisappear {
            controlsHideTask?.cancel()
            model.disconnect()
        }
        .onTapGesture {
            guard !ui.chatPresented else { return }
            withAnimation(.plinkControls) {
                ui.controlsVisible.toggle()
            }
            scheduleControlsHide()
        }
        .sheet(isPresented: $ui.chatPresented) {
            WatchChatSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(PlinkRave.void)
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        guard ui.controlsVisible, model.coordinator.isPlaying, !ui.isScrubbing else { return }

        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.plinkControls) {
                ui.controlsVisible = false
            }
        }
    }
}
