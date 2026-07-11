// Plink/AppShell/PlinkPhoneTabShell.swift — iPhone tab bar
//
// PATCH 25: use existing HomeView + RoomService + fullScreenCover
// instead of DiscoveryHomeView (which created new services and
// broke media/room creation).

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    @State private var homeViewModel: HomeViewModel?

    var body: some View {
        TabView(selection: $selection) {
            // Home — use existing HomeView with real HomeViewModel
            NavigationStack {
                ZStack {
                    if let homeViewModel {
                        HomeView(
                            viewModel: homeViewModel,
                            onProfileTap: { selection = .profile },
                            onSwitchToAITab: { },
                            onSwitchToJoinTab: { }
                        )
                    } else {
                        ProgressView().tint(CinemaColor.plink)
                    }
                }
                .fullScreenCover(item: $navigateToRoom) { room in
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
            .onAppear {
                if homeViewModel == nil {
                    homeViewModel = HomeViewModel(
                        roomService: dependencies.roomService,
                        authService: dependencies.authService
                    )
                }
            }
            .tag(AppSection.home)
            .tabItem { Label("Главная", systemImage: "house") }

            // Rooms — use existing RoomsTabContent (has its own fullScreenCover)
            RoomsTabContent()
                .tag(AppSection.rooms)
                .tabItem { Label("Комнаты", systemImage: "play.rectangle.on.rectangle") }

            Color.clear
                .tag(AppSection.create)
                .tabItem { Label("Создать", systemImage: "plus") }

            FriendsView()
                .tag(AppSection.friends)
                .tabItem { Label("Друзья", systemImage: "person.2") }

            SettingsView()
                .tag(AppSection.settings)
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(CinemaColor.plink)
        .environmentObject(dependencies.apiClient)
        .onChange(of: selection) { oldValue, newValue in
            guard newValue == .create else { return }
            selection = oldValue
            createPresented = true
        }
    }
}
