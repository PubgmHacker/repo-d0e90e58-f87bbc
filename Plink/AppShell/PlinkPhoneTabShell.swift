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

    // MARK: - Home (Netflix-style)

    private var homeView: some View {
        ScrollView {
            LazyVStack(spacing: CompactPhoneMetrics.sectionSpacing) {
                // Netflix-style hero banner — always visible from trending
                if let hero = trendingVideos.first {
                    NetflixHeroBanner(video: hero) { draft in
                        createIntent = .selectedContent(draft)
                    }
                } else {
                    // Loading state
                    Rectangle()
                        .fill(Cinema2026.surface)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .overlay {
                            ProgressView().tint(Cinema2026.accent)
                        }
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

                // Trending — ALWAYS visible (all services label)
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

                // Secondary trending (different items)
                if trendingVideos.count > 6 {
                    TrendingRail(
                        title: "Рекомендуем",
                        videos: Array(trendingVideos.shuffled().prefix(10)),
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
        .background(Cinema2026.background)
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
