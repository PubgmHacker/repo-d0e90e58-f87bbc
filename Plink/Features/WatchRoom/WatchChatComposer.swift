import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.openEmojiPicker) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 16))
                    .foregroundStyle(PlinkRave.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(PlinkRave.raised, in: Circle())
            }
            .accessibilityLabel("Emoji")

            TextField("Message...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundStyle(PlinkRave.text)
                .tint(PlinkRave.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PlinkRave.raised, in: RoundedRectangle(cornerRadius: 20))

            Button {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                model.sendChat(text: value)
                text = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Group {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                PlinkRave.raised
                            } else {
                                PlinkRave.primaryAction
                            }
                        },
                        in: Circle()
                    )
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connectionState != .connected)
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
