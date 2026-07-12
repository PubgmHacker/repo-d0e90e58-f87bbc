// Plink/Features/WatchRoom/WatchRoomScreen.swift — Brain Revision 3 Step 5
//
// Single structural PlayerStage via WatchRoomRootLayout.
//
// Brain: "Identity is scoped by structural path. Runtime evidence is required,
// and the safer architecture is one player surface outside the portrait/landscape switch."
//
// WatchRoomRootLayout places PlayerStage at the ZStack root with .id(model.roomID).
// Portrait/Landscape/Tablet chrome overlays it; the player is never recreated.
//
// Connection state machine (Brain Revision 3 Step 5):
//   idle -> connecting -> joining -> synchronizing -> connected
// Only realtime callbacks move between these states. connect() no longer
// sets .connected unconditionally — it sets .connecting and waits for
// realtime session-ready/snapshot handshake to promote to .connected.

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
            Cinema2026.background.ignoresSafeArea()

            // Brain Revision 3: single structural PlayerStage outside the switch.
            // ui.variant is updated via .onChange below; the player's .id stays
            // stable across layout switches.
            WatchRoomRootLayout(model: model, ui: $ui)

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
        .onChange(of: layoutVariant) { _, newVariant in
            // Brain Revision 3: update ui.variant (drives chrome switch).
            // PlayerStage is in WatchRoomRootLayout and is NOT recreated.
            ui.variant = newVariant

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
        .onAppear {
            // Initialize ui.variant on first appearance.
            ui.variant = layoutVariant
        }
        .task { await model.connect() }
        .onDisappear {
            // Brain Revision 3: do NOT disconnect here — onDisappear fires on
            // rotation when SwiftUI rebuilds the view tree. The model's
            // connect()/disconnect() are idempotent, so rotation is safe.
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
