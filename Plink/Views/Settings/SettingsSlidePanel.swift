import SwiftUI

// MARK: - Settings Bottom Sheet (чистая шторка снизу)
//
// Премиальная шторка настроек, выезжающая снизу.
// • Переход: .move(edge: .bottom) — без просветов, плотно к краям
// • Анимация: spring(response: 0.35, dampingFraction: 0.8)
// • Затемнённый оверлей закрывается по тапу
// • Матское стекло (ultraThin) + неоновая обводка сверху
struct SettingsSlidePanel: View {
    @Binding var isPresented: Bool

    @State private var profileVM: ProfileViewModel?
    @State private var showFullProfile = false
    @State private var showPrivacy = false
    @State private var showNotifications = false
    @State private var showPremium = false
    @State private var showAdminPanel = false
    @State private var isPremium = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Затемнённый оверлей (закрывается по тапу) ──
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { closePanel() }

            // ── Шторка снизу ──
            VStack(spacing: 0) {
                // Grabber (ручка)
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                panelContent
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 520)
            .background(
                ZStack {
                    Color.raveBackground.opacity(0.95)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                // Неоновая обводка только сверху
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        LinearGradient(
                            colors: [Color.bioCyan.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.15)
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.bioCyan.opacity(0.15), radius: 20, y: -2)
            .shadow(color: .black.opacity(0.6), radius: 30, y: -4)
        }
        .ignoresSafeArea(.keyboard)
        .task {
            if profileVM == nil {
                let api = APIClient()
                let vm = ProfileViewModel(authService: AuthService(api: api))
                await vm.loadUser()
                profileVM = vm
                isPremium = PremiumStatusManager.shared.isPremium
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let profileVM {
                NavigationStack {
                    ProfileView(viewModel: profileVM, onSignOut: { closePanel() })
                }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySettingsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPremium) {
            PremiumManagementView(isPremium: $isPremium)
        }
        .sheet(isPresented: $showAdminPanel) {
            AdminPanelView()
        }
    }

    // MARK: - Panel Content (компактный список)

    private var panelContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Шапка: аватар + имя (компактно) ──
                accountHeader
                    .padding(.top, 16)
                    .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06))

            // ── Меню ──
            VStack(spacing: 0) {
                compactRow(icon: "person.crop.circle.fill", title: "Аккаунт", color: .ravePrimary) {
                    showFullProfile = true
                }
                compactRow(icon: "lock.shield.fill", title: "Конфиденциальность", color: .raveGreen) {
                    showPrivacy = true
                }
                compactRow(icon: "bell.badge.fill", title: "Уведомления", color: .raveWarning) {
                    showNotifications = true
                }
                compactRow(icon: "sparkles", title: "Premium Подписка", color: .raveAccent) {
                    showPremium = true
                }

                // Админ-панель (только для ADMIN)
                if profileVM?.user?.isAdmin == true {
                    compactRow(icon: "shield.lefthalf.filled", title: "Админ-панель", color: .raveWarning) {
                        showAdminPanel = true
                    }
                }
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.06))

            // ── Разработчик (компактно) ──
            developerRow
                .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.06))

            // ── Выйти ──
            Button {
                closePanel()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.square.fill")
                        .font(.system(size: 16))
                    Text("Выйти")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.raveDanger)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Account Header (компактный)

    @ViewBuilder
    private var accountHeader: some View {
        Button {
            showFullProfile = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.premiumGradient)
                        .frame(width: 44, height: 44)
                    Text((profileVM?.displayName ?? "?").prefix(2).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .if(isPremium) { view in
                    view.premiumStroke(lineWidth: 2)
                }
                .if(!isPremium) { view in
                    view.overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    PremiumUsernameText(
                        text: profileVM?.displayName ?? "Гость",
                        isPremium: isPremium,
                        font: .system(size: 15, weight: .bold)
                    )
                    Text("@\((profileVM?.username ?? "guest").lowercased())")
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Row

    private func compactRow(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.raveTextPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Developer Row (компактный)

    private var developerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Разработчик")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.raveTextSecondary)
                .padding(.horizontal, 18)

            HStack(spacing: 0) {
                devLink(icon: "paperplane.fill", color: .ravePrimary, url: "https://t.me/raveclone")
                devLink(icon: "play.rectangle.fill", color: .raveDanger, url: "https://youtube.com/@raveclone")
                devLink(icon: "music.note.tv", color: .raveTextPrimary, url: "https://tiktok.com/@raveclone")
                devLink(icon: "globe", color: .raveCyan, url: "https://raveclone.com")
            }
            .padding(.horizontal, 10)
        }
    }

    private func devLink(icon: String, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Close

    private func closePanel() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            isPresented = false
        }
    }
}

