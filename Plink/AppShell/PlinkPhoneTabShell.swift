// Plink/AppShell/PlinkPhoneTabShell.swift — Final: all new cinematic views
//
// 5 tabs using NEW cinematic components, not legacy HomeTabContent/etc.

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    @State private var navigateToRoom: Room?
    @State private var homeViewModel: HomeViewModel?

    var body: some View {
        TabView(selection: $selection) {
            // Главная — new compact home with rails
            NavigationStack {
                compactHome
                    .fullScreenCover(item: $navigateToRoom) { room in
                        watchRoom(for: room)
                    }
            }
            .tag(AppSection.home)
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.symbol) }

            // Комнаты — new compact rooms hub
            NavigationStack {
                compactRooms
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

            // Настройки — existing SettingsView (has real settings)
            SettingsView()
                .tag(AppSection.settings)
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.symbol) }
        }
        .tint(Cinema2026.accent)
        .toolbarBackground(Cinema2026.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(dependencies.apiClient)
    }

    // MARK: - Compact Home

    private var compactHome: some View {
        ScrollView {
            LazyVStack(spacing: CompactPhoneMetrics.sectionSpacing) {
                CompactHomeHeader(
                    openProfile: { selection = .settings },
                    openJoin: { selection = .rooms }
                )

                CompactAIEntryCard {
                    selection = .ai
                }

                if let vm = homeViewModel {
                    if vm.activeRooms.isEmpty && vm.myRooms.isEmpty {
                        CompactNoLiveRoomsState {
                            createPresented = true
                        }
                    } else {
                        if !vm.activeRooms.isEmpty {
                            CompactRoomRail(
                                title: "Сейчас в эфире",
                                rooms: vm.activeRooms,
                                style: .landscape,
                                open: { navigateToRoom = $0 }
                            )
                        }
                        if !vm.myRooms.isEmpty {
                            CompactRoomRail(
                                title: "Мои комнаты",
                                rooms: vm.myRooms,
                                style: .poster,
                                open: { navigateToRoom = $0 }
                            )
                        }
                    }
                } else {
                    ProgressView()
                        .tint(Cinema2026.accent)
                        .padding(.top, 40)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(Cinema2026.background)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Cinema2026.accent)
                }
            }
        }
        .task {
            if homeViewModel == nil {
                homeViewModel = HomeViewModel(
                    roomService: dependencies.roomService,
                    authService: dependencies.authService
                )
                await homeViewModel?.loadRooms()
                await homeViewModel?.loadMyRooms()
            }
        }
        .safeAreaInset(edge: .bottom) {
            CompactRoomActions(
                create: { createPresented = true },
                join: { selection = .rooms }
            )
        }
    }

    // MARK: - Compact Rooms

    private var compactRooms: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Комнаты")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                Button {
                    createPresented = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Cinema2026.accent)
                }
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
                    Button("Создать комнату") {
                        createPresented = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
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
            await homeViewModel?.loadMyRooms()
        }
        .fullScreenCover(item: $navigateToRoom) { room in
            watchRoom(for: room)
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
