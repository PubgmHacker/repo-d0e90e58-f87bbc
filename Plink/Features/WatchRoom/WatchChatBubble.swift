import SwiftUI

struct WatchChatBubble: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 62) }
            if !isOwn { ChatAvatar(message: message) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    Text(message.senderName.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(roleColor)
                }

                Text(message.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOwn ? PlinkRave.text : Color(hex: 0xE6DCEB))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(bubbleBackground)
                    .clipShape(BubbleShape(isOwn: isOwn))
                    .overlay {
                        if !isOwn {
                            BubbleShape(isOwn: false)
                                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        }
                    }

                if message.isPending {
                    Label("Sending", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(PlinkRave.textSecondary)
                } else if message.isFailed {
                    Button(action: onRetry) {
                        Label("Tap to retry", systemImage: "arrow.clockwise")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PlinkRave.danger)
                    }
                }
            }

            if isOwn { ChatAvatar(message: message) }
            if !isOwn { Spacer(minLength: 62) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)))
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isOwn { PlinkRave.outgoingBubble } else { PlinkRave.surface }
    }

    private var roleColor: Color {
        message.isAdmin ? Color(hex: 0xFFD700) : message.isPremium ? PlinkRave.hotPink : PlinkRave.cyan
    }
}

struct BubbleShape: Shape {
    let isOwn: Bool
    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(
            topLeading: isOwn ? 16 : 6,
            bottomLeading: 16,
            bottomTrailing: 16,
            topTrailing: isOwn ? 6 : 16
        )
        return Path(roundedRect: rect, cornerRadii: radii)
    }
}
