// Plink/Features/AI/PlinkAIChatView.swift — GPT-5.6 §11
import SwiftUI

struct PlinkAIChatView: View {
    @State private var model = PlinkAIViewModel()
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.messages) { msg in
                        AIBubble(message: msg)
                    }
                }
                .padding(16)
            }
            HStack(spacing: 10) {
                TextField("Спросите ИИ...", text: $input)
                    .textFieldStyle(RaveTextFieldStyle())
                Button {
                    Task { await model.send(input); input = "" }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Cinema2026.accent)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
            }
            .padding(16)
        }
    }
}

private struct AIBubble: View {
    let message: PlinkAIMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(message.role == .user ? .white : Cinema2026.text)
                .padding(12)
                .background(message.role == .user ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
            if message.role != .user { Spacer() }
        }
    }
}
