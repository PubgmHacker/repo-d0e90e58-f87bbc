import SwiftUI

struct WatchRoomScreen: View {
    @Bindable var model: WatchRoomModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isTablet: Bool { horizontalSizeClass == .regular && !isLandscape }

    var body: some View {
        ZStack {
            PurpleAmbientBackdrop()

            if isTablet {
                TabletWatchLayout(model: model, ui: $ui)
            } else if isLandscape {
                LandscapeWatchLayout(model: model, ui: $ui)
            } else {
                PortraitWatchLayout(model: model, ui: $ui)
            }

            WatchReactionLayer(
                reactions: model.reactions,
                reduceMotion: reduceMotion
            )

            if let toast = ui.activeToast {
                RoomToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }
        }
        .background(PlinkRave.void.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await model.connect() }
        .onDisappear {
            controlsHideTask?.cancel()
            model.disconnect()
        }
        .onTapGesture {
            guard !ui.chatPresented else { return }
            withAnimation(.easeOut(duration: 0.18)) {
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
            withAnimation(.easeIn(duration: 0.14)) {
                ui.controlsVisible = false
            }
        }
    }
}
