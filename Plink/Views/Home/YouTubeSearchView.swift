// Plink/Views/Home/YouTubeSearchView.swift — Brain §4: Native YouTube picker
//
// Replaces URL paste with search + trending + tap-to-select.
// Uses backend /api/media/youtube/search and /api/media/youtube/trending.
// Shows embeddability status. URL paste is secondary action only.

import SwiftUI

// MARK: - Data models

struct YouTubeVideoSummary: Decodable, Identifiable, Sendable {
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailURL: String?
    let durationSeconds: Int?
    let liveBroadcastContent: String
    let embeddable: Bool?

    var id: String { videoId }

    var durationText: String? {
        guard let seconds = durationSeconds, seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var isLive: Bool { liveBroadcastContent == "live" }
}

struct YouTubeSearchPage: Decodable, Sendable {
    let items: [YouTubeVideoSummary]
    let nextPageToken: String?
}

// MARK: - Service

@MainActor
@Observable
final class YouTubePickerModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    var query = ""
    var items: [YouTubeVideoSummary] = []
    var state: State = .idle
    var selected: YouTubeVideoSummary?
    var showURLPaste = false
    var urlText = ""

    private var searchTask: Task<Void, Never>?
    private let apiBaseURL = "https://plink-backend-production-ef31.up.railway.app"

    func queryChanged() {
        searchTask?.cancel()
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if value.isEmpty {
                await loadTrending()
            } else {
                await search(value)
            }
        }
    }

    func loadTrending() async {
        state = .loading
        do {
            let url = URL(string: "\(apiBaseURL)/api/media/youtube/trending?regionCode=RU&limit=20")!
            var request = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Не удалось загрузить")
                return
            }
            let page = try JSONDecoder().decode(YouTubeSearchPage.self, from: data)
            items = page.items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func search(_ query: String) async {
        state = .loading
        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = URL(string: "\(apiBaseURL)/api/media/youtube/search?q=\(encoded)&limit=20")!
            var request = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Не удалось найти")
                return
            }
            let page = try JSONDecoder().decode(YouTubeSearchPage.self, from: data)
            items = page.items
            state = items.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() {
        Task {
            query.isEmpty ? await loadTrending() : await search(query)
        }
    }

    func selectFromURL() {
        let videoId = extractVideoId(from: urlText) ?? urlText
        guard videoId.count == 11 else { return }
        selected = YouTubeVideoSummary(
            videoId: videoId,
            title: "YouTube: \(videoId)",
            channelTitle: "",
            thumbnailURL: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg",
            durationSeconds: nil,
            liveBroadcastContent: "none",
            embeddable: nil
        )
    }

    private func extractVideoId(from url: String) -> String? {
        if url.contains("youtu.be/") {
            return url.components(separatedBy: "youtu.be/").last?.components(separatedBy: "?").first
        }
        if let components = URLComponents(string: url),
           let item = components.queryItems?.first(where: { $0.name == "v" }) {
            return item.value
        }
        if url.count == 11 { return url }
        return nil
    }
}

// MARK: - View

struct YouTubeSearchView: View {
    @State private var model = YouTubePickerModel()
    let onSelect: (String, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.showURLPaste {
                    urlPasteView
                } else {
                    switch model.state {
                    case .idle, .loading:
                        loadingView
                    case .empty:
                        emptyView
                    case .failed(let message):
                        errorView(message)
                    case .loaded:
                        resultsList
                    }
                }
            }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, prompt: "Найти видео")
            .onChange(of: model.query) { _, _ in model.queryChanged() }
            .task { await model.loadTrending() }
            .safeAreaInset(edge: .bottom) {
                if let item = model.selected {
                    selectedBar(item: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Ссылка") {
                        model.showURLPaste.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(model.items) { item in
            Button {
                model.selected = item
            } label: {
                YouTubeResultRow(item: item, isSelected: model.selected?.id == item.id)
            }
            .disabled(item.embeddable == false)
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Cinema2026.background)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Cinema2026.accent)
                .scaleEffect(1.2)
            Text(model.query.isEmpty ? "Загрузка популярного…" : "Поиск…")
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.secondary)
            Text("Ничего не найдено")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Text("Попробуйте другой запрос")
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.amber)
            Text("Ошибка")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Text(message)
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
            Button("Повторить") { model.retry() }
                .buttonStyle(.bordered)
                .tint(Cinema2026.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background)
    }

    // MARK: - URL paste fallback

    private var urlPasteView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(Cinema2026.secondary)
            Text("Вставить ссылку")
                .font(.headline)
                .foregroundStyle(Cinema2026.text)
            TextField("https://youtube.com/watch?v=…", text: $model.urlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)
            Button("Выбрать") {
                model.selectFromURL()
                if let item = model.selected {
                    confirmSelection(item)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Cinema2026.accent)
            .disabled(model.urlText.isEmpty)
            Spacer()
        }
        .background(Cinema2026.background)
    }

    // MARK: - Selected bar

    private func selectedBar(item: YouTubeVideoSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                    Text(item.channelTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    confirmSelection(item)
                } label: {
                    Text("Выбрать")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Cinema2026.background)
                }
            }
            .padding(14)
            .background(Cinema2026.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(Cinema2026.divider).frame(height: 0.5)
            }
        }
    }

    private func confirmSelection(_ item: YouTubeVideoSummary) {
        let url = "https://www.youtube.com/watch?v=\(item.videoId)"
        let thumb = item.thumbnailURL ?? "https://img.youtube.com/vi/\(item.videoId)/mqdefault.jpg"
        onSelect(url, item.title, thumb)
        dismiss()
    }
}

// MARK: - Result row

struct YouTubeResultRow: View {
    let item: YouTubeVideoSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: item.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let duration = item.durationText {
                    Text(duration)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(4)
                }

                if item.isLive {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Cinema2026.danger, in: Capsule())
                        .padding(4)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(2)

                Text(item.channelTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)

                if item.embeddable == false {
                    Text("Нельзя встроить")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Cinema2026.danger)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Cinema2026.accent)
            }
        }
        .padding(.vertical, 6)
        .background(isSelected ? Cinema2026.accent.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }
}
