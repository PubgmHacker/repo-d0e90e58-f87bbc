// Plink/AppShell/PlinkPhoneTabShell.swift — iPhone tab bar
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: Phone tab shell

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        TabView(selection: $selection) {
            DiscoveryHomeView(dependencies: dependencies)
                .tag(AppSection.home)
                .tabItem { Label("Главная", systemImage: "house") }

            RoomsHubView(dependencies: dependencies)
                .tag(AppSection.rooms)
                .tabItem { Label("Комнаты", systemImage: "play.rectangle.on.rectangle") }

            Color.clear
                .tag(AppSection.create)
                .tabItem { Label("Создать", systemImage: "plus") }

            FriendsView()
                .tag(AppSection.friends)
                .tabItem { Label("Друзья", systemImage: "person.2") }

            SettingsHubView(dependencies: dependencies)
                .tag(AppSection.settings)
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(CinemaColor.plink)
        .onChange(of: selection) { oldValue, newValue in
            guard newValue == .create else { return }
            selection = oldValue
            createPresented = true
        }
    }
}
