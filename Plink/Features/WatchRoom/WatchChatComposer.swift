// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 02: composer
//
// Commit Group 1: fix ShapeStyle conformance error at the send button.
// The original code wrapped Color/LinearGradient in a Group inside
// `.background(_, in: Circle())` — that produces a View, not a ShapeStyle,
// and the `background(_:in:fillStyle:)` overload rejects it. Switching to
// AnyShapeStyle keeps both branches as ShapeStyle-conforming values and
// preserves the visual intent (dim circle when empty, gradient when armed).
//
// Token usage aligned to PATCH 01: outgoingBubble gradient and raised
// surface for the disabled state; magenta for the send glyph.

import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel
    @State private var text = ""

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty && model.connectionState == .connected
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.openEmojiPicker) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 16))
                    .foregroundStyle(PlinkRave.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(PlinkRave.raised, in: Circle())
            }
            .accessibilityLabel("Emoji")

            TextField("Message...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundStyle(PlinkRave.text)
                .tint(PlinkRave.magenta)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PlinkRave.raised, in: RoundedRectangle(cornerRadius: 20))

            Button {
                let value = trimmedText
                guard !value.isEmpty else { return }
                model.sendChat(text: value)
                text = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend
                            ? AnyShapeStyle(PlinkRave.primaryAction)
                            : AnyShapeStyle(PlinkRave.raised),
                        in: Circle()
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(PlinkRave.surface.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle().fill(PlinkRave.divider.opacity(0.5)).frame(height: 0.5)
        }
    }
}
