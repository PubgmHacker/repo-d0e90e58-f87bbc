import SwiftUI

// MARK: - Language Picker View
/// Экран выбора языка приложения. Переключает язык мгновенно в рантайме.
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(spacing: 14) {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                loc.currentLanguage = lang
                            }
                            // Закрываем с задержкой чтобы анимация переключения была видна
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Text(lang.flag)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang.nativeName)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.raveTextPrimary)
                                }

                                Spacer()

                                if loc.currentLanguage == lang {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.ravePrimary)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                loc.currentLanguage == lang
                                    ? Color.ravePrimary.opacity(0.15)
                                    : Color.raveCard
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        loc.currentLanguage == lang
                                            ? Color.ravePrimary.opacity(0.4)
                                            : Color.raveSurface,
                                        lineWidth: 1
                                    )
                            )
                        }
                    }

                    Spacer()

                    Text(loc.string(.profileLanguageSubtitle))
                        .font(.caption2)
                        .foregroundColor(.raveTextSecondary.opacity(0.6))
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
            }
            .navigationTitle(loc.string(.profileLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
        }
    }
}
