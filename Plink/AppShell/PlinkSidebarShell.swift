// Plink/AppShell/PlinkSidebarShell.swift — GPT-5.6 V4 (fixed)
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
                    nav(.home); nav(.rooms); nav(.ai); nav(.friends)
                }
                Section {
                    Button { createIntent = .chooseService } label: {
                        Label("Создать комнату", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Cinema2026.accent)
                }
                Section { nav(.profile) }
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
            VStack { Text("Главная").font(.largeTitle.bold()).foregroundStyle(Cinema2026.text) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Cinema2026.background)
        case .rooms:
            VStack { Text("Комнаты").font(.largeTitle.bold()).foregroundStyle(Cinema2026.text) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Cinema2026.background)
        case .ai:
            AIAssistantView()
        case .friends:
            VStack { Text("Друзья").font(.largeTitle.bold()).foregroundStyle(Cinema2026.text) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Cinema2026.background)
        case .profile:
            SettingsView(authService: dependencies.authService)
        }
    }
}
