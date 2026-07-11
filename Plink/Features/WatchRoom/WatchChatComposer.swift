// Plink/Features/WatchRoom/WatchChatComposer.swift — PATCH 02 polish
//
// Commit Group 1: fixed ShapeStyle conformance error (Group<Color|LinearGradient>
// → AnyShapeStyle).
// Commit Group 2: professional sizing — 40pt send button (was 36pt),
// 22pt corner radius (was 20pt), 14pt emoji button (was 16pt icon in 38pt circle).
//
// Token usage (PATCH 01 spec):
//   - magenta for send glyph background (via outgoingBubble/primaryAction)
//   - raised for disabled state and emoji button
//   - secondaryText for placeholder icon
//   - text for input

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
        HStack(spacing: 10) {
            Button(action: model.openEmojiPicker) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17))
                    .foregroundStyle(PlinkRave.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(PlinkRave.raised, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.05), lineWidth: 0.5))
            }
            .accessibilityLabel("Emoji")

            TextField("Message…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundStyle(PlinkRave.text)
                .tint(PlinkRave.magenta)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PlinkRave.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )

            Button {
                let value = trimmedText
                guard !value.isEmpty else { return }
                model.sendChat(text: value)
                text = ""
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
            .disabled(!canSend)
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
    }
}
