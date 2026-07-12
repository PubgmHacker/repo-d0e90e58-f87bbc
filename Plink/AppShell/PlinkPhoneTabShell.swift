// Plink/AppShell/PlinkPhoneTabShell.swift — Netflix-style home
//
// 5 tabs. Home = hero banner (always) + live rooms + trending (always).
// One Create button only (bottom bar).

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createIntent: CreateRoomIntent?
    let dependencies: AppDependencies

    @State private var navigateToRoom: Room?
    @State private var homeViewModel: HomeViewModel?
    @State private var trendingVideos: [YouTubeVideoSummary] = []
    @State private var plinkPopular: [PlinkPopularItem] = []

    var body: some View {
        TabView(selection: $selection) {
            // Главная
            NavigationStack {
                homeView
                    .fullScreenCover(item: $navigateToRoom) { room in
                        watchRoom(for: room)
                    }
            }
            .tag(AppSection.home)
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.symbol) }

            // Комнаты
            NavigationStack {
                roomsView
                    .fullScreenCover(item: $navigateToRoom) { room in
                        watchRoom(for: room)
                    }
            }
            .tag(AppSection.rooms)
            .tabItem { Label(AppSection.rooms.title, systemImage: AppSection.rooms.symbol) }

            // ИИ
            AIAssistantView()
                .tag(AppSection.ai)
                .tabItem { Label(AppSection.ai.title, systemImage: AppSection.ai.symbol) }

            // Друзья
            FriendsView()
                .tag(AppSection.friends)
                .tabItem { Label(AppSection.friends.title, systemImage: AppSection.friends.symbol) }

            // Настройки
            SettingsView(authService: dependencies.authService)
                .tag(AppSection.settings)
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.symbol) }
        }
        .tint(Cinema2026.accent)
        .toolbarBackground(Cinema2026.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(dependencies.apiClient)
        // ONE persistent Create button — visible only on home + rooms tabs
        .overlay(alignment: .bottom) {
            if selection == .home || selection == .rooms {
                createButtonBar
            }
        }
    }

    // MARK: - Create button (shared)

    private var createButtonBar: some View {
        Button {
            createIntent = .chooseService
        } label: {
            Label("Создать комнату", systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.background)
                .frame(maxWidth: .infinity)
                .frame(height: CompactPhoneMetrics.primaryButtonHeight)
                .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
        .padding(.bottom, 72)  // sit above the tab bar
        .padding(.top, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Home (Netflix-style + GPT-5 Living Home)

    /// GPT-5 §8: artwork URL from hero (first trending video) for living backdrop.
    /// nil when no trending data → backdrop uses Cinema2026 fallback palette.
    private var heroArtworkURL: URL? {
        guard let hero = trendingVideos.first,
              let thumbString = hero.thumbnailURLString,
              let url = URL(string: thumbString) else {
            return nil
        }
        return url
    }

    private var homeView: some View {
        // GPT-5 §8: wrap Home content in PlinkLivingHome for artwork-driven
        // living backdrop. artworkURL comes from the hero (first trending video).
        // Backdrop uses existing PaletteLoader + LivingBackdropPalette (no duplication).
        PlinkLivingHome(artworkURL: heroArtworkURL) {
            ScrollView {
                LazyVStack(spacing: CompactPhoneMetrics.sectionSpacing) {
                    // Netflix-style hero banner — always visible from trending
                    if let hero = trendingVideos.first {
                        NetflixHeroBanner(video: hero) { draft in
                            createIntent = .selectedContent(draft)
                        }
                    } else {
                        // GPT-5 §8.6: loading state — stable skeleton over fallback backdrop.
                        LivingHomeStateOverlay(isLoading: true)
                            .frame(height: 220)
                    }

                    // AI CTA
                    CompactAIEntryCard {
                        selection = .ai
                    }
                    .padding(.top, 8)

                    // Live rooms (if any)
                    if let vm = homeViewModel, !vm.activeRooms.isEmpty {
                        CompactRoomRail(
                            title: "Сейчас смотрят",
                            rooms: vm.activeRooms,
                            style: .landscape,
                            open: { navigateToRoom = $0 }
                        )
                    }

                    // Trending — ALWAYS visible (YouTube only, honest label)
                    if !trendingVideos.isEmpty {
                        TrendingRail(
                            title: "Популярное на YouTube",
                            videos: trendingVideos,
                            onSelect: { video in
                                createIntent = .selectedContent(
                                    SelectedContentDraft(
                                        id: video.videoId,
                                        service: .youtube,
                                        contentURL: "https://www.youtube.com/watch?v=\(video.videoId)",
                                        title: video.title,
                                        thumbnailURL: video.thumbnailURLString
                                    )
                                )
                            }
                        )
                    }

                    // Brain Revision 3 Step 6: "Популярное в Plink" rail.
                    // First-party popularity from /api/discovery/popular.
                    // Hide the rail entirely if endpoint returns empty (do NOT fill with YouTube).
                    if !plinkPopular.isEmpty {
                        PlinkPopularRail(
                            title: "Популярное в Plink",
                            items: plinkPopular,
                            onSelect: { item in
                                // Only allow tap if directCreateRoomDraft is true (YouTube content).
                                guard item.directCreateRoomDraft else { return }
                                createIntent = .selectedContent(
                                    SelectedContentDraft(
                                        id: item.id,
                                        service: .youtube,
                                        contentURL: item.contentURL,
                                        title: item.title,
                                        thumbnailURL: item.thumbnailURL
                                    )
                                )
                            }
                        )
                    }

                    // Brain Revision 3 Step 6: removed shuffled() — was causing unstable UI.
                    // Deterministic order from backend ranking (already sorted by uniqueViewers desc).
                    // Show "Рекомендуем" only when we have 7+ trending items (top 6 in primary rail,
                    // items 7-12 in secondary rail — deterministic, not random).
                    if trendingVideos.count > 6 {
                        TrendingRail(
                            title: "Рекомендуем",
                            videos: Array(trendingVideos.prefix(12).suffix(6)),
                            onSelect: { video in
                                createIntent = .selectedContent(
                                    SelectedContentDraft(
                                        id: video.videoId,
                                        service: .youtube,
                                        contentURL: "https://www.youtube.com/watch?v=\(video.videoId)",
                                        title: video.title,
                                        thumbnailURL: video.thumbnailURLString
                                    )
                                )
                            }
                        )
                    }
                }
                .padding(.bottom, 140)  // leave room for the persistent create button
            }
            .scrollIndicators(.hidden)
            // GPT-5: background is now provided by PlinkLivingHome's LivingHomeCanvas.
            // Do NOT add .background(Cinema2026.background) here — it would cover the backdrop.
            .navigationTitle("")
            .task {
                if homeViewModel == nil {
                    homeViewModel = HomeViewModel(
                        roomService: dependencies.roomService,
                        authService: dependencies.authService
                    )
                    await homeViewModel?.loadRooms()
                }
                if trendingVideos.isEmpty {
                    await loadTrending()
                }
                if plinkPopular.isEmpty {
                    await loadPlinkPopular()
                }
            }
        }
    }

    // MARK: - Rooms

    private var roomsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Комнаты")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
            }
            .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
            .padding(.top, 14)

            if let vm = homeViewModel, !vm.activeRooms.isEmpty {
                List(vm.activeRooms) { room in
                    Button {
                        navigateToRoom = room
                    } label: {
                        CompactRoomListRow(room: room)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Cinema2026.divider)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Cinema2026.background)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Cinema2026.secondary)
                    Text("Нет активных комнат")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Text("Создайте первую комнату — кнопка внизу")
                        .font(.system(size: 13))
                        .foregroundStyle(Cinema2026.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Cinema2026.background)
        .task {
            if homeViewModel == nil {
                homeViewModel = HomeViewModel(
                    roomService: dependencies.roomService,
                    authService: dependencies.authService
                )
            }
            await homeViewModel?.loadRooms()
        }
    }

    // MARK: - Load trending

    private func loadTrending() async {
        let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app"
        guard let url = URL(string: "\(apiBaseURL)/api/media/trending?regionCode=RU&maxResults=20") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            trendingVideos = resp.results
        } catch {}
    }

    /// Brain Revision 3 Step 6: load first-party Popular in Plink from
    /// /api/discovery/popular. If endpoint fails or returns empty, the rail
    /// stays hidden (plinkPopular remains []).
    private func loadPlinkPopular() async {
        let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app"
        guard let url = URL(string: "\(apiBaseURL)/api/discovery/popular?window=24h&limit=20") else { return }
        do {
            var request = URLRequest(url: url)
            // Brain Revision 3: /api/discovery/popular may require auth —
            // attach Bearer token if available. If 401, rail stays hidden.
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let resp = try JSONDecoder().decode(PlinkPopularResponse.self, from: data)
            plinkPopular = resp.results
        } catch {
            // Silent failure — rail just stays hidden.
        }
    }

    // MARK: - Watch Room

    @ViewBuilder
    private func watchRoom(for room: Room) -> some View {
        WatchRoomCompositionRoot.makeScreenForRoom(
            room: room,
            userId: UserDefaults.standard.string(forKey: "plink_user_id") ?? "",
            username: UserDefaults.standard.string(forKey: "plink_username") ?? "",
            apiBaseURL: URL(string: "https://plink-backend-production-ef31.up.railway.app")!,
            wsBaseURL: URL(string: "wss://plink-backend-production-ef31.up.railway.app/ws")!,
            authToken: KeychainHelper.read(for: "rave_auth_token") ?? ""
        )
    }
}

