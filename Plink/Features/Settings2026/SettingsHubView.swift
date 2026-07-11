// Plink/Features/Settings2026/SettingsHubView.swift — Settings hub
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §5

import SwiftUI

enum SettingsDetailRoute: Hashable {
    case account
    case premium
    case playback
    case danmaku
    case voiceVideo
    case chatAppearance
    case privacy
    case notifications
    case language
    case admin
    case about
}

@MainActor
@Observable
final class SettingsHubViewModel {
    var isAdmin = false
    var isPremium = false
    var bubbleStyleName = "Стандарт"
    var languageName = "Русский"
    var signOutConfirmation = false
    var deleteConfirmation = false

    private let authService: AuthService
    private let apiClient: APIClient

    init(authService: AuthService, apiClient: APIClient) {
        self.authService = authService
        self.apiClient = apiClient
    }

    func load() async {
        isPremium = PremiumStatusManager.shared.isPremium
        // TODO: wire isAdmin from user role
    }
}

struct SettingsHubView: View {
    @State private var model: SettingsHubViewModel
    @Environment(\.horizontalSizeClass) private var widthClass

    init(dependencies: AppDependencies) {
        _model = State(initialValue: SettingsHubViewModel(
            authService: dependencies.authService,
            apiClient: dependencies.apiClient
        ))
    }

    var body: some View {
        Group {
            if widthClass == .regular {
                NavigationSplitView {
                    SettingsSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
                        .scrollContentBackground(.hidden)
                        .background(CinemaColor.background)
                } detail: {
                    SettingsDetailView(route: .account, model: model)
                }
            } else {
                NavigationStack {
                    SettingsPhoneList(model: model)
                }
            }
        }
        .task { await model.load() }
        .background(CinemaColor.background)
    }
}

struct SettingsSidebar: View {
    let model: SettingsHubViewModel

    var body: some View {
        List {
            Section {
                ProfileSettingsHeader(model: model)
            }
            Section("Просмотр") {
                Label("Воспроизведение", systemImage: "play.rectangle")
                Label("Летящие комментарии", systemImage: "text.bubble")
                Label("Голос и камера", systemImage: "waveform")
            }
            Section("Общение") {
                Label("Оформление чата", systemImage: "bubble.left.and.bubble.right")
                Label("Уведомления", systemImage: "bell")
            }
            Section("Аккаунт") {
                Label("Приватность", systemImage: "lock.shield")
                Label("Язык", systemImage: "globe")
            }
            if model.isAdmin {
                Section("Администрирование") {
                    Label("Админ-панель", systemImage: "shield")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CinemaColor.background)
    }
}

struct SettingsPhoneList: View {
    let model: SettingsHubViewModel

    var body: some View {
        List {
            Section {
                ProfileSettingsHeader(model: model)
                NavigationLink {
                    Text("Plink+")
                        .cinematicScreen()
                } label: {
                    PlinkPlusRow(model: model)
                }
            }

            Section("Просмотр") {
                SettingsNavigationRow(title: "Воспроизведение", subtitle: "Качество, PiP, автозапуск", symbol: "play.rectangle")
                SettingsNavigationRow(title: "Летящие комментарии", subtitle: "Плотность, скорость, прозрачность", symbol: "text.bubble")
                SettingsNavigationRow(title: "Голос и камера", subtitle: "Push-to-talk, шумоподавление", symbol: "waveform")
            }

            Section("Общение") {
                SettingsNavigationRow(title: "Оформление чата", subtitle: model.bubbleStyleName, symbol: "bubble.left.and.bubble.right")
                SettingsNavigationRow(title: "Уведомления", subtitle: nil, symbol: "bell")
            }

            Section("Аккаунт") {
                SettingsNavigationRow(title: "Приватность", subtitle: nil, symbol: "lock.shield")
                SettingsNavigationRow(title: "Язык", subtitle: model.languageName, symbol: "globe")
            }

            if model.isAdmin {
                Section("Администрирование") {
                    SettingsNavigationRow(title: "Админ-панель", subtitle: "Требуется 2FA", symbol: "shield")
                }
            }

            Section {
                Button("Выйти", role: .destructive) { model.signOutConfirmation = true }
                Button("Удалить аккаунт", role: .destructive) { model.deleteConfirmation = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CinemaColor.background)
        .navigationTitle("Настройки")
    }
}

struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String?
    let symbol: String

    var body: some View {
        NavigationLink {
            Text(title)
                .cinematicScreen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(CinemaColor.plink)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(CinemaColor.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(CinemaColor.secondary)
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(CinemaColor.divider)
    }
}

struct ProfileSettingsHeader: View {
    let model: SettingsHubViewModel

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(CinemaColor.raised)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(CinemaColor.secondary)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Профиль")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CinemaColor.text)
                if model.isPremium {
                    Text("Plink+")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CinemaColor.plink)
                }
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
}

struct PlinkPlusRow: View {
    let model: SettingsHubViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(CinemaColor.plink)
            Text(model.isPremium ? "Plink+ активен" : "Получить Plink+")
                .foregroundStyle(CinemaColor.text)
            Spacer()
            if !model.isPremium {
                Image(systemName: "chevron.right")
                    .foregroundStyle(CinemaColor.tertiary)
            }
        }
        .listRowBackground(Color.clear)
    }
}

struct SettingsDetailView: View {
    let route: SettingsDetailRoute
    let model: SettingsHubViewModel

    var body: some View {
        Text("Settings detail: \(String(describing: route))")
            .cinematicScreen()
    }
}
