// Plink/AppShell/PlinkSidebarShell.swift — §4 Final Architecture

import SwiftUI

struct PlinkSidebarShell: View {
    @Binding var selection: AppSection
    @Binding var createIntent: CreateRoomIntent?
    let dependencies: AppDependencies

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    Label("Plink", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Cinema2026.text)
                        .listRowBackground(Color.clear)
                }

                Section("Смотреть") {
                    nav(.home)
                    nav(.discover)
                    nav(.friends)
                }

                Section {
                    Button {
                        createIntent = .chooseService
                    } label: {
                        Label("Создать комнату", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Cinema2026.accent)
                }

                Section {
                    nav(.profile)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .scrollContentBackground(.hidden)
            .background(Cinema2026.background)
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
            SidebarHomeWrapper(dependencies: dependencies)
        case .discover:
            DiscoverScreen(dependencies: dependencies, navigateToRoom: .constant(nil))
        case .create:
            EmptyView()
        case .friends:
            FriendsScreen(dependencies: dependencies)
        case .profile:
            ProfileScreen(authService: dependencies.authService)
        }
    }
}

/// GPT-5.6 SOL: wrapper that creates HomeViewModel for sidebar usage.
private struct SidebarHomeWrapper: View {
    let dependencies: AppDependencies

    var body: some View {
        HomeView(
            viewModel: HomeViewModel(
                roomService: dependencies.roomService,
                authService: dependencies.authService
            ),
            onProfileTap: { }
        )
        .environmentObject(dependencies.apiClient)
    }
}
