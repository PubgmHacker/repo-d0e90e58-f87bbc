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
    @Environment(\.dismiss) private var dismiss  // PATCH 26: dismiss fullScreenCover on leave

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?

    private var layoutVariant: WatchRoomLayoutState.Variant {
        if widthClass == .regular && heightClass != .compact { return .tablet }
        if heightClass == .compact { return .landscape }
        return .portrait
    }

    var body: some View {
        ZStack {
            // PATCH 14: ambient state now comes from model (driven by
            // AmbientVideoSampler). ui.ambient is no longer used.
            Cinema2026.background.ignoresSafeArea()

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

            // PATCH 14: Rutube fallback toast — shown when source is .rutube
            // and the embedded player's JS API is unavailable. Tapping
            // "Open" launches SFSafariViewController with the Rutube video URL.
            if model.requiresRutubeFallback {
                RutubeFallbackToast(onOpen: {
                    model.openInRutubeExternal()
                })
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(101)
            }
        }
        .background(Cinema2026.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.plinkLayout, value: layoutVariant)
        .onChange(of: layoutVariant) { _, newVariant in
            // PATCH 14: update danmaku lane count on rotation.
            // Portrait = 5 lanes, landscape = 7 lanes, tablet = 5 lanes.
            let laneCount: Int
            switch newVariant {
            case .portrait:  laneCount = 5
            case .landscape: laneCount = 7
            case .tablet:    laneCount = 5
            }
            model.updateDanmakuLaneCount(laneCount)
        }
        .task { await model.connect() }
        .onDisappear {
            // Brain Phase 6: do NOT disconnect here — onDisappear fires on
            // rotation when SwiftUI rebuilds the view tree. The model's
            // connect()/disconnect() are now idempotent, so rotation is safe.
            // Disconnect only on explicit leaveRoom (X button) — see
            // onChange(connectionState == .idle) below which dismisses
            // the fullScreenCover, and WatchRoomModel.disconnect() is
            // called by leaveRoom() only.
            controlsHideTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OrientationManager.shared.unlockOrientation()
            }
        }
        .onChange(of: model.connectionState) { _, newState in
            // PATCH 26: auto-dismiss when disconnected (after leaveRoom)
            if newState == .idle {
                dismiss()
            }
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
                .presentationBackground(Cinema2026.background)
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
