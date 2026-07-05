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
        .tint(.ravePrimary)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - Rooms Tab (Общедоступные + Мои комнаты)

struct RoomsTabContent: View {
    @EnvironmentObject private var apiClient: APIClient
    @ObservedObject private var inviteService = RoomInviteService.shared
    @State private var viewModel: HomeViewModel?
    @State private var navigateToRoom: Room?
    @State private var selectedSubTab: RoomSubTab = .discover

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
                BioluminescentBackground(energy: 0.35, dimming: 0)
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
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $navigateToRoom) { room in
                RoomView(room: room)
                    .toolbar(.hidden, for: .tabBar)
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
            } else {
                Task { await viewModel?.loadMyRooms() }
            }
        }
    }

    // MARK: - Sub-Tab Bar

    private var subTabBar: some View {
        HStack(spacing: 0) {
            ForEach(RoomSubTab.allCases) { tab in
                subTabButton(tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // 🔧 Red badge on Requests tab
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
            .foregroundColor(isActive ? .white : .raveTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                isActive
                    ? AnyShapeStyle(Color.raveGradient)
                    : AnyShapeStyle(Color.clear)
            )
            .clipShape(Capsule())
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
                    emptyState(icon: "globe.americas.fill", text: "Нет активных комнат")
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
                        Button { navigateToRoom = room } label: {
                            myRoomCard(room)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    emptyState(icon: "rectangle.stack.badge.plus", text: "Создайте комнату с главной")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Join Content (embedded JoinRoomView)

    private var joinContent: some View {
        ScrollView(showsIndicators: false) {
            JoinRoomView { room in
                navigateToRoom = room
            }
            .frame(minHeight: 500)
            .padding(.top, 8)
        }
    }

    // MARK: - Requests Content (Room invites)

    private var requestsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if inviteService.pendingInvites.isEmpty {
                    emptyState(icon: "envelope.open", text: "Нет запросов на присоединение")
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

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.raveTextTertiary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassCard(cornerRadius: 16, opacity: 0.04)
    }

    // MARK: - My Room Card

    @ViewBuilder
    private func myRoomCard(_ room: Room) -> some View {
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
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(room.code)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.bioCyan)
                Text("код")
                    .font(.system(size: 8))
                    .foregroundColor(.raveTextTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.raveTextTertiary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
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
                RoomView(room: room)
                    .toolbar(.hidden, for: .tabBar)
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
        SettingsView(authService: authService)
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
                AnimatedGradientBackground()

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
