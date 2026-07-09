import SwiftUI

// MARK: - Main Tab Bar (5 вкладок) — ИИ-помощник по центру
/// Нижняя навигация: Главная, Комнаты, ИИ ✨, Друзья, Настройки.
/// «Настройки» открывает полноэкранный SettingsView (как Apple ID Settings).
struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @EnvironmentObject private var apiClient: APIClient
    let authService: AuthService
    @StateObject private var inviteService = RoomInviteService.shared

    enum Tab: Hashable {
        case home, rooms, ai, friends, settings
    }

    init(authService: AuthService) {
        self.authService = authService
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabContent(
                onProfileTap: { selectedTab = .settings },
                onSwitchToAITab: {
                    HapticManager.impact(.light)
                    withAnimation { selectedTab = .ai }
                },
                onSwitchToJoinTab: {
                    HapticManager.impact(.light)
                    UserDefaults.standard.set(true, forKey: "plink_switch_to_join")
                    selectedTab = .rooms
                }
            )
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
                .tag(Tab.home)

            RoomsTabContent()
                .tabItem {
                    Label("Комнаты", systemImage: "rectangle.stack.fill")
                }
                .badge(inviteService.inviteCount > 0 ? inviteService.inviteCount : 0)
                .tag(Tab.rooms)

            AIAssistantView()
                .tabItem {
                    Label("ИИ", systemImage: "sparkles")
                }
                .tag(Tab.ai)

            FriendsTabContent()
                .tabItem {
                    Label("Друзья", systemImage: "person.2.fill")
                }
                .tag(Tab.friends)

            // 🔧 Pack v3: Settings — отдельная вкладка таббара, не модалка
            SettingsTabContent(authService: authService)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        // 🔧 FIX: .tint(.white) делал ВСЕ вкладки белыми (активные и неактивные).
        // .tint применяется только к ВЫБРАННОЙ вкладке по умолчанию в iOS 17+,
        // но .white слишком яркий — неактивные тоже кажутся белыми из-за .fill иконок.
        // Используем bioCyan — только активная вкладка подсвечивается, неактивные серые.
        .tint(.bioCyan)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        // 🔧 Pack v3: Свайп влево/вправо для переключения вкладок
        // Только горизонтальные свайпы (|width| > |height| * 2), минимум 100px
        .gesture(
            DragGesture(minimumDistance: 100)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                    let tabs: [Tab] = [.home, .rooms, .ai, .friends, .settings]
                    guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
                    if value.translation.width < -100 && currentIndex < tabs.count - 1 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tabs[currentIndex + 1]
                        }
                    }
                    if value.translation.width > 100 && currentIndex > 0 {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tabs[currentIndex - 1]
                        }
                    }
                }
        )
    }
}

// MARK: - Rooms Tab (Общедоступные + Мои комнаты)

struct RoomsTabContent: View {
    @EnvironmentObject private var apiClient: APIClient
    @ObservedObject private var inviteService = RoomInviteService.shared
    @State private var viewModel: HomeViewModel?
    @State private var navigateToRoom: Room?
    @State private var selectedSubTab: RoomSubTab = .discover

    /// 🔧 NEW: Room pending deletion — shows confirmation alert, then calls viewModel.deleteRoom
    @State private var roomToDelete: Room?
    @State private var isDeleting = false
    @State private var deleteError: String?

    /// 🔧 NEW: Internal tabs within the Rooms tab
    enum RoomSubTab: String, CaseIterable, Identifiable {
        case discover = "Общие"
        case mine = "Мои"
        case join = "Войти"
        case requests = "Запросы"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .discover: return "🍿"
            case .mine: return "🎬"
            case .join: return "🔓"
            case .requests: return "🔔"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 🔧 ROOMS: тёплая crimson палитра (отличается от Home ocean)
                BioluminescentBackground(energy: 0.7, dimming: 0, palette: .crimson)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Sub-tab segmented control ──
                    subTabBar

