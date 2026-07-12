// Plink/AppShell/ProfileScreen.swift — GPT-5.6 SOL §8.8
//
// Profile root containing Settings.
// Avatar, display name, Plink+ status; grouped rows for Account, Privacy,
// Notifications, Playback, Appearance, Help. Settings lives here.

import SwiftUI

struct ProfileScreen: View {
    let authService: AuthService
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Profile header
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Cinema2026.surface)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Cinema2026.secondary)
                            )

                        Text(authService.currentUser?.username ?? "Пользователь")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Cinema2026.text)

                        if PremiumStatusManager.shared.isPremium {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11))
                                Text("Plink+")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Cinema2026.amber)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Cinema2026.amber.opacity(0.15), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    // Quick actions
                    VStack(spacing: 0) {
                        ProfileRow(icon: "gearshape.fill", title: "Настройки", action: { showSettings = true })
                        ProfileDivider()
                        ProfileRow(icon: "crown.fill", title: "Plink+ подписка", tint: Cinema2026.amber, action: {})
                        ProfileDivider()
                        ProfileRow(icon: "person.2.fill", title: "Друзья", action: {})
                        ProfileDivider()
                        ProfileRow(icon: "rectangle.stack.fill", title: "Мои комнаты", action: {})
                    }
                    .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    // Account & Privacy
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Аккаунт и приватность")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Cinema2026.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ProfileRow(icon: "lock.fill", title: "Конфиденциальность", action: {})
                            ProfileDivider()
                            ProfileRow(icon: "hand.raised.fill", title: "Заблокированные", action: {})
                            ProfileDivider()
                            ProfileRow(icon: "trash.fill", title: "Удалить аккаунт", tint: Cinema2026.danger, action: {})
                        }
                        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }

                    // Help
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Помощь")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Cinema2026.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ProfileRow(icon: "questionmark.circle.fill", title: "Поддержка", action: {})
                            ProfileDivider()
                            ProfileRow(icon: "doc.text.fill", title: "Условия использования", action: {})
                            ProfileDivider()
                            ProfileRow(icon: "shield.fill", title: "Политика конфиденциальности", action: {})
                        }
                        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }

                    // Sign out
                    Button {
                        NotificationCenter.default.post(name: .plinkSignedOut, object: nil)
                    } label: {
                        Text("Выйти из аккаунта")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Cinema2026.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)

                    Text("Plink v1.0")
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 104)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) {
            SettingsView(authService: authService)
        }
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let icon: String
    let title: String
    var tint: Color = Cinema2026.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Rectangle()
            .fill(Cinema2026.divider.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}
