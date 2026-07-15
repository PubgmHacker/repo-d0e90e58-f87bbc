// Plink/Features/WatchRoom/WatchChatView.swift — PATCH 02 polish
//
// Professional design:
//   - Living backdrop at 0.28 opacity (was 0.4) — readable but still alive
//   - Bottom gradient overlay for composer legibility
//   - Scroll-to-bottom button: 40pt circle with elevation (was pill)
//   - Message spacing: 12pt (was 10pt)
//   - Top padding: 8pt (new — gives breathing room)
//   - LazyVStack alignment: .leading (kept)
//
// V5: WatchChatBubble inlined here (no separate file).

import SwiftUI

struct WatchChatView: View {
    let model: WatchRoomModel
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.chatMessages) { message in
                        WatchChatBubbleInline(
                            message: message,
                            isOwn: message.senderId == model.currentUserId,
                            onRetry: { model.retryChatMessage(message) }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .background(
                Cinema2026.background.ignoresSafeArea()
                    .opacity(0.28)
            )
            .onChange(of: model.chatMessages.count) { _, _ in
                guard atBottom, let last = model.chatMessages.last else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    reader.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && model.unreadCount > 0 {
                    Button {
                        if let last = model.chatMessages.last {
                            withAnimation(.easeOut(duration: 0.22)) {
                                reader.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(model.unreadCount)")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Cinema2026.text)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Scroll to latest message")
                }
            }
        }
    }
}

// MARK: - WatchChatBubbleInline (V5 — replaces deleted WatchChatBubble.swift)

private struct WatchChatBubbleInline: View {
    let message: ChatMessageInfo
    let isOwn: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 56) }
            if !isOwn { ChatAvatarInline(message: message) }

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
                                .foregroundStyle(Cinema2026.accent)
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
                    .background(bubbleBackground)
                    .clipShape(V5WatchBubbleShape(isOwn: isOwn))
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

            if isOwn { ChatAvatarInline(message: message) }
            if !isOwn { Spacer(minLength: 56) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isOwn {
            Cinema2026.outgoingBubble
        } else {
            Cinema2026.surface.opacity(0.92)
        }
    }

    private var roleColor: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.accent }
        return Cinema2026.secondary
    }
}

private struct ChatAvatarInline: View {
    let message: ChatMessageInfo

    private var initials: String {
        let parts = message.senderName.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return letters.map { String($0).uppercased() }.joined()
    }

    var body: some View {
        Circle()
            .fill(Cinema2026.accent.opacity(0.25))
            .overlay(Text(initials).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            .frame(width: 28, height: 28)
    }
}

// MARK: - V5WatchBubbleShape

private struct V5WatchBubbleShape: Shape {
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
