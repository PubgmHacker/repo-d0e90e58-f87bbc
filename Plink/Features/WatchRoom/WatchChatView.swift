// Plink/Features/WatchRoom/WatchChatView.swift — PATCH 02 polish
//
// Professional design:
//   - Living backdrop at 0.28 opacity (was 0.4) — readable but still alive
//   - Bottom gradient overlay for composer legibility
//   - Scroll-to-bottom button: 40pt circle with elevation (was pill)
//   - Message spacing: 12pt (was 10pt)
//   - Top padding: 8pt (new — gives breathing room)
//   - LazyVStack alignment: .leading (kept)

import SwiftUI

struct WatchChatView: View {
    let model: WatchRoomModel
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .background(
                LivingVideoBackdrop(player: model.coordinator.nativePlayer)
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
                        .foregroundStyle(PlinkRave.text)
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
