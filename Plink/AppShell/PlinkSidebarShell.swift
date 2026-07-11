// Plink/AppShell/PlinkSidebarShell.swift — iPad/macOS sidebar
//
// PATCH 25: use existing views (HomeView, RoomsTabContent, SettingsView)
// instead of new cinematic placeholders.

import SwiftUI

struct PlinkSidebarShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    Label("Plink", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(CinemaColor.text)
                        .listRowBackground(Color.clear)
                }

                Section("Смотреть") {
                    nav(.home)
                    nav(.rooms)
                    nav(.friends)
                }

                Section("Вы") {
                    nav(.profile)
                    nav(.settings)
                }

                Section {
                    Button {
                        createPresented = true
                    } label: {
                        Label("Создать комнату", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CinemaColor.plink)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .scrollContentBackground(.hidden)
            .background(CinemaColor.background)
        } detail: {
            detail(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(dependencies.apiClient)
    }

    private func nav(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.symbol)
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home:
            HomeTabContent(
                onProfileTap: { },
                onSwitchToAITab: nil,
                onSwitchToJoinTab: nil
            )
        case .rooms:
            RoomsTabContent()
        case .friends:
            FriendsView()
        case .profile:
            Text("Профиль")
                .cinematicScreen()
        case .settings:
            SettingsView()
        case .create:
            EmptyView()
        }
    }
}
