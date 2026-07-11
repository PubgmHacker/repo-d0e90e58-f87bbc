import SwiftUI

struct WatchChatComposer: View {
    let model: WatchRoomModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.openEmojiPicker) {
                Image(systemName: "sparkles")
                    .foregroundStyle(PlinkRave.hotPink)
                    .frame(width: 42, height: 42)
                    .background(PlinkRave.raised, in: Circle())
            }
            .accessibilityLabel("Custom emoji")

            TextField("Say something...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(PlinkRave.text)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(PlinkRave.void, in: RoundedRectangle(cornerRadius: 20))

            Button {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                model.sendChat(text: value)
                text = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(PlinkRave.text)
                    .frame(width: 40, height: 40)
                    .background(PlinkRave.magenta, in: Circle())
                    .plinkGlow(PlinkRave.cyan, radius: 8)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connectionState != .connected)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(PlinkRave.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(PlinkRave.magenta.opacity(0.30)).frame(height: 1)
        }
    }
}
