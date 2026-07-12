// Plink/Views/AI/AIAssistantView.swift — simplified (V4 has full AI screen)
import SwiftUI

struct AIAssistantView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(Cinema2026.accent)
            Text("ИИ-помощник")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Cinema2026.text)
            Text("Скоро будет доступен на iPhone")
                .font(.system(size: 15))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }
}
