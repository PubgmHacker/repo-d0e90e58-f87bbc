import SwiftUI

// MARK: - Privacy Settings View (Premium)
/// 🔧 REDESIGNED: Full-screen settings window with premium toggle design.
/// Was: bottom sheet with default iOS Toggle and visible Divider gaps.
/// Now: full-screen NavigationStack with custom PlinkToggle, grouped cards
/// without internal dividers, real UserDefaults persistence.
///
/// Design inspired by Telegram Privacy + iOS Settings.
struct PrivacySettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    // Persisted state (UserDefaults-backed)
    @AppStorage("privacy_profile_visible") private var profileVisibility = true
    @AppStorage("privacy_online_status") private var onlineStatus = true
    @AppStorage("privacy_read_receipts") private var readReceipts = true
    @AppStorage("privacy_show_in_search") private var showInSearch = true
    @AppStorage("privacy_allow_dm_from") private var allowDMFrom = "everyone" // everyone / friends / nobody
    @AppStorage("privacy_allow_invites_from") private var allowInvitesFrom = "everyone"

    var body: some View {
        ZStack {
            BioluminescentBackground(energy: 0.4, dimming: 0)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                        // ── Visibility Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Видимость")

                            PlinkSettingsCard {
                                PlinkToggleRow(
                                    icon: "eye.fill",
                                    title: loc.string(.privacyProfileVisibility),
                                    subtitle: loc.string(.privacyProfileVisibilitySubtitle),
                                    iconColor: .bioCyan,
                                    isOn: $profileVisibility
                                )
                                PlinkToggleRow(
                                    icon: "circle.fill",
                                    title: loc.string(.privacyOnlineStatus),
                                    subtitle: loc.string(.privacyOnlineStatusSubtitle),
                                    iconColor: .bioEmerald,
                                    isOn: $onlineStatus
                                )
                                PlinkToggleRow(
                                    icon: "magnifyingglass",
                                    title: "Показывать в поиске",
                                    subtitle: "Другие пользователи могут найти вас по имени",
                                    iconColor: .bioTeal,
                                    isOn: $showInSearch
                                )
                            }
                        }

                        // ── Messages & Invites Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Сообщения и приглашения")

                            PlinkSettingsCard {
                                PlinkToggleRow(
                                    icon: "checkmark.circle.fill",
                                    title: loc.string(.privacyReadReceipts),
                                    subtitle: loc.string(.privacyReadReceiptsSubtitle),
                                    iconColor: .bioCyan,
                                    isOn: $readReceipts
                                )
                                privacyPickerRow(
                                    icon: "envelope.fill",
                                    title: "Кто может писать ЛС",
                                    subtitle: "Получать личные сообщения от",
                                    value: $allowDMFrom,
                                    options: [("everyone", "Все"), ("friends", "Только друзья"), ("nobody", "Никто")]
                                )
                                privacyPickerRow(
                                    icon: "rectangle.stack.fill.badge.plus",
                                    title: "Кто может звать в комнаты",
                                    subtitle: "Приглашения в совместный просмотр",
                                    value: $allowInvitesFrom,
                                    options: [("everyone", "Все"), ("friends", "Только друзья"), ("nobody", "Никто")]
                                )
                            }
                        }

                        // ── Data Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Данные")

                            PlinkSettingsCard {
                                Button {
                                    clearCache()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(Color.raveDanger.opacity(0.18))
                                            .clipShape(RoundedRectangle(cornerRadius: 7))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(loc.string(.privacyClearCache))
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.raveTextPrimary)
                                            Text(loc.string(.privacyClearCacheSubtitle))
                                                .font(.system(size: 12))
                                                .foregroundColor(.raveTextSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.raveTextTertiary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // ── Info Footer ──
                        Text(loc.string(.privacyInfo))
                            .font(.system(size: 11))
                            .foregroundColor(.raveTextTertiary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Конфиденциальность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Privacy Picker Row (inline picker styled like iOS Settings)

    @ViewBuilder
    private func privacyPickerRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button {
                    value.wrappedValue = option.0
                } label: {
                    if value.wrappedValue == option.0 {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.bioTeal.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.raveTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                Text(options.first(where: { $0.0 == value.wrappedValue })?.1 ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(.bioCyan)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func clearCache() {
        HapticManager.impact(.medium)
        // Clear URLCache + image caches
        URLCache.shared.removeAllCachedResponses()
        // Clear temp directory
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir)
    }
}
