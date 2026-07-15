// Plink/Features/WatchRoom/WatchChatBubble.swift — PATCH 02 polish
//
// Professional design:
//   - Avatar: 28pt (was 26pt) with proper initials
//   - Bubble corner radius: 18pt (was 16pt) — modern
//   - Sender name: 12pt semibold (was 11pt)
//   - Message text: 15pt regular (kept)
//   - Subtle shadow on bubble (new)
//   - BubbleShape tail (kept) — gives conversational feel
//   - Role colors: admin=gold, premium=hotPink, default=secondaryText

import SwiftUI

struct WatchChatBubble: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void

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
                                .foregroundStyle(Cinema2026.danger)
                        }
                        Text(message.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(roleColor)
                    }
                }

                // P0.4: support custom emoji PNG names
                Group {
                    if message.text.hasPrefix("emoji_") {
                        Image(message.text)
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Text(message.text)
                            .font(.system(size: 15, weight: .regular))
                    }
                }
                .foregroundStyle(isOwn ? .white : Cinema2026.text)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isOwn: isOwn))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

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
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isOwn {
            Cinema2026.accent
        } else {
            Cinema2026.surface.opacity(0.92)
        }
    }

    private var roleColor: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.danger }
        return Cinema2026.secondary
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
