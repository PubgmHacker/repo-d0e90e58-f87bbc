// Plink/Features/WatchRoom/AI/AIModerationNotice.swift — GPT-5.6 §13-14
import SwiftUI

struct AIModerationNotice: View {
    let reasonCode: String
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 14)).foregroundStyle(Cinema2026.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Модерация ИИ").font(.system(size: 12, weight: .semibold)).foregroundStyle(Cinema2026.text)
                Text(message).font(.system(size: 11)).foregroundStyle(Cinema2026.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Cinema2026.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
    }
}
