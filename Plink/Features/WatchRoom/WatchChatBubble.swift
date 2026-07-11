import SwiftUI

struct WatchChatBubble: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 52) }
            if !isOwn { ChatAvatar(message: message) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(roleColor)
                }

                Text(message.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isOwn ? .white : PlinkRave.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(BubbleShape(isOwn: isOwn))

                if message.isPending {
                    Text("Sending...")
                        .font(.system(size: 10))
                        .foregroundStyle(PlinkRave.textTertiary)
                } else if message.isFailed {
                    Button(action: onRetry) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PlinkRave.danger)
                    }
                }
            }

            if isOwn { ChatAvatar(message: message) }
            if !isOwn { Spacer(minLength: 52) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isOwn {
            PlinkRave.outgoingBubble
        } else {
            PlinkRave.surface.opacity(0.85)
        }
    }

    private var roleColor: Color {
        message.isAdmin ? PlinkRave.gold : message.isPremium ? PlinkRave.accent : PlinkRave.textSecondary
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
