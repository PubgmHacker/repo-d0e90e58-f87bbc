import SwiftUI

struct PortraitWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        VStack(spacing: 0) {
            PlayerStage(model: model, ui: $ui, style: .portrait)
                .aspectRatio(16 / 9, contentMode: .fit)

            PresenceBar(model: model)
                .frame(height: 52)

            WatchChatView(model: model)
                .frame(maxHeight: .infinity)

            WatchChatComposer(model: model)
        }
        .safeAreaPadding(.top, 0)
    }
}

struct LandscapeWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        ZStack(alignment: .trailing) {
            PlayerStage(model: model, ui: $ui, style: .landscape)
                .ignoresSafeArea()

            if ui.chatDrawerVisible {
                LandscapeChatDrawer(model: model, isVisible: $ui.chatDrawerVisible)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.24)) {
                        ui.chatDrawerVisible = true
                    }
                } label: {
                    Image(systemName: "message.fill")
                        .foregroundStyle(PlinkRave.text)
                        .frame(width: 44, height: 44)
                        .background(PlinkRave.surface, in: Circle())
                }
                .padding(.trailing, 12)
                .accessibilityLabel("Open chat")
            }
        }
    }
}

struct TabletWatchLayout: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PlayerStage(model: model, ui: $ui, style: .tablet)
                    .aspectRatio(16 / 9, contentMode: .fit)

                RoomIdentityBar(model: model)
                PresenceBar(model: model)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(PlinkRave.divider.opacity(0.55))
                .frame(width: 1)

            VStack(spacing: 0) {
                WatchChatHeader(model: model)
                WatchChatView(model: model)
                WatchChatComposer(model: model)
            }
            .frame(width: 380)
            .background(PlinkRave.void.opacity(0.98))
        }
    }
}
