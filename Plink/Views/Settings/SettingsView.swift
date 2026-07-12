// Plink/Views/Settings/SettingsView.swift — GPT-5.6 V4 §1
// V4 redesign: V4SecondaryScreen + SettingsSection/Row.
// No SettingsBackground, no bioluminescent, no old glass.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlinkThemeStore.self) private var themeStore
    let authService: AuthService

    var body: some View {
        V4SecondaryScreen(surface: .profile, title: "Настройки", dismiss: dismiss.callAsFunction) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Account
                    SettingsSection(title: "Аккаунт") {
                        SettingsRow(icon: "person.crop.circle", title: "Личные данные") { }
                        SettingsRow(icon: "lock.shield", title: "Приватность") { }
                        SettingsRow(icon: "person.crop.circle.badge.xmark", title: "Заблокированные") { }
                    }

                    // App
                    SettingsSection(title: "Приложение") {
                        SettingsRow(icon: "circle.lefthalf.filled", title: "Оформление", value: themeStore.appTheme.name) { dismiss() }
                        SettingsRow(icon: "bell", title: "Уведомления") { }
                        SettingsRow(icon: "play.rectangle", title: "Воспроизведение") { }
                        SettingsRow(icon: "globe", title: "Язык", value: "Русский") { }
                    }

                    // Plink+
                    SettingsSection(title: "Подписка") {
                        SettingsRow(icon: "crown.fill", title: "Plink+ статус", value: PremiumStatusManager.shared.isPremium ? "Активна" : "Нет") { }
                    }

                    // Support
                    SettingsSection(title: "Поддержка") {
                        SettingsRow(icon: "questionmark.circle", title: "Помощь") { }
                        SettingsRow(icon: "doc.text", title: "Условия использования") { }
                        SettingsRow(icon: "shield", title: "Политика конфиденциальности") { }
                    }

                    // Danger zone
                    SettingsSection(title: "Аккаунт") {
                        SettingsRow(icon: "trash", title: "Удалить аккаунт", role: .destructive) { }
                    }

                    Text("Plink v1.0")
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}
