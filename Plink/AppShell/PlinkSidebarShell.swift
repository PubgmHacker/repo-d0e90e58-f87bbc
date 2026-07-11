// Plink/AppShell/PlinkSidebarShell.swift — iPad/macOS sidebar
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: Sidebar shell

import SwiftUI

struct PlinkSidebarShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
    }

    private func nav(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .tag(section)
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home: DiscoveryHomeView(dependencies: dependencies)
        case .rooms: RoomsHubView(dependencies: dependencies)
        case .friends: FriendsView()
        case .profile: ProfileView()
        case .settings: SettingsHubView(dependencies: dependencies)
        case .create: EmptyView()
        }
    }
}
