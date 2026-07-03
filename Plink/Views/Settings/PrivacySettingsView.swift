import SwiftUI

// MARK: - Privacy Settings View
/// Экран настроек конфиденциальности.
struct PrivacySettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profileVisibility = true
    @State private var onlineStatus = true
    @State private var readReceipts = true

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Профиль
                        settingsCard {
                            ToggleRow(
                                icon: "eye",
                                title: loc.string(.privacyProfileVisibility),
                                subtitle: loc.string(.privacyProfileVisibilitySubtitle),
                                isOn: $profileVisibility
                            )
                            Divider().padding(.leading, 52)
                            ToggleRow(
                                icon: "circle.fill",
                                title: loc.string(.privacyOnlineStatus),
                                subtitle: loc.string(.privacyOnlineStatusSubtitle),
                                isOn: $onlineStatus
                            )
                            Divider().padding(.leading, 52)
                            ToggleRow(
                                icon: "checkmark.circle",
                                title: loc.string(.privacyReadReceipts),
                                subtitle: loc.string(.privacyReadReceiptsSubtitle),
                                isOn: $readReceipts
                            )
                        }

                        // Данные
                        settingsCard {
                            Button {
                                // TODO: очистка кэша
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundColor(.raveDanger)
                                        .frame(width: 30, height: 30)
                                        .background(Color.raveDanger.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loc.string(.privacyClearCache))
                                            .font(.subheadline)
                                            .foregroundColor(.raveTextPrimary)
                                        Text(loc.string(.privacyClearCacheSubtitle))
                                            .font(.caption2)
                                            .foregroundColor(.raveTextSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.raveTextSecondary.opacity(0.5))
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // Информация
                        settingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(loc.string(.privacyInfo))
                                    .font(.caption)
                                    .foregroundColor(.raveTextSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle(loc.string(.privacyTitle))
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

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.raveCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.raveSurface, lineWidth: 1)
            )
    }
}

// MARK: - Toggle Row
private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.ravePrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.ravePrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.raveTextPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.raveTextSecondary)
                }
            }
        }
        .tint(.ravePrimary)
        .padding(.vertical, 4)
    }
}
