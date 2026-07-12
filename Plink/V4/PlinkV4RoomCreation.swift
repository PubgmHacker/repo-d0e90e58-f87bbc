import SwiftUI

public struct V4RoomCreationFlow: View {
    enum Step: Hashable { case services, youtube, provider(String), directLink, setup, summary }
    let adapter: any V4AppAdapter
    @Bindable var themeStore: V4ThemeStore
    let completed: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var draft = V4RoomDraft()

    public var body: some View {
        NavigationStack(path: $path) {
            V4ServiceSelectionScreen(adapter: adapter) { service in
                draft.serviceID = service.id
                switch service.kind {
                case .youtube: path.append(.youtube)
                case .directLink: path.append(.directLink)
                default: path.append(.provider(service.id))
                }
            }
            .navigationDestination(for: Step.self, destination: destination)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .environment(themeStore)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func destination(_ step: Step) -> some View {
        switch step {
        case .services: EmptyView()
        case .youtube: V4YouTubeSearchScreen(adapter: adapter) { draft.media = .youtube($0); path.append(.setup) }
        case .provider(let id): V4ProviderBrowserScreen(serviceID: id, adapter: adapter) { draft.media = .provider(serviceID: id, item: $0); path.append(.setup) }
        case .directLink: V4DirectLinkScreen(adapter: adapter) { draft.media = .directLink(validatedToken: $0.token, title: $0.title); path.append(.setup) }
        case .setup: V4RoomSetupScreen(draft: $draft, themeStore: themeStore) { path.append(.summary) }
        case .summary: V4RoomSummaryScreen(draft: draft) { let id = try await adapter.createRoom(draft: draft); completed(id) }
        }
    }
}

public struct V4ServiceSelectionScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter
    let selected: (V4VideoService) -> Void
    @State private var category: String?

    private var filtered: [V4VideoService] { category.map { id in adapter.services.filter { $0.categoryID == id } } ?? adapter.services }

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .rooms) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    V4ScreenHeader(eyebrow: "НОВАЯ КОМНАТА", title: "Выберите сервис", subtitle: "У каждого источника свой безопасный сценарий")
                    ScrollView(.horizontal) {
                        HStack {
                            categoryChip("Все", id: nil)
                            ForEach(adapter.serviceCategories) { item in categoryChip(item.title, id: item.id) }
                        }
                    }.scrollIndicators(.hidden)
                    ForEach(filtered) { service in
                        Button { if service.isAvailable { selected(service) } } label: {
                            HStack(spacing: 12) {
                                Text(service.symbol).font(.headline).frame(width: 48, height: 48).background(V4Tokens.raised, in: RoundedRectangle(cornerRadius: 15))
                                VStack(alignment: .leading) { Text(service.name).bold(); Text(service.subtitle).font(.caption).foregroundStyle(V4Tokens.secondaryText) }
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(minHeight: 70)
                        }.buttonStyle(.plain).opacity(service.isAvailable ? 1 : 0.45)
                    }
                }.padding(20)
            }
        }
    }

    private func categoryChip(_ title: String, id: String?) -> some View {
        Button(title) { category = id }.buttonStyle(.bordered).tint(category == id ? V4Tokens.accent : V4Tokens.secondaryText)
    }
}

@MainActor
@Observable
final class V4YouTubeSearchState {
    var query = ""
    var items: [V4MediaCard] = []
    var loading = false
    var nextPageToken: String?
    var error: String?
    private var task: Task<Void, Never>?

    func changed(adapter: any V4AppAdapter) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(adapter: adapter, reset: true)
        }
    }

    func search(adapter: any V4AppAdapter, reset: Bool) async {
        loading = true; defer { loading = false }
        do {
            let result = try await adapter.searchYouTube(query: query, pageToken: reset ? nil : nextPageToken)
            items = reset ? result.0 : items + result.0.filter { item in !items.contains(where: { $0.id == item.id }) }
            nextPageToken = result.1; error = nil
        } catch { self.error = String(describing: error) }
    }
}

