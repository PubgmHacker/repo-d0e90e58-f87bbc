// Plink/Features/AI/PlinkAIComposer.swift — GPT-5.6 §11
import SwiftUI

struct PlinkAIComposer: View {
    @Binding var text: String
    let onSend: () -> Void
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Спросите ИИ...", text: $text)
                .textFieldStyle(RaveTextFieldStyle())
                .disabled(isLoading)
            Button(action: onSend) {
                Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Cinema2026.accent)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(16)
    }
}
