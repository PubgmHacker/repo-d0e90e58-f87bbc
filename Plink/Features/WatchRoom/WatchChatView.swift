import SwiftUI

struct WatchChatView: View {
    let model: WatchRoomModel
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.chatMessages) { message in
                        WatchChatBubble(
                            message: message,
                            isOwn: message.senderId == model.currentUserId,
                            onRetry: { model.retryChatMessage(message) }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(
                // Living video backdrop — chat breathes with the movie
                LivingVideoBackdrop(player: model.coordinator.nativePlayer)
                    .opacity(0.4)
            )
            .onChange(of: model.chatMessages.count) { _, _ in
                guard atBottom, let last = model.chatMessages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last.id, anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && model.unreadCount > 0 {
                    Button("\(model.unreadCount) new") {
                        if let last = model.chatMessages.last { reader.scrollTo(last.id, anchor: .bottom) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlinkRave.text)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(PlinkRave.primary, in: Capsule())
                    .padding(12)
                }
            }
        }
    }
}
