import SwiftUI
import PhotosUI

// MARK: - Profile View v3 (Premium + Edit Profile)
/// Профиль: премиальный хедер, бейдж Premium, статистика, история.
/// Настройки — через шестерёнку.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onSignOut: () -> Void

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showPaywall = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var friendManager = FriendManager()
    @State private var isPremium = false

    init(viewModel: ProfileViewModel, onSignOut: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignOut = onSignOut
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    premiumBanner
                    activityBlock
                    statsRow
                    watchHistorySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clear, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(loc.string(.profileTitle))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            // Только шестерёнка — настройки (убран карандаш сверху слева)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.ravePrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadUser()
            isPremium = PremiumStatusManager.shared.isPremium
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onSignOut: {
                Task {
                    try? await viewModel.authService.signOut()
                    onSignOut()
                    dismiss()
                }
            }, onDeleteAccount: {
                Task {
                    await viewModel.deleteAccount()
                    onSignOut()
                    dismiss()
                }
            })
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                onPurchase: {
                    // 🔧 FIX C9: Premium activation goes through StoreManager.handleSuccessfulPurchase
                    // → activatePremium(expiryDate:). Direct setPremium() removed.
                    Task {
                        await StoreManager.shared.purchase()
                        isPremium = PremiumStatusManager.shared.isPremium
                        showPaywall = false
                    }
                },
                onRestore: {
                    // 🔧 FIX C9: Restore goes through StoreManager.restorePurchases
                    // which iterates Transaction.currentEntitlements (FIX M5).
                    Task {
                        await StoreManager.shared.restorePurchases()
                        isPremium = PremiumStatusManager.shared.isPremium
                        showPaywall = false
                    }
                },
                onDismiss: { showPaywall = false }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            newItem.loadTransferable(type: Data.self) { result in
                DispatchQueue.main.async {
                    if case .success(let data?) = result, let img = UIImage(data: data) {
                        viewModel.saveAvatar(img)
                    }
                }
            }
            selectedPhotoItem = nil
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            Button { showPhotoPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarView
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .if(isPremium) { view in
                            view.premiumStroke(lineWidth: 3.5)
                        }
                        .if(!isPremium) { view in
                            view.overlay(
                                Circle()
                                    .stroke(Color.raveGradient, lineWidth: 3)
                            )
                        }
                        .neonGlow(color: .ravePrimary, radius: 20, y: 8)

                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.ravePrimary))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                // Переливающийся никнейм для премиум (без короны)
                PremiumUsernameText(
                    text: viewModel.displayName,
                    isPremium: isPremium,
                    font: .title2.bold()
                )

                Text(viewModel.email)
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
            }

            // Кнопка редактировать — премиум градиент (остаётся под аватаркой)
            Button { showEditProfile = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Редактировать профиль")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.raveGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .ravePrimary.opacity(0.3), radius: 10, y: 4)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let image = viewModel.avatarImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let avatarURL = viewModel.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: avatarFallback
                }
            }
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color.ravePrimary, Color.raveAccent],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(viewModel.displayName.prefix(2).uppercased())
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Premium Banner (дорогой стиль — без дешёвого gold)

    @ViewBuilder
    private var premiumBanner: some View {
        if isPremium {
            // ── Статус подписки: «Plink Premium активен до: [дата]» ──
            let expiryDate = PremiumStatusManager.shared.subscriptionExpiry ?? Date().addingTimeInterval(30 * 86400)
            let formatter = DateFormatter()
            let _ = { formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "d MMMM yyyy" }()
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.bioCyan.opacity(0.2), Color.bioEmerald.opacity(0.15)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(.bioCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Plink Premium активен")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("Действует до \(formatter.string(from: expiryDate))")
                        .font(.caption)
                        .foregroundColor(.raveTextSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.bioEmerald)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 16, opacity: 0.06)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.bioCyan.opacity(0.2), lineWidth: 0.5)
            )
        } else {
            // Кнопка оформления подписки — стильная, не убогая
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color.ravePrimary.opacity(0.2), Color.raveAccent.opacity(0.15)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(.ravePrimary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Оформить Premium")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("Без рекламы · 4K · Дизайн · Бейдж")
                            .font(.caption)
                            .foregroundColor(.raveTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.ravePrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassCard(cornerRadius: 16, opacity: 0.06)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.ravePrimary.opacity(0.2), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activity Block (что смотрит сейчас + последние просмотры)

    private var activityBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.ravePrimary)
                Text("Активность")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
            }

            // Что сейчас смотрит (если есть активная комната)
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.raveGreen.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.raveGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Сейчас в комнате")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.raveTextPrimary)
                    Text("Смотрит с друзьями")
                        .font(.system(size: 13))
                        .foregroundColor(.raveTextSecondary)
                }
                Spacer()
                PulsingDot(color: .raveGreen).frame(width: 8, height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 14, opacity: 0.04)
        }
    }

    // MARK: - Stats (кликабельные)

    private var statsRow: some View {
        HStack(spacing: 0) {
            statBox(value: "\(viewModel.roomsJoined)", label: loc.string(.profileStatsRooms))
            Divider().frame(height: 40).background(Color.white.opacity(0.06))
            statBox(value: "\(viewModel.hoursWatched)", label: loc.string(.profileStatsHours))
            Divider().frame(height: 40).background(Color.white.opacity(0.06))
            statBox(value: "\(friendManager.friends.count)", label: loc.string(.profileStatsFriends))
        }
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 18, opacity: 0.04)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.raveTextPrimary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.raveTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Watch History (горизонтальная карусель постеров)

    private var watchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc.string(.profileHistory))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Spacer()
                if !viewModel.history.isEmpty {
                    Button(loc.string(.profileClear)) { viewModel.clearHistory() }
                        .font(.system(size: 13))
                        .foregroundColor(.raveDanger)
                }
            }

            if viewModel.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.raveTextTertiary)
                    Text(loc.string(.profileHistoryEmpty))
                        .font(.subheadline)
                        .foregroundColor(.raveTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .glassCard(cornerRadius: 16, opacity: 0.04)
            } else {
                // Горизонтальная карусель постеров
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.history) { item in
                            WatchHistoryPoster(item: item) { viewModel.rewatch(item) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.removeHistoryItem(item)
                                    } label: {
                                        Label(loc.string(.delete), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}

// MARK: - Premium Avatar Stroke (пульсирующая ледяной голубой + розовый)
/// Анимированная обводка аватарки для премиум-пользователей.
struct PremiumAvatarStroke: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        AngularGradient(
            colors: [
                Color.bioCyan,
                Color.raveAccent,
                Color(hex: 0x22D3EE),
                Color.raveAccent,
                Color.bioCyan,
            ],
            center: .center
        )
    }
}

