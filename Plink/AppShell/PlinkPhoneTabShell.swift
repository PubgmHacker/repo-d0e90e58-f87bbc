// Plink/AppShell/PlinkPhoneTabShell.swift — GPT-5.6 V4 Rescue §3-4
//
// Custom V4TabBar replaces standard .tabItem.
// V4Surface wraps each tab with PlinkLivingBackground.
// One create presentation owner, one WatchRoom presentation.

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createIntent: CreateRoomIntent?
    let dependencies: AppDependencies
    @Environment(PlinkThemeStore.self) private var themeStore

    @State private var navigateToRoom: Room?
    @State private var homeViewModel: HomeViewModel?
    @State private var trendingVideos: [YouTubeVideoSummary] = []
    @State private var plinkPopular: [PlinkPopularItem] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            V4TabBar(selection: $selection)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .background(Cinema2026.void.ignoresSafeArea())
        // GPT-5.6 §1: Create is persistent action on Home/Rooms
        .overlay(alignment: .bottom) {
            if selection == .home || selection == .rooms {
                createButtonBar
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .home:
            V4Surface(theme: themeStore.appTheme, surface: .home) {
                homeView
            }
        case .rooms:
            V4Surface(theme: themeStore.appTheme, surface: .rooms) {
                DiscoverScreen(dependencies: dependencies, navigateToRoom: $navigateToRoom)
            }
        case .ai:
            V4Surface(theme: themeStore.appTheme, surface: .ai) {
                AIAssistantView()
            }
        case .friends:
            V4Surface(theme: themeStore.appTheme, surface: .friends) {
                FriendsScreen(dependencies: dependencies)
            }
        case .profile:
            V4Surface(theme: themeStore.appTheme, surface: .profile) {
                ProfileScreen(authService: dependencies.authService)
            }
        }
    }

    // MARK: - Create button
    private var createButtonBar: some View {
        Button {
            createIntent = .chooseService
        } label: {
            Label("Создать комнату", systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 72)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Home view (existing data + actions)
    private var heroArtworkURL: URL? {
        guard let hero = trendingVideos.first,
              let thumbString = hero.thumbnailURLString,
              let url = URL(string: thumbString) else { return nil }
        return url
    }

    private var homeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                heroSection
                sectionGap(24)
                liveRoomsSection
                sectionGap(32)
                trendingSection
                sectionGap(32)
                plinkPopularSection
                sectionGap(32)
                recommendedSection
                sectionGap(32)
                contextualAISection
            }
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .task {
            if homeViewModel == nil {
                homeViewModel = HomeViewModel(
                    roomService: dependencies.roomService,
                    authService: dependencies.authService
                )
                await homeViewModel?.loadRooms()
            }
            if trendingVideos.isEmpty { await loadTrending() }
            if plinkPopular.isEmpty { await loadPlinkPopular() }
        }
        .fullScreenCover(item: $navigateToRoom) { room in
            watchRoom(for: room)
        }
    }

    private func sectionGap(_ h: CGFloat) -> some View { Color.clear.frame(height: h) }

    @ViewBuilder private var heroSection: some View {
        if let hero = trendingVideos.first {
            NetflixHeroBanner(video: hero) { draft in createIntent = .selectedContent(draft) }
        } else {
            LivingHomeStateOverlay(isLoading: true).frame(height: 220)
        }
    }

    @ViewBuilder private var liveRoomsSection: some View {
        if let vm = homeViewModel, !vm.activeRooms.isEmpty {
            CompactRoomRail(title: "Сейчас смотрят", rooms: vm.activeRooms, style: .landscape, open: { navigateToRoom = $0 })
        }
    }

    @ViewBuilder private var trendingSection: some View {
        if !trendingVideos.isEmpty {
            TrendingRail(title: "Популярное на YouTube", videos: trendingVideos, onSelect: { video in
                createIntent = .selectedContent(SelectedContentDraft(id: video.videoId, service: .youtube, contentURL: "https://www.youtube.com/watch?v=\(video.videoId)", title: video.title, thumbnailURL: video.thumbnailURLString))
            })
        }
    }

    @ViewBuilder private var plinkPopularSection: some View {
        if !plinkPopular.isEmpty {
            PlinkPopularRail(title: "Популярное в Plink", items: plinkPopular, onSelect: { item in
                guard item.directCreateRoomDraft else { return }
                createIntent = .selectedContent(SelectedContentDraft(id: item.id, service: .youtube, contentURL: item.contentURL, title: item.title, thumbnailURL: item.thumbnailURL))
            })
        }
    }

    @ViewBuilder private var recommendedSection: some View {
        if trendingVideos.count > 6 {
            TrendingRail(title: "Рекомендуем", videos: Array(trendingVideos.prefix(12).suffix(6)), onSelect: { video in
                createIntent = .selectedContent(SelectedContentDraft(id: video.videoId, service: .youtube, contentURL: "https://www.youtube.com/watch?v=\(video.videoId)", title: video.title, thumbnailURL: video.thumbnailURLString))
            })
        }
    }

    @ViewBuilder private var contextualAISection: some View {
        CompactAIEntryCard { }
    }

    private func loadTrending() async {
        let api = "https://plink-backend-production-ef31.up.railway.app"
        guard let url = URL(string: "\(api)/api/media/trending?regionCode=RU&maxResults=20") else { return }
        do { let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url)); trendingVideos = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data).results } catch {}
    }

    private func loadPlinkPopular() async {
        let api = "https://plink-backend-production-ef31.up.railway.app"
        guard let url = URL(string: "\(api)/api/discovery/popular?window=24h&limit=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let t = KeychainHelper.read(for: "rave_auth_token") { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return }
            plinkPopular = try JSONDecoder().decode(PlinkPopularResponse.self, from: data).results
        } catch {}
    }

    @ViewBuilder private func watchRoom(for room: Room) -> some View {
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

// MARK: - V4TabBar (GPT-5.6 §3)
private struct V4TabBar: View {
    @Binding var selection: AppSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(section.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == section ? Cinema2026.accent : Cinema2026.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if selection == section {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Cinema2026.accent.opacity(0.10))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - V4Surface (GPT-5.6 §4)
struct V4Surface<Content: View>: View {
    let theme: PlinkLivingTheme
    let surface: PlinkLivingBackground.Surface
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            PlinkLivingBackground(theme: theme, surface: surface)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
