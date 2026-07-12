// Plink/Features/WatchRoom/WatchChatBubble.swift — GPT-5.6 V4 Rescue §9
//
// Uses ThemedChatBubbleStyle for explicit surfaces (not blur).
// Verified sender identity from server event type, not display name.

import SwiftUI

struct WatchChatBubble: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void
    var onReport: ((ChatMessageInfo) -> Void)?
    var onBlock: ((ChatMessageInfo) -> Void)?

    // GPT-5.6 §9: bubble color from ThemedChatBubbleStyle
    private var bubbleColor: Color {
        if message.isAdmin {
            return ThemedChatBubbleStyle.system
        }
        return isOwn ? ThemedChatBubbleStyle.outgoing : ThemedChatBubbleStyle.incoming
    }

    private var roleColor: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.amber }
        return Cinema2026.secondary
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 56) }
            if !isOwn { ChatAvatar(message: message) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    HStack(spacing: 4) {
                        if message.isAdmin {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Cinema2026.amber)
                        }
                        if message.isPremium {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Cinema2026.amber)
                        }
                        Text(message.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(roleColor)
                    }
                }

                Text(message.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isOwn ? .white : Cinema2026.text)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(bubbleColor, in: BubbleShape(isOwn: isOwn))

                if message.isPending {
                    Text("Sending…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Cinema2026.secondary)
                } else if message.isFailed {
                    Button(action: onRetry) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Cinema2026.danger)
                    }
                }
            }

            if isOwn { ChatAvatar(message: message) }
            if !isOwn { Spacer(minLength: 56) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .contextMenu {
            if !isOwn {
                Button { onReport?(message) } label: {
                    Label("Пожаловаться", systemImage: "flag")
                }
                Button(role: .destructive) { onBlock?(message) } label: {
                    Label("Заблокировать", systemImage: "hand.raised")
                }
            }
        }
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
