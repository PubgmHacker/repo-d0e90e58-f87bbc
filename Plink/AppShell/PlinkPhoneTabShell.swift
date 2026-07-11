// Plink/AppShell/PlinkPhoneTabShell.swift — iPhone tab bar
//
// PATCH 26: 5 tabs (Home, Rooms, AI, Friends, Settings), no Create tab.
// Create is triggered from Home/Rooms toolbar buttons like before.

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        TabView(selection: $selection) {
            HomeTabContent(
                onProfileTap: { createPresented = true },
                onSwitchToAITab: { selection = .ai },
                onSwitchToJoinTab: { selection = .rooms }
            )
            .tag(AppSection.home)
            .tabItem { Label("Главная", systemImage: "house") }

            RoomsTabContent()
                .tag(AppSection.rooms)
                .tabItem { Label("Комнаты", systemImage: "play.rectangle.on.rectangle") }

            AIAssistantView()
                .tag(AppSection.ai)
                .tabItem { Label("ИИ", systemImage: "sparkles") }

            FriendsView()
                .tag(AppSection.friends)
                .tabItem { Label("Друзья", systemImage: "person.2") }

            SettingsTabContent(authService: dependencies.authService)
                .tag(AppSection.settings)
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(CinemaColor.plink)
        .environmentObject(dependencies.apiClient)
    }
}