                    // ── Content ──
                    switch selectedSubTab {
                    case .discover:
                        discoverContent
                    case .mine:
                        myRoomsContent
                    case .join:
                        joinContent
                    case .requests:
                        requestsContent
                    }
                }
            }
            .navigationTitle("Комнаты")
            .navigationBarTitleDisplayMode(.inline)
            // 🔧 FIX v2 (July 2026): replaced `navigationDestination(item:)` with
            // `.fullScreenCover(item:)`. The old code opened RoomView INSIDE the
            // NavigationStack of the Комнаты tab — which meant iOS edge-swipe
            // gestures (used by NavigationStack for "swipe to go back") could
            // pop RoomView, returning to the tab and re-showing the tabbar.
            // In landscape, a horizontal swipe was misinterpreted as edge-swipe,
            // causing 'swipe left → tabbar → orientation reset → room closes'.
            //
            // fullScreenCover lifts RoomView OUT of the NavigationStack into a
            // modal context where:
            //   1. There is no "swipe to go back" gesture at all
            //   2. The underlying TabView + tabbar are fully covered
            //   3. .interactiveDismissDisabled(true) on RoomView blocks swipe-down
            //      dismissal too
            // Combined with the AppDelegate orientation lock (see
            // PlinkAppDelegate), this completely isolates RoomView from system
            // gestures.
            .fullScreenCover(item: $navigateToRoom) { room in
                RoomView(room: room)
            }
        }
        .refreshable {
            await viewModel?.loadRooms()
            await viewModel?.loadMyRooms()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    roomService: RoomService(api: apiClient),
                    authService: AuthService(api: apiClient)
                )
                Task {
                    await viewModel?.loadRooms()
                    await viewModel?.loadMyRooms()
                }
            }
            // 🔧 Pack v3: Если нажали "Присоединиться" на главной — переключить на "Войти"
            if UserDefaults.standard.bool(forKey: "plink_switch_to_join") {
                UserDefaults.standard.set(false, forKey: "plink_switch_to_join")
                withAnimation { selectedSubTab = .join }
            }
        }
        // 🔧 NEW: Confirmation alert before deleting a room
        .alert("Удалить комнату?", isPresented: Binding(
            get: { roomToDelete != nil },
            set: { if !$0 { roomToDelete = nil; deleteError = nil } }
        )) {
            Button("Отмена", role: .cancel) { roomToDelete = nil }
            Button("Удалить", role: .destructive) {
                guard let room = roomToDelete else { return }
                Task {
                    isDeleting = true
                    do {
                        try await viewModel?.deleteRoom(room)
                        roomToDelete = nil
                    } catch {
                        deleteError = error.localizedDescription
                    }
                    isDeleting = false
                }
            }
        } message: {
            if let room = roomToDelete {
                Text("Комната «\(room.name)» (код \(room.code)) будет удалена без возможности восстановления. Все участники и история чата удалятся.")
            } else if let deleteError {
                Text("Ошибка: \(deleteError)")
            }
        }
    }

    // MARK: - Sub-Tab Bar
    //
    // 🔧 TELEGRAM-STYLE: прозрачный glass container с металлик-обводкой.
    // Убран cyan/emerald gradient border — теперь чёрная metallic.
    private var subTabBar: some View {
        HStack(spacing: 8) {
            ForEach(RoomSubTab.allCases) { tab in
                subTabButton(tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .telegramGlass(cornerRadius: 22, borderColor: .black.opacity(0.4))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func subTabButton(_ tab: RoomSubTab) -> some View {
        let isActive = selectedSubTab == tab
        let showBadge = tab == .requests && inviteService.inviteCount > 0

        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSubTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Text(tab.icon)
                    .font(.system(size: 13))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if showBadge {
                    Text("\(inviteService.inviteCount)")
                        .font(.system(size: 9, weight: .heavy).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.raveDanger)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isActive ? .raveTextPrimary : .raveTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            // 🔧 TELEGRAM-GLASS: убран cyan gradient + glow. Теперь прозрачное
            // стекло с металлик-обводкой для ВСЕХ состояний (active/inactive).
            // Active отличается только белым текстом (был white-on-cyan).
            .telegramGlass(
                cornerRadius: 14,
                borderColor: isActive ? .black.opacity(0.6) : .black.opacity(0.4)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Discover Content (5 рандомных открытых комнат)

    /// 🔧 Shows 5 RANDOM public rooms (not top, not sorted — random each time)
    private var discoverContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                let publicRooms = (viewModel?.filteredRooms ?? [])
                    .filter({ room in room.isActive && room.privacy == .publicRoom })
                if !publicRooms.isEmpty {
                    ForEach(Array(publicRooms.shuffled().prefix(5))) { room in
                        Button { navigateToRoom = room } label: {
                            RoomCardView(room: room, onReport: nil, onBlock: nil)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    emptyState(icon: "globe.americas.fill", text: "Нет активных комнат",
                               subtitle: "Создайте новую комнату с главной страницы")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - My Rooms Content

    private var myRoomsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let myRooms = viewModel?.myRooms, !myRooms.isEmpty {
                    ForEach(myRooms) { room in
                        // 🔧 REDESIGNED: was a Button wrapping the card → that swallowed
                        // all taps including the delete button. Now: card with explicit
                        // tap gesture for navigation + a separate delete icon button on
                        // the right that doesn't conflict.
                        myRoomCard(room)
                    }
                } else {
                    emptyState(icon: "rectangle.stack.badge.plus", text: "Создайте комнату с главной",
                               subtitle: "Здесь появятся комнаты, которые вы создали или посетили")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 🔧 FIX: Refresh my-rooms every time this subtab appears. Was only loaded
        // ONCE on first Rooms tab open (gated by `if viewModel == nil`). After the
        // user created a new room on Home and switched to Mine, they saw stale data.
        // Now: every appearance of Mine subtab triggers loadMyRooms. Cheap network
        // call, ensures orphan rooms (hostID=user.id, no RoomParticipant row) always
        // appear so the user can delete them.
        .task {
            await viewModel?.loadMyRooms()
        }
    }

    // MARK: - Join Content (embedded JoinRoomView)
    //
    // 🔧 FIX: was wrapping JoinRoomView in another ScrollView + .frame(minHeight: 500).
    // JoinRoomView already has its own internal ScrollView → double-scroll caused
    // content to overflow horizontally and the bottom join button to clip off-screen.
    // Now: embed JoinRoomView directly with proper padding. It manages its own layout.
    private var joinContent: some View {
        JoinRoomView { room in
            navigateToRoom = room
        }
        .padding(.top, 8)
    }

    // MARK: - Requests Content (Room invites)

    private var requestsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if inviteService.pendingInvites.isEmpty {
                    emptyState(icon: "envelope.open", text: "Нет запросов на присоединение",
                               subtitle: "Приглашайте друзей и получайте запросы на вход сюда")
                } else {
                    ForEach(inviteService.pendingInvites) { invite in
                        inviteCard(invite)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Invite Card

    @ViewBuilder
    private func inviteCard(_ invite: RoomInvite) -> some View {
        VStack(spacing: 0) {
            // ── Top: Inviter avatar + nick + invite text ──
            HStack(spacing: 12) {
                // Inviter avatar
                ZStack {
                    Circle()
                        .fill(Color.bioCyan.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(invite.fromUsername.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.bioCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Nick + invite text
                    HStack(spacing: 4) {
                        Text(invite.fromUsername)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.raveTextPrimary)
                        Text("приглашает посмотреть")
                            .font(.system(size: 12))
                            .foregroundColor(.raveTextSecondary)
                    }

                    // 🔧 What they're watching — media title in quotes
                    if let mediaTitle = invite.mediaTitle, !mediaTitle.isEmpty {
                        Text("«\(mediaTitle)»")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.bioCyan)
                            .lineLimit(1)
                    } else {
                        Text("«\(invite.roomName)»")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.bioCyan)
                            .lineLimit(1)
                    }

                    // Service name
                    if let service = invite.service {
                        Text(service.brandName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.raveTextTertiary)
                    }
                }

                Spacer()

                // 🔧 Service logo (small, right side)
                if let service = invite.service {
                    ServiceLogoView(service: service, size: 28)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // ── Room code (small, subtle) ──
            HStack {
                Image(systemName: "number")
                    .font(.system(size: 9))
                Text(invite.roomCode)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.raveTextTertiary)
                Spacer()
                Text(invite.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.raveTextTertiary)
            }
            .padding(.top, 8)

            // ── Accept / Decline buttons ──
            HStack(spacing: 12) {
                Button {
                    HapticManager.impact(.light)
                    inviteService.declineInvite(invite)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Отклонить")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.raveDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.raveDanger.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.raveDanger.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.impact(.medium)
                    Task {
                        if let room = await inviteService.acceptInvite(invite) {
                            navigateToRoom = room
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Принять")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.raveGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [Color.bioCyan.opacity(0.15), Color.white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Empty State

    /// 🔧 PREMIUM empty state — was bare icon + text. Now: glass card with
    /// gradient ring around icon + title + subtitle for better UX guidance.
    private func emptyState(icon: String, text: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 12) {
            // 🔧 PREMIUM: icon in gradient ring instead of bare SF Symbol
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bioCyan.opacity(0.15),
                                Color.bioEmerald.opacity(0.08),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.bioCyan.opacity(0.3),
                                Color.bioEmerald.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.bioCyan)
            }
            .shadow(color: Color.bioCyan.opacity(0.2), radius: 8, y: 2)

            VStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.raveTextSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.raveTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.bioObsidian.opacity(0.3))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.bioCyan.opacity(0.2),
                            Color.bioEmerald.opacity(0.08),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: - My Room Card
    //
    // 🔧 REDESIGNED per user request:
    // 1. Separate trash icon button on the right (was: long-press context menu —
    //    user said "не нужно зажимать её").
    // 2. Card itself is tappable for navigation (via .onTapGesture on the card,
    //    NOT via Button wrapper — Button swallows all taps including the trash).
    // 3. chevron.right removed — redundant with tap affordance.
    @ViewBuilder
    private func myRoomCard(_ room: Room) -> some View {
        HStack(spacing: 12) {
            // ── Card body (tap → open room) ──
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.bioCyan.opacity(0.12))
                        .frame(width: 44, height: 44)
                    if let source = room.mediaItem?.source, source != .url {
                        ServiceLogoView(service: source, size: 24)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.bioCyan)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.raveTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // 🔧 Participant badge (glass)
                        ParticipantBadge(count: room.participantCount)

                        Text("· \(room.hostName)")
                            .font(.system(size: 12))
                            .foregroundColor(.raveTextTertiary)
                            .lineLimit(1)

                        if room.isActive {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color.bioEmerald)
                                    .frame(width: 5, height: 5)
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .heavy))
                            }
                            .foregroundColor(.bioEmerald)
                        } else {
                            // 🔧 NEW: indicate ended rooms (history view)
                            Text("завершена")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.raveTextTertiary)
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(room.code)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.bioCyan)
                    Text("код")
                        .font(.system(size: 8))
                        .foregroundColor(.raveTextTertiary)
                }
            }
            .contentShape(Rectangle())  // весь HStack — tappable
            .onTapGesture {
                HapticManager.impact(.light)
                navigateToRoom = room
            }

            // ── Delete button (separate, doesn't trigger navigation) ──
            Button {
                HapticManager.impact(.medium)
                roomToDelete = room
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.raveDanger)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.raveDanger.opacity(0.1))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.raveDanger.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    room.isActive
                        ? Color.white.opacity(0.06)
                        : Color.white.opacity(0.03),  // ended rooms — dimmer border
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Tab Contents Contents

/// Главная — экран Discover
struct HomeTabContent: View {
    @State private var navigateToRoom: Room?
    @State private var viewModel: HomeViewModel?
    @EnvironmentObject private var apiClient: APIClient
    var onProfileTap: () -> Void
    /// 🔧 NEW: Closure to switch to the AI tab from Home's AI CTA card.
    var onSwitchToAITab: (() -> Void)?
    var onSwitchToJoinTab: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                BioluminescentBackground(energy: 0.45, dimming: 0)
                    .ignoresSafeArea()

                if let viewModel {
                    HomeView(
                        viewModel: viewModel,
                        onProfileTap: onProfileTap,
                        onSwitchToAITab: onSwitchToAITab,
                        onSwitchToJoinTab: onSwitchToJoinTab
                    )
                } else {
                    ProgressView()
                        .tint(.ravePrimary)
                }
            }
            .navigationDestination(item: $navigateToRoom) { room in
                // 🔧 FIX v2 (July 2026): Home tab also uses `.fullScreenCover` to
                // present RoomView (see the .fullScreenCover attached just below
                // this NavigationStack). We keep an EmptyView placeholder here
                // so the `navigationDestination(item:)` type-checks — without
                // it, SwiftUI would warn about an unhandled navigation item.
                EmptyView()
            }
            // 🔧 FIX v2: present RoomView modally. See the matching comment in
            // RoomsTabContent for the full rationale.
            .fullScreenCover(item: $navigateToRoom) { room in
                RoomView(room: room)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    roomService: RoomService(api: apiClient),
                    authService: AuthService(api: apiClient)
                )
            }
        }
    }
}

/// Друзья — список друзей с поиском и кнопкой чата
// MARK: - Settings Tab Content (отдельная вкладка, не модалка)
struct SettingsTabContent: View {
    let authService: AuthService

    var body: some View {
        // 🔧 SETTINGS: grayscale gradient background (B&W, no orbs)
        ZStack {
            SettingsBackground(energy: 0.7)
                .ignoresSafeArea()
            SettingsView(authService: authService)
        }
    }
}

// MARK: - Friends Tab Content
struct FriendsTabContent: View {
    @State private var searchText = ""
    @EnvironmentObject private var friendManager: FriendManager
    @State private var selectedFriendForProfile: Friend?
    @State private var selectedFriendForChat: Friend?
    @State private var showAddFriend = false
    @State private var showRequests = false
    @State private var friendToDelete: Friend?

    private var filteredFriends: [Friend] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return friendManager.friends
        }
        return friendManager.friends.filter {
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 🔧 FRIENDS: зелёная emerald палитра — социальное тепло
                BioluminescentBackground(energy: 0.7, dimming: 0, palette: .emerald)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    friendsHeader

                    if friendManager.friends.isEmpty {
                        emptyState
                    } else {
                        searchAndList
                    }
                }
            }
            .navigationTitle("Друзья")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 🔧 Pack v3: Toolbar пустой — кнопки перенесены в friendsHeader
            }
            .navigationDestination(item: $selectedFriendForProfile) { friend in
                FriendProfileView(friend: friend) {
                    selectedFriendForChat = friend
                }
            }
            .navigationDestination(item: $selectedFriendForChat) { friend in
                DMChatView(friend: friend)
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet(friendManager: friendManager)
            }
            .sheet(isPresented: $showRequests) {
                FriendRequestsSheet(friendManager: friendManager)
            }
        }
    }

    // MARK: - Header
    private var friendsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Друзья")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.raveTextPrimary)
                Text("\(friendManager.friends.count) друзей")
                    .font(.subheadline)
                    .foregroundColor(.raveTextSecondary)
            }
            Spacer()
            // 🔧 Pack v3: Кнопки добавления и запросов — В заголовке, не в toolbar
            HStack(spacing: 12) {
                Button { showRequests = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.bioAmber)
                        if !friendManager.incomingRequests.isEmpty {
                            Text("\(friendManager.incomingRequests.count)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.raveDanger)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                }
                Button { showAddFriend = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18))
                        .foregroundColor(.bioCyan)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 56))
                .foregroundColor(.ravePrimary.opacity(0.5))

            Text("Друзей пока нет")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.raveTextPrimary)

            Text("Добавьте друзей, чтобы смотреть вместе")
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.center)

            Button { showAddFriend = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                    Text("Добавить друга")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.raveGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PremiumButtonStyle())
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Search + List
    private var searchAndList: some View {
        VStack(spacing: 0) {
            // Поиск
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.raveTextSecondary)
                TextField("Поиск друзей", text: $searchText)
                    .foregroundColor(.raveTextPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.raveTextSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 14, opacity: 0.05)
            .padding(.horizontal, 20)
            .padding(.top, 4)

            // Список
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredFriends) { friend in
                        FriendRowCard(
                            friend: friend,
                            onProfileTap: { selectedFriendForProfile = friend },
                            onChatTap: { selectedFriendForChat = friend },
                            onDelete: { friendToDelete = friend }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .confirmationDialog(
            "Удалить \(friendToDelete?.username ?? "") из друзей?",
            isPresented: Binding(get: { friendToDelete != nil }, set: { if !$0 { friendToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let friend = friendToDelete {
                    Task { await friendManager.removeFriend(friend) }
                }
                friendToDelete = nil
            }
            Button("Отмена", role: .cancel) { friendToDelete = nil }
        }
    }
}

// MARK: - Friend Row Card v3 (ice blue, 44pt avatar, swipe delete)
private struct FriendRowCard: View {
    let friend: Friend
    var onProfileTap: () -> Void
    var onChatTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Аватарка 44pt → профиль
            Button(action: onProfileTap) {
                if let urlStr = friend.avatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            avatarFallback
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        if friend.isOnline {
                            Circle()
                                .fill(Color.raveGreen)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Color.raveBackground, lineWidth: 2))
                        }
                    }
                } else {
                    avatarFallback
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            if friend.isOnline {
                                Circle()
                                    .fill(Color.raveGreen)
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().stroke(Color.raveBackground, lineWidth: 2))
                            }
                        }
                }
            }
            .buttonStyle(.plain)

            // Имя + username + статус → профиль
            Button(action: onProfileTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.username)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.raveTextPrimary)
                    Text("@\(friend.username.lowercased())")
                        .font(.system(size: 13))
                        .foregroundColor(.raveTextSecondary)
                    Text(friend.isOnline ? "В сети" : "Был(а) недавно")
                        .font(.system(size: 12))
                        .foregroundColor(friend.isOnline ? .raveGreen : .raveTextTertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Кнопка чата — ледяной голубой на прозрачной подложке
            Button(action: onChatTap) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.ravePrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.ravePrimary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(cornerRadius: 16, opacity: 0.04)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить из друзей", systemImage: "trash")
            }
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.ravePrimary, .raveAccent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(friend.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Add Friend Sheet (поиск по username)
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var friendManager: FriendManager
    @State private var searchQuery = ""
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(spacing: 16) {
                    // Поле поиска
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.ravePrimary)
                        TextField("Введите @username", text: $searchQuery)
                            .foregroundColor(.raveTextPrimary)
                            .autocapitalization(.none)
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await friendManager.searchUsers(query: searchQuery)
                                    hasSearched = true
                                }
                            }
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.raveTextSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 14, opacity: 0.05)
                    .padding(.horizontal, 20)

                    // Результаты
                    if friendManager.isLoading {
                        ProgressView().tint(.ravePrimary)
                    } else if hasSearched && friendManager.searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 44))
                                .foregroundColor(.raveTextTertiary)
                            Text("Ничего не найдено")
                                .font(.subheadline)
                                .foregroundColor(.raveTextSecondary)
                        }
                        .padding(.top, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(friendManager.searchResults) { user in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color.ravePrimary.opacity(0.2))
                                            Text(user.username.prefix(1).uppercased())
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.ravePrimary)
                                        }
                                        .frame(width: 44, height: 44)

                                        Text("@\(user.username)")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.raveTextPrimary)
                                        Spacer()

                                        Button {
                                            Task { await friendManager.sendRequest(to: user.id, username: user.username) }
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "person.badge.plus")
                                                Text("Добавить")
                                            }
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.raveGradient)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(12)
                                    .glassCard(cornerRadius: 14, opacity: 0.04)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Добавить друга")
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

// MARK: - Friend Requests Sheet
struct FriendRequestsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var friendManager: FriendManager

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                if friendManager.incomingRequests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 44))
                            .foregroundColor(.raveTextTertiary)
                        Text("Нет запросов")
                            .font(.subheadline)
                            .foregroundColor(.raveTextSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(friendManager.incomingRequests) { request in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.raveAccent.opacity(0.2))
                                        Text(request.fromUser.username.prefix(1).uppercased())
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.raveAccent)
                                    }
                                    .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.fromUser.username)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.raveTextPrimary)
                                        Text("Хочет дружить")
                                            .font(.system(size: 13))
                                            .foregroundColor(.raveTextSecondary)
                                    }
                                    Spacer()

                                    // Принять
                                    Button {
                                        Task { await friendManager.acceptRequest(request) }
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Color.raveGreen)
                                            .clipShape(Circle())
                                    }
                                    // Отклонить
                                    Button {
                                        Task { await friendManager.declineRequest(request) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Color.raveDanger)
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(14)
                                .glassCard(cornerRadius: 16, opacity: 0.04)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Запросы")
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