// MARK: - Premium Animated Avatar Border
struct PremiumAvatarModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .trim(from: 0, to: CGFloat(rotation / 360.0))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.bioCyan,
                                Color.raveAccent,
                                Color(hex: 0x22D3EE),
                                Color.bioCyan,
                            ],
                            center: .center
                        ),
                        lineWidth: 3.5
                    )
                    .rotationEffect(.degrees(rotation))
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

extension View {
    func premiumAvatarBorder() -> some View {
        modifier(PremiumAvatarModifier())
    }
}

// MARK: - Premium Glow Card Modifier (стеклянное свечение на карточках комнат)
struct PremiumGlowCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .glassCard(cornerRadius: cornerRadius, opacity: 0.06)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.bioCyan.opacity(0.3), Color.raveAccent.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.bioCyan.opacity(0.15), radius: 12, y: 4)
    }
}

extension View {
    func premiumGlowCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PremiumGlowCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Edit Profile Sheet
/// Изменение имени пользователя.
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileViewModel
    @State private var newUsername = ""
    @State private var isSaving = false

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
        _newUsername = State(initialValue: viewModel.username)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(spacing: 24) {
                    // Аватарка
                    if let image = viewModel.avatarImage {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.raveGradient, lineWidth: 3))
                    } else {
                        ZStack {
                            Circle().fill(Color.raveGradient).frame(width: 100, height: 100)
                            Text(viewModel.displayName.prefix(2).uppercased())
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Имя пользователя")
                            .font(.subheadline.bold())
                            .foregroundColor(.raveTextPrimary)
                        TextField("Введите имя", text: $newUsername)
                            .textFieldStyle(RaveTextFieldStyle())
                    }

                    Spacer()

                    // Кнопка сохранить
                    Button {
                        Task {
                            isSaving = true
                            await viewModel.updateUsername(newUsername)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text("Сохранить")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .raveButtonStyle()
                    .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundColor(.raveTextSecondary)
                }
            }
        }
    }
}

