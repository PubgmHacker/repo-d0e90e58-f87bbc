// Plink/AppShell/DiscoverScreen.swift — GPT-5.6 SOL §8.8
//
// Designed destination screen for Discover tab.
// Title + search; featured live room; public-room rail; loading/empty/offline states.

import SwiftUI

struct DiscoverScreen: View {
    @Environment(PlinkThemeStore.self) private var themeStore
    let dependencies: AppDependencies
    @Binding var navigateToRoom: Room?

    @State private var searchText = ""
    @State private var homeViewModel: HomeViewModel?
    @State private var trendingVideos: [YouTubeVideoSummary] = []

    var body: some View {
        V4Surface(theme: themeStore.appTheme, surface: .rooms) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Title
                    Text("Обзор")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Cinema2026.secondary)
                        TextField("Поиск комнат и видео", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 50)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Cinema2026.divider, lineWidth: 0.5))
                    .padding(.horizontal, 20)

                    // Featured live rooms
                    if let vm = homeViewModel, !vm.activeRooms.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Сейчас в эфире")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(vm.activeRooms) { room in
                                        Button {
                                            navigateToRoom = room
                                        } label: {
                                            DiscoverRoomCard(room: room)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Trending
                    if !trendingVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Популярное на YouTube")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(trendingVideos.prefix(10)) { video in
                                        DiscoverTrendingCard(video: video)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // Empty state
                    if homeViewModel?.activeRooms.isEmpty != false && trendingVideos.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 48))
                                .foregroundStyle(Cinema2026.secondary)
                            Text("Нет активных комнат")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                            Text("Создайте первую комнату — кнопка «Создать» внизу")
                                .font(.system(size: 13))
                                .foregroundStyle(Cinema2026.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private func loadTrending() async {
        let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app"
        guard let url = URL(string: "\(apiBaseURL)/api/media/trending?regionCode=RU&maxResults=10") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            trendingVideos = resp.results
        } catch {}
    }
}

// MARK: - Cards

private struct DiscoverRoomCard: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: room.mediaItem?.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Cinema2026.danger, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }

            Text(room.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            Text("\(room.participantCount) участников")
                .font(.system(size: 11))
                .foregroundStyle(Cinema2026.secondary)
                .frame(width: 200, alignment: .leading)
        }
    }
}

private struct DiscoverTrendingCard: View {
    let video: YouTubeVideoSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: video.thumbnailURLString ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Cinema2026.surface)
            }
            .frame(width: 200, height: 113)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(video.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)

            Text(video.channelTitle)
                .font(.system(size: 11))
                .foregroundStyle(Cinema2026.secondary)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
        }
    }
}
