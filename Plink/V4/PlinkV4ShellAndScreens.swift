import SwiftUI
import Observation

public struct PlinkV4Root: View {
    @State private var selectedTab: V4Tab = .home
    @State private var themeStore = V4ThemeStore()
    @State private var showCreate = false
    @State private var activeRoomID: String?
    let adapter: any V4AppAdapter

    public var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            V4TabBar(selection: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .environment(themeStore)
        .preferredColorScheme(.dark)
        .task { await adapter.bootstrap() }
        .sheet(isPresented: $showCreate) {
            V4RoomCreationFlow(adapter: adapter, themeStore: themeStore) { roomID in
                showCreate = false
                activeRoomID = roomID
            }
        }
        .fullScreenCover(item: $activeRoomID) { roomID in
            V4WatchRoomBridge(roomID: roomID, themeStore: themeStore, adapter: adapter)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .home: V4HomeScreen(adapter: adapter, create: { showCreate = true }, openRoom: { activeRoomID = $0 })
        case .rooms: V4RoomsScreen(adapter: adapter, create: { showCreate = true }, openRoom: { activeRoomID = $0 })
        case .ai: V4AIScreen(adapter: adapter, themeStore: themeStore)
        case .friends: V4FriendsScreen(adapter: adapter)
        case .profile: V4ProfileScreen(adapter: adapter, themeStore: themeStore)
        }
    }
}

extension String: @retroactive Identifiable { public var id: String { self } }

public struct V4TabBar: View {
    @Binding var selection: V4Tab

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(V4Tab.allCases) { tab in
                Button { withAnimation(.easeOut(duration: 0.22)) { selection = tab } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                        Text(tab.title).font(.caption2).lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? V4Tokens.accent : V4Tokens.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16).fill(V4Tokens.accent.opacity(0.10))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
    }

    @Namespace private var namespace
}

public struct V4HomeScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter
    let create: () -> Void
    let openRoom: (String) -> Void
    @State private var search = ""

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .home) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    HStack {
                        V4Avatar(user: adapter.currentUser)
                        Spacer()
                        Button(action: {}) { Image(systemName: "bell") }.buttonStyle(V4CircleButtonStyle())
                    }
                    .padding(.horizontal, V4Tokens.horizontal)

                    V4ScreenHeader(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                        .padding(.horizontal, V4Tokens.horizontal)

                    V4SearchField(text: $search, prompt: "Видео, сервис или комната")
                        .padding(.horizontal, V4Tokens.horizontal)

                    if let hero = adapter.trending.first {
                        V4HeroBanner(item: hero, action: create)
                            .padding(.horizontal, 13)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        V4SectionTitle(title: "Сейчас вместе", actionTitle: "Все", action: nil)
                            .padding(.horizontal, V4Tokens.horizontal)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 11) {
                                ForEach(adapter.liveRooms) { room in V4RoomCard(room: room) { openRoom(room.id) } }
                            }
                            .padding(.horizontal, V4Tokens.horizontal)
                        }
                        .scrollIndicators(.hidden)
                    }

                    Button("Создать комнату", systemImage: "plus", action: create)
                        .buttonStyle(V4PrimaryButtonStyle())
                        .padding(.horizontal, V4Tokens.horizontal)
                }
                .padding(.top, 10)
                .padding(.bottom, 108)
            }
            .scrollIndicators(.hidden)
            .refreshable { await adapter.refreshHome() }
        }
    }
}

public struct V4RoomsScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter
    let create: () -> Void
    let openRoom: (String) -> Void

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .rooms) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    V4ScreenHeader(eyebrow: "ОБЗОР", title: "Комнаты")
                    Button("Создать комнату", systemImage: "plus", action: create).buttonStyle(V4PrimaryButtonStyle())
                    ForEach(adapter.liveRooms) { room in V4RoomCard(room: room) { openRoom(room.id) } }
                }
                .padding(.horizontal, V4Tokens.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 108)
            }
        }
    }
}

public struct V4FriendsScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .friends) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    V4ScreenHeader(eyebrow: "ВМЕСТЕ ЛУЧШЕ", title: "Друзья")
                    V4SectionTitle(title: "Сейчас онлайн", actionTitle: nil, action: nil)
                    ForEach(adapter.friends) { user in
                        HStack(spacing: 12) {
                            V4Avatar(user: user, size: 40)
                            VStack(alignment: .leading) { Text(user.displayName).bold(); Text(user.subtitle).font(.caption).foregroundStyle(V4Tokens.secondaryText) }
                            Spacer()
                            Button("Позвать") { adapter.invite(userID: user.id) }.buttonStyle(.bordered)
                        }
                        .frame(minHeight: 58)
                    }
                }
                .padding(.horizontal, V4Tokens.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 108)
            }
        }
    }
}

public struct V4ProfileScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter
    let themeStore: V4ThemeStore
    @State private var showThemes = false

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .profile) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        V4Avatar(user: adapter.currentUser, size: 58)
                        VStack(alignment: .leading) { Text(adapter.currentUser.displayName).font(.title2.bold()); Text("Plink+").foregroundStyle(V4Tokens.warning) }
                    }
                    SettingsGroup(title: "Аккаунт", rows: ["Личные данные", "Приватность и безопасность", "Заблокированные"])
                    SettingsGroup(title: "Приложение", rows: ["Оформление", "Уведомления", "Воспроизведение", "Помощь"], onTap: { if $0 == "Оформление" { showThemes = true } })
                    Button("Выйти") { Task { await adapter.signOut() } }.buttonStyle(V4SecondaryButtonStyle())
                    Button("Удалить аккаунт", role: .destructive) { Task { try? await adapter.deleteAccount() } }
                }
                .padding(.horizontal, V4Tokens.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 108)
            }
        }
        .sheet(isPresented: $showThemes) { V4ThemePicker(store: themeStore) }
    }
}

private struct SettingsGroup: View {
    let title: String
    let rows: [String]
    var onTap: (String) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(V4Tokens.secondaryText)
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    Button { onTap(row) } label: { HStack { Text(row); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 52) }
                        .buttonStyle(.plain)
                    if row != rows.last { Divider().overlay(.white.opacity(0.08)) }
                }
            }
            .padding(.horizontal, 14)
            .background(V4Tokens.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct V4ThemePicker: View {
    @Bindable var store: V4ThemeStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(V4ThemeCatalog.all) { theme in
                        Button { try? store.selectApp(theme.id) } label: {
                            ZStack(alignment: .bottomLeading) {
                                V4LivingBackground(theme: theme, surface: .profile)
                                Text(theme.name).font(.caption.bold()).padding(10)
                            }
                            .frame(width: 128, height: 174)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(20)
            }
            .navigationTitle("Оформление")
            .toolbar { Button("Готово") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
