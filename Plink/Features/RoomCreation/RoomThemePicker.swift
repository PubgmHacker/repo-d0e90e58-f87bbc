// Plink/Features/RoomCreation/RoomThemePicker.swift — GPT-5.6 §8
import SwiftUI

struct RoomThemePicker: View {
    let hasPremium: Bool
    @Binding var selectedID: String
    let openPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Оформление комнаты").font(.headline).foregroundStyle(Cinema2026.text)
                Spacer()
                if !hasPremium { Text("PLINK+").font(.caption.bold()).foregroundStyle(Cinema2026.amber) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(PlinkThemeCatalog.all) { theme in
                        ThemePreview(theme: theme, selected: theme.id == selectedID)
                            .onTapGesture {
                                if theme.access == .premium && !hasPremium { openPaywall() }
                                else { selectedID = theme.id }
                            }
                    }
                }
            }
        }
    }
}

private struct ThemePreview: View {
    let theme: PlinkLivingTheme; let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(colors: theme.colors.map { $0.color }, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if theme.access == .premium {
                    Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(Cinema2026.amber).padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Cinema2026.accent : .clear, lineWidth: 2))
            Text(theme.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Cinema2026.text)
        }
    }
}
