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
            HomeTabContent(
                onProfileTap: { selection = .profile },
                onSwitchToAITab: nil,
                onSwitchToJoinTab: nil
            )
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

            SettingsTabContent(authService: dependencies.authService)
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
