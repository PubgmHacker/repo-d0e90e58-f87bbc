// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 26: Telegram-style emoji
//
// PATCH 26: inline emoji panel (Telegram-style) instead of popover.

import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel

    @State private var state = ChatComposerState()
    @State private var showEmojiPanel = false

    private var canSend: Bool {
        state.canSend(connected: model.connectionState == .connected)
    }

    private var hasPremium: Bool {
        PremiumStatusManager.shared.isPremium
    }

    var body: some View {
        VStack(spacing: 0) {
            // PATCH 26: inline emoji panel (Telegram-style)
            if showEmojiPanel {
                EmojiInlinePanel(
                    hasPremium: hasPremium,
                    onPick: { emoji in
                        state.insertAtCursor(emoji)
                    },
                    onPremiumUpsell: {
                        showEmojiPanel = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showEmojiPanel.toggle()
                    }
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                        .font(.system(size: 17))
                        .foregroundStyle(PlinkRave.secondaryText)
                        .frame(width: 40, height: 40)
                        .background(PlinkRave.raised, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                }
                .accessibilityLabel("Emoji")

                VStack(spacing: 4) {
                    TextField("Message…", text: $state.text, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 15))
                        .foregroundStyle(PlinkRave.text)
                        .tint(PlinkRave.magenta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PlinkRave.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    state.isOverLength ? PlinkRave.danger : .white.opacity(0.05),
                                    lineWidth: state.isOverLength ? 1 : 0.5
                                )
                        )

                    if state.isOverLength {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("\(state.trimmedText.count)/\(ChatComposerState.maxLength) — too long")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(PlinkRave.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }

                Button {
                    let value = state.trimmedText
                    guard state.canSend(connected: model.connectionState == .connected) else { return }
                    model.sendChat(text: value)
                    state.clearAfterSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            canSend
                                ? AnyShapeStyle(PlinkRave.primaryAction)
                                : AnyShapeStyle(PlinkRave.raised),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
                }
                .disabled(!canSend || state.isOverLength)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PlinkRave.surface.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PlinkRave.divider.opacity(0.4))
                    .frame(height: 0.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .plinkInsertAtCursor)) { note in
                if let insertion = note.userInfo?["text"] as? String {
                    state.insertAtCursor(insertion)
                }
            }
        }
    }
}

// MARK: - PATCH 26: Inline emoji panel (Telegram-style)

struct EmojiInlinePanel: View {
    let hasPremium: Bool
    let onPick: (String) -> Void
    let onPremiumUpsell: () -> Void

    private let freeEmojis = ["❤️", "😂", "😢", "😡", "😮", "🔥", "👏", "💜"]
    private let premiumEmojis = ["🎉", "🤩", "🥳", "😎", "🤔", "🥺", "😭", "🤣", "💯", "✨", "🌟", "💫", "👑", "🏆", "🚀", "🌈"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(freeEmojis, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                }

                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 4)

                ForEach(premiumEmojis, id: \.self) { emoji in
                    Button {
                        if hasPremium {
                            onPick(emoji)
                        } else {
                            onPremiumUpsell()
                        }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .opacity(hasPremium ? 1.0 : 0.4)
                            .overlay {
                                if !hasPremium {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(PlinkRave.gold)
                                        .offset(x: 14, y: -14)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(PlinkRave.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(PlinkRave.divider.opacity(0.4)).frame(height: 0.5)
        }
    }
}

// MARK: - Emoji picker notification

extension Notification.Name {
    static let plinkInsertAtCursor = Notification.Name("plinkInsertAtCursor")
}
