// Plink/Views/Chat/EmojiPickerGrid.swift
//
// GPT-5.6 SOL fix: EmojiPickerGrid was previously in a deleted file.
// Recreated here as a minimal grid for DM chat emoji selection.
// Used by DMChatView.

import SwiftUI

/// Inline emoji picker grid for DM chat.
/// Tapping an emoji inserts it into the message text.
struct EmojiPickerGrid: View {
    @Binding var chatText: String

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    private let emojis: [String] = [
        "😀", "😂", "😍", "🥰", "😘", "🤗",
        "🤔", "🤩", "🥳", "😭", "😱", "🤯",
        "👍", "👎", "👏", "🙌", "🤝", "💪",
        "❤️", "🔥", "✨", "🎉", "💯", "⚡",
        "🌟", "💎", "👑", "🚀", "🌈", "🎬",
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    chatText += emoji
                    HapticManager.impact(.light)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Emoji \(emoji)")
            }
        }
        .padding(12)
        .background(Cinema2026.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
    }
}