public struct V4YouTubeSearchScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter
    let selected: (V4MediaCard) -> Void
    @State private var state = V4YouTubeSearchState()

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .rooms) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    V4ScreenHeader(eyebrow: "YOUTUBE", title: "Выберите видео", subtitle: "Найдите ролик и тапните по карточке")
                    V4SearchField(text: $state.query, prompt: "Поиск на YouTube").onChange(of: state.query) { _, _ in state.changed(adapter: adapter) }
                    if state.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                    if let error = state.error { Text(error).foregroundStyle(V4Tokens.danger) }
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                        ForEach(state.items) { item in
                            Button { if item.isSelectable { selected(item) } } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    AsyncImage(url: item.artworkURL) { phase in
                                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { V4Tokens.raised }
                                    }.frame(height: 102).clipShape(RoundedRectangle(cornerRadius: 16))
                                    Text(item.title).font(.caption.bold()).lineLimit(2)
                                    Text(item.subtitle).font(.caption2).foregroundStyle(V4Tokens.secondaryText).lineLimit(1)
                                }
                            }.buttonStyle(.plain).opacity(item.isSelectable ? 1 : 0.45)
                        }
                    }
                }.padding(20)
            }
        }.task { await state.search(adapter: adapter, reset: true) }
    }
}

public struct V4ProviderBrowserScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let serviceID: String; let adapter: any V4AppAdapter; let selected: (V4MediaCard) -> Void
    @State private var items: [V4MediaCard] = []
    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .rooms) {
            ScrollView { LazyVStack(spacing: 14) { ForEach(items) { item in Button { selected(item) } label: { Text(item.title).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(.horizontal, 14).background(V4Tokens.surface, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) } }.padding(20) }
        }.task { items = (try? await adapter.browse(serviceID: serviceID)) ?? [] }
    }
}

public struct V4DirectLinkScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    let adapter: any V4AppAdapter; let validated: ((token: String, title: String)) -> Void
    @State private var value = ""; @State private var loading = false; @State private var error: String?
    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .rooms) {
            VStack(alignment: .leading, spacing: 20) {
                V4ScreenHeader(eyebrow: "ВИДЕО ПО ССЫЛКЕ", title: "Добавьте источник", subtitle: "Отдельный сервис для HLS, MP4 или разрешённого URL")
                TextField("https://…", text: $value).textInputAutocapitalization(.never).keyboardType(.URL).padding(14).background(V4Tokens.surface, in: RoundedRectangle(cornerRadius: 16))
                if let error { Text(error).foregroundStyle(V4Tokens.danger) }
                Button(loading ? "Проверяем…" : "Проверить видео") { Task { loading = true; defer { loading = false }; do { validated(try await adapter.validateDirectLink(value)) } catch { self.error = String(describing: error) } } }.buttonStyle(V4PrimaryButtonStyle())
            }.padding(20)
        }
    }
}

public struct V4RoomSetupScreen: View {
    @Binding var draft: V4RoomDraft
    @Bindable var themeStore: V4ThemeStore
    let next: () -> Void
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                V4ScreenHeader(eyebrow: "НАСТРОЙКА", title: "Оформите комнату")
                TextField("Название комнаты", text: $draft.title).padding(14).background(V4Tokens.surface, in: RoundedRectangle(cornerRadius: 16))
                Picker("Доступ", selection: $draft.privacy) { ForEach(V4RoomPrivacy.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Toggle("Plink AI в комнате", isOn: $draft.aiEnabled)
                Text("Оформление комнаты").font(.headline)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(V4ThemeCatalog.all) { theme in
                            Button { if theme.access == .free || themeStore.hasPremium { draft.themeID = theme.id } } label: {
                                ZStack(alignment: .bottomLeading) { V4LivingBackground(theme: theme, surface: .roomChat); Text(theme.name).font(.caption.bold()).padding(10) }
                                    .frame(width: 112, height: 150).clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(draft.themeID == theme.id ? .white : .white.opacity(0.12), lineWidth: draft.themeID == theme.id ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
                Button("Продолжить", action: next).buttonStyle(V4PrimaryButtonStyle()).disabled(!draft.isValid)
            }.padding(20)
        }
    }
}

public struct V4RoomSummaryScreen: View {
    let draft: V4RoomDraft; let create: () async throws -> Void
    @State private var loading = false
    public var body: some View {
        VStack(spacing: 20) {
            V4ScreenHeader(eyebrow: "ПРОВЕРКА", title: "Создать комнату?")
            VStack { summary("Название", draft.title); summary("Доступ", draft.privacy.title); summary("Тема", V4ThemeCatalog.resolve(draft.themeID).name); summary("Plink AI", draft.aiEnabled ? "Включён" : "Выключен") }.padding(14).background(V4Tokens.surface, in: RoundedRectangle(cornerRadius: 20))
            Button(loading ? "Создаём…" : "Создать комнату") { Task { loading = true; defer { loading = false }; try? await create() } }.buttonStyle(V4PrimaryButtonStyle())
        }.padding(20)
    }
    private func summary(_ key: String, _ value: String) -> some View { HStack { Text(key).foregroundStyle(V4Tokens.secondaryText); Spacer(); Text(value).bold() }.frame(minHeight: 44) }
}
