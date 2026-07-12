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
                    nav(.rooms)
                    nav(.ai)
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
                    nav(.settings)
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
            // GPT-5.6 SOL: HomeView requires HomeViewModel — use a simple wrapper
            // that creates it from AppDependencies.
            SidebarHomeWrapper(dependencies: dependencies)
        case .rooms:
            // GPT-5.6 SOL: RoomsTabContent not on this branch — use placeholder.
            VStack {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(Cinema2026.secondary)
                Text("Комнаты")
                    .font(.title)
                    .foregroundStyle(Cinema2026.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Cinema2026.background)
        case .ai:
            AIAssistantView()
        case .friends:
            FriendsView()
        case .settings:
            // GPT-5.6 SOL: SettingsTabContent not on this branch — use SettingsView directly.
            SettingsView(authService: dependencies.authService)
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
