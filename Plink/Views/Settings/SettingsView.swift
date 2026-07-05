import SwiftUI

// MARK: - Settings View (полноэкранный, в стиле Apple ID)
//
// 🔧 REPLACES SettingsSlidePanel — пользователь просил сделать вместо
// выдвигаемой панели полноценное окно, взяв за основу интерфейс Apple ID
// (раздел Settings → профиль Apple Account).
//
// Особенности Apple ID-стиля:
//   • Большая карточка профиля сверху (аватар, имя, «Аккаунт Плинк»)
//   • Grouped sections с rounded cards (16pt corner radius)
//   • Тонкие разделители (0.5px)
//   • Иконки в квадратных скруглённых боксах (как у iOS Settings)
//   • Chevron справа у каждой row
//
// Адаптация под Plink:
//   • Биолюминесцентный фон (BioluminescentBackground)
//   • Cyan/teal акценты вместо system blue
//   • Стекло (ultraThinMaterial) для карточек
//   • Glow на premium-элементах

struct SettingsView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var apiClient: APIClient
    /// 🔧 AuthService is not ObservableObject — pass via init instead of EnvironmentObject.
    /// RaveCloneApp injects it directly when constructing SettingsView.
    let authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var profileVM: ProfileViewModel?
    @State private var showFullProfile = false
    @State private var showPremium = false
    @State private var showAdminPanel = false
    @State private var isPremium = false
    @State private var user: User?
    // 🔧 Navigation destinations for full-screen push (was: .sheet which opened
    // as overlay). Now uses NavigationLink for proper full-screen push transitions.
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Биолюминесцентный фон
                BioluminescentBackground(energy: 0.45, dimming: 0)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // ── Profile Card (как Apple ID) ──
                        profileCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // ── Account Section ──
                        settingsSection("Аккаунт") {
                            settingsRow(
                                icon: "person.crop.circle.fill",
                                title: "Профиль",
                                subtitle: profileVM?.displayName,
                                color: .bioCyan
                            ) {
                                showFullProfile = true
                            }
                            settingsRow(
                                icon: "sparkles",
                                title: "Оформить Плинк+",
                                subtitle: premiumSubtitle,
                                color: .bioAmber
                            ) {
                                showPremium = true
                            }
                        }

                        // ── Privacy & Notifications Section ──
                        settingsSection("Конфиденциальность") {
                            // 🔧 Pack v3: Button + navigationPath вместо NavigationLink
                            // NavigationLink с .buttonStyle(.plain) плохо регистрировал тапы
                            Button {
                                navigationPath.append(SettingsDestination.privacy)
                            } label: {
                                rowContent(
                                    icon: "lock.shield.fill",
                                    title: "Конфиденциальность",
                                    subtitle: nil,
                                    color: .bioCoral,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                navigationPath.append(SettingsDestination.notifications)
                            } label: {
                                rowContent(
                                    icon: "bell.badge.fill",
                                    title: "Уведомления",
                                    subtitle: nil,
                                    color: .bioAmber,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                navigationPath.append(SettingsDestination.language)
                            } label: {
                                rowContent(
                                    icon: "globe",
                                    title: "Язык приложения",
                                    subtitle: LocalizationManager.shared.currentLanguageName,
                                    color: .bioRose,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // ── Admin Section (только для админов) ──
                        if profileVM?.user?.isAdmin == true {
                            settingsSection("Администрирование") {
                                settingsRow(
                                    icon: "shield.lefthalf.filled",
                                    title: "Админ-панель",
                                    color: .raveDanger
                                ) {
                                    showAdminPanel = true
                                }
                            }
                        }

                        // ── Developer Section ──
                        settingsSection("Разработчик") {
                            Link(destination: URL(string: "https://t.me/raveclone")!) {
                                settingsRowLink(
                                    icon: "paperplane.fill",
                                    title: "Telegram",
                                    color: .bioCyan
                                )
                            }
                            Link(destination: URL(string: "https://raveclone.com")!) {
                                settingsRowLink(
                                    icon: "globe",
                                    title: "Сайт",
                                    color: .bioTeal
                                )
                            }
                        }

                        // ── Sign Out ──
                        Button(role: .destructive) {
                            signOut()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right.square.fill")
                                    .font(.system(size: 17))
                                Text("Выйти из аккаунта")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                            }
                            .foregroundColor(.raveDanger)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.raveDanger.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        // ── Footer (версия) ──
                        VStack(spacing: 4) {
                            Text("Плинк")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.raveTextSecondary)
                            Text("Версия 1.0 (1)")
                                .font(.system(size: 11))
                                .foregroundColor(.raveTextTertiary)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        closeSettings()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.raveTextSecondary)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            // 🔧 FIX: Full-screen push navigation for sub-screens (was: .sheet overlay)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .privacy:
                    PrivacySettingsView()
                case .notifications:
                    NotificationsView()
                case .language:
                    LanguagePickerView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if profileVM == nil {
                let vm = ProfileViewModel(authService: authService)
                await vm.loadUser()
                profileVM = vm
                user = vm.user
                isPremium = PremiumStatusManager.shared.isPremium
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let profileVM {
                NavigationStack {
                    ProfileView(viewModel: profileVM, onSignOut: { closeSettings() })
                }
            }
        }
        .sheet(isPresented: $showPremium) {
            PremiumManagementView(isPremium: $isPremium)
        }
        .sheet(isPresented: $showAdminPanel) {
            AdminPanelView()
        }
    }

    /// 🔧 NEW: Shows premium subscription status with expiry date
    private var premiumSubtitle: String? {
        if isPremium {
            if let expiry = PremiumStatusManager.shared.subscriptionExpiry {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.locale = Locale(identifier: "ru_RU")
                return "Активен до \(formatter.string(from: expiry))"
            }
            return "Активна"
        }
        return "Не активна"
    }

    // MARK: - Profile Card (Apple ID style)

    private var profileCard: some View {
        Button {
            showFullProfile = true
        } label: {
            HStack(spacing: 16) {
                // 🔧 Pack v2: переиспользуемый AvatarView с Premium/Admin кольцами
                // Синхронизация с профилем — тот же компонент
                AvatarView(
                    imageURL: profileVM?.user?.avatarURL,
                    username: profileVM?.displayName ?? "?",
                    size: 64,
                    isPremium: isPremium,
                    isAdmin: profileVM?.user?.isAdmin ?? false
                )

                // Имя + подпись
                VStack(alignment: .leading, spacing: 4) {
                    PremiumUsernameText(
                        text: profileVM?.displayName ?? "Гость",
                        isPremium: isPremium,
                        font: .system(size: 19, weight: .bold)
                    )
                    Text("Аккаунт Плинк")
                        .font(.system(size: 13))
                        .foregroundColor(.raveTextSecondary)
                    if let email = profileVM?.user?.email {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.raveTextTertiary)
                            .lineLimit(1)
                    }
                    // 🔧 NEW: Short user ID for friend search
                    if let user = profileVM?.user {
                        HStack(spacing: 4) {
                            Text("ID:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.raveTextTertiary)
                            Text(user.shortId)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.raveTextSecondary)
                            Button {
                                UIPasteboard.general.string = user.fullId
                                HapticManager.impact(.light)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundColor(.raveTextTertiary)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.bioCyan.opacity(0.3),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings Section (grouped card)

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.raveTextSecondary)
                .tracking(0.5)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Settings Row (with chevron)

    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(icon: icon, title: title, subtitle: subtitle, color: color, showChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLink(
        icon: String,
        title: String,
        color: Color
    ) -> some View {
        rowContent(icon: icon, title: title, subtitle: nil, color: color, showChevron: false)
    }

    @ViewBuilder
    private func rowContent(
        icon: String,
        title: String,
        subtitle: String?,
        color: Color,
        showChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            // Иконка в скруглённом боксе (как у iOS Settings)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.raveTextPrimary)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.raveTextTertiary)
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.raveTextTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Sign Out

    private func signOut() {
        Task {
            try? await authService.signOut()
            await MainActor.run {
                closeSettings()
            }
        }
    }

    // MARK: - Close

    private func closeSettings() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

// MARK: - Localization Helper
extension LocalizationManager {
    var currentLanguageName: String {
        switch currentLanguage {
        case .russian: return "Русский"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

// MARK: - Settings Navigation Destinations
/// 🔧 FIX: Type-safe navigation destinations for full-screen push transitions.
enum SettingsDestination: Hashable {
    case privacy
    case notifications
    case language
}
