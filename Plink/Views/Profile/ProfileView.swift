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
    @State private var showCoverPicker = false  // 🔧 NEW: cover photo picker
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?  // 🔧 NEW: cover photo selection
    @State private var friendManager: FriendManager? = nil
    @State private var isPremium = false

    init(viewModel: ProfileViewModel, onSignOut: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignOut = onSignOut
    }

    var body: some View {
        ZStack {
            // 🔧 PROFILE: own ocean palette (cyan/emerald/amber — distinct from tabs)
            // was: AnimatedGradientBackground() — теперь BioluminescentBackground
            // для консистентности с другими вкладками + лучшая видимость орбов.
            BioluminescentBackground(energy: 0.75, dimming: 0, palette: .ocean)
                .ignoresSafeArea()

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
            // 🔧 Pack v3: убрана шестерёнка — настройки в таббаре
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadUser()
            isPremium = PremiumStatusManager.shared.isPremium
        }
        // 🔧 Pack v3: Перезагружаем после EditProfileSheet (ник + аватар)
        .onChange(of: showEditProfile) { _, isShown in
            if !isShown {
                Task {
                    await viewModel.loadUser()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let concreteAuth = viewModel.authService as? AuthService {
                SettingsView(authService: concreteAuth)
            }
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
        // 🔧 NEW: Cover photo picker (separate from avatar)
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            newItem.loadTransferable(type: Data.self) { result in
                DispatchQueue.main.async {
                    if case .success(let data?) = result, let img = UIImage(data: data) {
                        viewModel.saveCover(img)
                    }
                }
            }
            selectedCoverItem = nil
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            // ─── COVER (VK-style, lower height) ───
            // 🔧 VK-STYLE: 150pt (was 180) — VK uses ~140-160pt cover.
            // Lower = avatar sits closer to top, more elegant.
            ZStack(alignment: .bottomTrailing) {
                if let coverImage = viewModel.coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [
                            Color.bioCyan.opacity(0.6),
                            Color.bioEmerald.opacity(0.5),
                            Color.bioTeal.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 150)
                    .overlay(
                        RadialGradient(
                            colors: [Color.white.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                }

                LinearGradient(
                    colors: [.clear, Color.bioObsidian.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .frame(maxHeight: .infinity, alignment: .bottom)

                Button {
                    showCoverPicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                            .frame(width: 36, height: 36)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .frame(height: 150)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // ─── AVATAR (overlapping cover, VK-style) ───
            // 🔧 VK-STYLE: 100pt avatar + 6px ring = 112pt total (was 120+12=132)
            // Smaller avatar = more elegant, matches VK proportions.
            ZStack {
                Circle()
                    .fill(Color.bioObsidian)
                    .frame(width: 112, height: 112)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    .frame(width: 112, height: 112)

                Button { showPhotoPicker = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(
                            image: viewModel.avatarImage,
                            imageURL: viewModel.avatarURL,
                            username: viewModel.displayName,
                            size: 100,
                            isPremium: isPremium,
                            isAdmin: viewModel.user?.isAdmin ?? false
                        )

                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.ravePrimary))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            .offset(y: -50)  // 🔧 VK-style: avatar overlaps cover (was -60)
            .padding(.bottom, -40)  // compensate (was -50)

            // ─── NAME + EMAIL ───
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    PremiumUsernameText(
                        text: viewModel.displayName,
                        isPremium: isPremium,
                        isAdmin: viewModel.user?.isAdmin ?? false,
                        font: .title2.bold()
                    )
                    if viewModel.user?.isAdmin == true {
                        AdminBadgeChip()
                    }
                }

                Text(viewModel.email)
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
                    .textStroke(opacity: 0.4)  // 🔧 subtle outline for readability
            }
            .padding(.top, 8)

            // ─── EDIT BUTTON ───
            Button { showEditProfile = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Редактировать профиль")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // 🔧 TELEGRAM-GLASS: убран cyan raveGradient + glow.
                .telegramGlass(cornerRadius: 14, borderColor: .black.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
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
                    Text("Плинк+ активен")
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
            statBox(value: "\(friendManager?.friends.count ?? 0)", label: loc.string(.profileStatsFriends))
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
    @State private var isPremium = false
    @State private var showAvatarPicker = false
    @State private var showCoverPicker = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
        _newUsername = State(initialValue: viewModel.username)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 🔧 EDIT PROFILE: own ocean palette (cyan/emerald — premium feel)
                BioluminescentBackground(energy: 0.7, dimming: 0, palette: .ocean)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // ─── COVER (VK-style, same as ProfileView but smaller) ───
                        ZStack(alignment: .bottomTrailing) {
                            if let coverImage = viewModel.coverImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 140)
                                    .clipped()
                            } else {
                                LinearGradient(
                                    colors: [
                                        Color.bioCyan.opacity(0.6),
                                        Color.bioEmerald.opacity(0.5),
                                        Color.bioTeal.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 140)
                                .overlay(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.15), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 160
                                    )
                                )
                            }

                            LinearGradient(
                                colors: [.clear, Color.bioObsidian.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 45)
                            .frame(maxHeight: .infinity, alignment: .bottom)

                            Button {
                                showCoverPicker = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                        .frame(height: 140)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // ─── AVATAR (overlapping cover) ───
                        ZStack {
                            Circle()
                                .fill(Color.bioObsidian)
                                .frame(width: 108, height: 108)
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                .frame(width: 108, height: 108)

                            Button { showAvatarPicker = true } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(
                                        image: viewModel.avatarImage,
                                        imageURL: viewModel.avatarURL,
                                        username: viewModel.displayName,
                                        size: 96,
                                        isPremium: isPremium,
                                        isAdmin: viewModel.user?.isAdmin ?? false
                                    )

                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.ravePrimary))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .offset(y: -45)
                        .padding(.bottom, -35)

                        // ─── USERNAME FIELD ───
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.bioCyan)
                                Text("Имя пользователя")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.raveTextPrimary)
                                    // 🔧 TEXT STROKE: subtle black outline for readability
                                    .shadow(color: .black.opacity(0.5), radius: 0.4, x: 0.4, y: 0)
                                    .shadow(color: .black.opacity(0.5), radius: 0.4, x: -0.4, y: 0)
                                    .shadow(color: .black.opacity(0.5), radius: 0.4, x: 0, y: 0.4)
                                    .shadow(color: .black.opacity(0.5), radius: 0.4, x: 0, y: -0.4)
                                if viewModel.user?.isAdmin == true {
                                    AdminBadgeChip(compact: true)
                                }
                            }
                            TextField("Введите имя", text: $newUsername)
                                .textFieldStyle(RaveTextFieldStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.bioCyan.opacity(0.35),
                                                    Color.bioEmerald.opacity(0.15)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                        .padding(.horizontal, 4)

                        Spacer(minLength: 20)

                        // ─── SAVE BUTTON ───
                        Button {
                            Task {
                                isSaving = true
                                await viewModel.updateUsername(newUsername)
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                Text(isSaving ? "Сохранение…" : "Сохранить")
                                    .font(.headline.bold())
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            // 🔧 TELEGRAM-GLASS: убран cyan→emerald gradient + glow.
                            // Now neutral glass with metallic border.
                            .telegramGlass(cornerRadius: 14, borderColor: .black.opacity(0.5))
                        }
                        .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .opacity(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSaving ? 0.5 : 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundColor(.bioCyan)
                }
            }
            .task {
                isPremium = PremiumStatusManager.shared.isPremium
            }
            .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
            .onChange(of: selectedAvatarItem) { _, newItem in
                guard let newItem else { return }
                newItem.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        if case .success(let data?) = result, let img = UIImage(data: data) {
                            viewModel.saveAvatar(img)
                        }
                    }
                }
                selectedAvatarItem = nil
            }
            .photosPicker(isPresented: $showCoverPicker, selection: $selectedCoverItem, matching: .images)
            .onChange(of: selectedCoverItem) { _, newItem in
                guard let newItem else { return }
                newItem.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        if case .success(let data?) = result, let img = UIImage(data: data) {
                            viewModel.saveCover(img)
                        }
                    }
                }
                selectedCoverItem = nil
            }
        }
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
