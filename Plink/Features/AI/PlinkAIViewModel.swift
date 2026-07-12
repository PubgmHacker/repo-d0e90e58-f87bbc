// Plink/Features/AI/PlinkAIViewModel.swift — GPT-5.6 §11
import SwiftUI

@MainActor
@Observable
final class PlinkAIViewModel {
    var messages: [PlinkAIMessage] = []
    var visualState: PlinkAIVisualState = .idle
    var isLoading = false

    func send(_ text: String) async {
        messages.append(PlinkAIMessage(role: .user, text: text))
        visualState = .thinking
        isLoading = true
        // Backend call would go here — for now, simulate
        try? await Task.sleep(for: .seconds(1))
        messages.append(PlinkAIMessage(role: .assistant, text: "Я помогу найти видео для совместного просмотра. Что вас интересует?"))
        visualState = .speaking
        isLoading = false
        try? await Task.sleep(for: .seconds(2))
        visualState = .idle
    }
}