// MARK: - Premium Animated Stroke (пульсирующая пурпурно-чёрная обводка)
/// Вращающийся AngularGradient — обводка пульсирует.
struct PremiumAnimatedStroke: ShapeStyle {
    @State private var rotation: Double = 0

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        AngularGradient(
            colors: [
                Color.bioCyan,
                Color.bioObsidian,
                Color.bioEmerald,
                Color.bioObsidian,
                Color.bioCyan,
            ],
            center: .center
        )
    }
}

// MARK: - Premium Username Text (переливающийся пурпурно-чёрный градиент)
/// Градиентный текст без короны. Анимация shimmer — перелив 3.5 сек.
/// Добавляет приписку [Premium] после ника.
struct PremiumUsernameText: View {
    let text: String
    let isPremium: Bool
    var font: Font = .system(size: 18, weight: .bold)

    var body: some View {
        if isPremium {
            HStack(spacing: 4) {
                Text(text)
                    .font(font)
                    .shimmerGradientText(colors: premiumColors)
                Text("[Premium]")
                    .font(font)
                    .shimmerGradientText(colors: premiumColors)
            }
        } else {
            Text(text)
                .font(font)
                .foregroundColor(.raveTextPrimary)
        }
    }

    private let premiumColors: [Color] = [
        Color.bioCyan,
        Color.bioEmerald,
        Color.bioTeal,
        Color.bioCyan,
    ]
}

// MARK: - Premium Management View (экран управления подпиской)
struct PremiumManagementView: View {
    @Binding var isPremium: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(orbColors: [Color(hex: 0x9B59B6), Color(hex: 0xF1C40F), Color(hex: 0x6EC1E4)])

                ScrollView {
                    VStack(spacing: 24) {
                        // Статус подписки
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color(hex: 0x6EC1E4), Color(hex: 0x9B59B6), Color(hex: 0xF1C40F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )

                            if isPremium {
                                Text("Premium активна")
                                    .font(.title2.bold())
                                    .foregroundColor(.raveTextPrimary)
                                Text("Действует до 2 августа 2026")
                                    .font(.subheadline)
                                    .foregroundColor(.raveTextSecondary)
                            } else {
                                Text("Premium не активна")
                                    .font(.title2.bold())
                                    .foregroundColor(.raveTextPrimary)
                                Text("Оформите подписку для расширенных возможностей")
                                    .font(.subheadline)
                                    .foregroundColor(.raveTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 20, opacity: 0.04)

                        if isPremium {
                            // Управление подпиской
                            Button {
                                // TODO: открыть управление подпиской в App Store
                            } label: {
                                HStack {
                                    Image(systemName: "creditcard.fill")
                                    Text("Управление подпиской")
                                    Spacer()
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.ravePrimary)
                                .padding(16)
                                .glassCard(cornerRadius: 16, opacity: 0.06)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                PremiumStatusManager.shared.setPremium(false)
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    isPremium = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Отменить подписку")
                                    Spacer()
                                }
                                .font(.subheadline)
                                .foregroundColor(.raveDanger)
                                .padding(16)
                                .glassCard(cornerRadius: 16, opacity: 0.04)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                PremiumStatusManager.shared.setPremium(true)
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    isPremium = true
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Оформить подписку")
                                        .font(.headline.bold())
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 16)
                                .background(Color.premiumGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Premium")
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
        .preferredColorScheme(.dark)
    }
}