// MARK: - Netflix-style hero banner

/// Brain Phase 4: no nested buttons. The entire banner is a single tappable
/// surface. The closure returns the SelectedContentDraft for the tapped video
/// so the caller can construct a `.selectedContent` intent.
struct NetflixHeroBanner: View {
    let video: YouTubeVideoSummary
    let onTap: (SelectedContentDraft) -> Void

    private var draft: SelectedContentDraft {
        SelectedContentDraft(
            id: video.videoId,
            service: .youtube,
            contentURL: "https://www.youtube.com/watch?v=\(video.videoId)",
            title: video.title,
            thumbnailURL: video.thumbnailURLString
        )
    }

    var body: some View {
        // Single Button — no nested Buttons (Brain Phase 4 rule).
        Button { onTap(draft) } label: {
            ZStack(alignment: .bottomLeading) {
                // Full-width backdrop
                AsyncImage(url: URL(string: video.thumbnailURLString ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(height: 280)
                .clipped()

                // Gradient fade
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Cinema2026.background.opacity(0.6), location: 0.7),
                        .init(color: Cinema2026.background, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content (no nested Buttons)
                VStack(alignment: .leading, spacing: 6) {
                    Text("● В ЭФИРЕ")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Cinema2026.danger)

                    Text(video.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    Text(video.channelTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Cinema2026.secondary)

                    // Single CTA label (not a button) — entire banner is tappable.
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Смотреть вместе")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Cinema2026.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Cinema2026.text, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .frame(height: 280)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact room list row

struct CompactRoomListRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: room.mediaItem?.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Cinema2026.danger, in: Capsule())
                        .padding(5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(1)
                Text(room.mediaItem?.title ?? "Без видео")
                    .font(.system(size: 12))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)
                Text("\(room.participantCount) участников")
                    .font(.system(size: 10))
                    .foregroundStyle(Cinema2026.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Cinema2026.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Plink Popular (first-party discovery)

/// Brain Revision 3 Step 6: first-party popularity item from /api/discovery/popular.
struct PlinkPopularItem: Decodable, Identifiable, Sendable, Hashable {
    let contentURL: String
    let title: String
    let thumbnailURL: String?
    let uniqueViewers: Int
    let uniqueRooms: Int
    let recentStarts: Int
    let directCreateRoomDraft: Bool

    /// Synthesize a stable id from contentURL.
    var id: String { contentURL }
}

struct PlinkPopularResponse: Decodable, Sendable {
    let results: [PlinkPopularItem]
}

/// Brain Revision 3 Step 6: rail for "Популярное в Plink" — first-party
/// popularity from public room activity. Hidden when empty (do NOT fill
/// with YouTube — keep the all-service label honest).
struct PlinkPopularRail: View {
    let title: String
    let items: [PlinkPopularItem]
    let onSelect: (PlinkPopularItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Cinema2026.amber)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
            }
            .padding(.horizontal, CompactPhoneMetrics.horizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            PlinkPopularCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.directCreateRoomDraft)
                    }
                }
                .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
                .padding(.bottom, 4)
            }
        }
    }
}

struct PlinkPopularCard: View {
    let item: PlinkPopularItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: item.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: CompactPhoneMetrics.landscapeCardWidth, height: CompactPhoneMetrics.landscapeCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: CompactPhoneMetrics.landscapeRadius))

                // Viewer count badge
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(item.uniqueViewers)")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.75), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
            }

            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)
                .frame(width: CompactPhoneMetrics.landscapeCardWidth, alignment: .leading)

            Text("\(item.uniqueRooms) комнат · \(item.recentStarts) новых")
                .font(.system(size: 10))
                .foregroundStyle(Cinema2026.secondary)
                .lineLimit(1)
                .frame(width: CompactPhoneMetrics.landscapeCardWidth, alignment: .leading)
        }
    }
}
