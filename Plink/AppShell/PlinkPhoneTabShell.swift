// Plink/AppShell/PlinkPhoneTabShell.swift — §4 Final Architecture
//
// 5 canonical tabs. Profile → Settings (not Create).
// Create Room via sheet from Home/Rooms toolbar.

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        TabView(selection: $selection) {
            HomeTabContent(
                onProfileTap: { selection = .settings },
                onSwitchToAITab: { selection = .ai },
                onSwitchToJoinTab: { selection = .rooms }
            )
            .tag(AppSection.home)
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.symbol) }

            RoomsTabContent()
                .tag(AppSection.rooms)
                .tabItem { Label(AppSection.rooms.title, systemImage: AppSection.rooms.symbol) }

            AIAssistantView()
                .tag(AppSection.ai)
                .tabItem { Label(AppSection.ai.title, systemImage: AppSection.ai.symbol) }

            FriendsView()
                .tag(AppSection.friends)
                .tabItem { Label(AppSection.friends.title, systemImage: AppSection.friends.symbol) }

            SettingsTabContent(authService: dependencies.authService)
                .tag(AppSection.settings)
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.symbol) }
        }
        .tint(CinemaColor.plink)
        .toolbarBackground(CinemaColor.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(dependencies.apiClient)
    }
}