// MARK: - Settings View (без друзей — теперь в TabBar)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onSignOut: () -> Void
    var onDeleteAccount: () -> Void

    @State private var showNotifications = false
    @State private var showPrivacy = false
    @State private var showLanguage = false
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Настройки
                        settingsSection("Настройки") {
                            settingsRow(icon: "bell.fill", title: loc.string(.profileNotifications), color: .raveWarning) { showNotifications = true }
                            settingsRow(icon: "shield.fill", title: loc.string(.profilePrivacy), color: .raveGreen) { showPrivacy = true }
                            settingsRow(icon: "globe", title: loc.string(.profileLanguage), color: .raveAccent) { showLanguage = true }
                        }

                        // Опасная зона
                        settingsSection("Опасная зона") {
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash").foregroundColor(.raveDanger)
                                    Text(loc.string(.profileDeleteAccount)).foregroundColor(.raveDanger)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.raveTextSecondary.opacity(0.5))
                                }
                            }
                        }

                        // Выход
                        Button(action: { dismiss(); onSignOut() }) {
                            HStack {
                                Image(systemName: "arrow.right.square.fill")
                                Text(loc.string(.profileSignOut))
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundColor(.raveWarning)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Настройки")
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
            .alert(loc.string(.profileDeleteConfirm), isPresented: $showDeleteAlert) {
                Button(loc.string(.cancel), role: .cancel) {}
                Button(loc.string(.delete), role: .destructive) {
                    dismiss()
                    onDeleteAccount()
                }
            } message: {
                Text(loc.string(.profileDeleteMessage))
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacySettingsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showLanguage) {
                LanguagePickerView().preferredColorScheme(.dark).presentationDetents([.medium])
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.raveTextSecondary)
                .padding(.leading, 4)
                .padding(.bottom, 8)
            content()
        }
    }

    private func settingsRow(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.raveTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary.opacity(0.5))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Watch History Poster (вертикальный постер для карусели)
/// Постер 120×170 с прогресс-баром просмотра и названием снизу.
struct WatchHistoryPoster: View {
    let item: WatchHistoryItem
    var onRewatch: () -> Void

    var body: some View {
        Button(action: onRewatch) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    // Постер
                    posterImage
                        .frame(width: 120, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )

                    // Прогресс-бар
                    if let progress = item.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.4)).frame(height: 3)
                                Rectangle().fill(Color.ravePrimary).frame(width: geo.size.width * progress, height: 3)
                            }
                        }
                        .frame(width: 120, height: 3)
                    }

                    // Иконка типа медиа
                    Image(systemName: mediaIcon)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
                .frame(width: 120, height: 170)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.raveTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var mediaIcon: String {
        switch item.mediaType {
        case "movie": return "film"
        case "series": return "tv"
        case "music": return "music.note"
        case "livestream": return "dot.radiowaves.left.and.right"
        default: return "video"
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    posterGradient
                }
            }
        } else {
            posterGradient
        }
    }

    private var posterGradient: some View {
        LinearGradient(
            colors: gradientPalette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.6))
        )
    }

    private var gradientPalette: [Color] {
        let palettes: [[Color]] = [
            [Color.ravePrimary.opacity(0.4), .black],
            [Color.raveAccent.opacity(0.4), .black],
            [Color.raveCyan.opacity(0.4), .black],
            [Color.raveWarning.opacity(0.4), .black],
        ]
        return palettes[abs(item.id.hashValue) % palettes.count]
    }
}

// MARK: - Watch History Card (старый — оставлен для совместимости)
struct WatchHistoryCard: View {
    let item: WatchHistoryItem
    var onRewatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                thumbnail
                    .frame(width: 100, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let progress = item.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 3)
                            Rectangle().fill(Color.ravePrimary).frame(width: geo.size.width * progress, height: 3)
                        }
                    }
                    .frame(width: 100, height: 3)
                }
            }
            .frame(width: 100, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                    .lineLimit(2)
                Text(item.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            Button(action: onRewatch) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.ravePrimary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.raveSurface)
                }
            }
        } else {
            Rectangle().fill(Color.raveSurface)
        }
    }
}
