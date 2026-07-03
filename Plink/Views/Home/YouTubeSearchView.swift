import SwiftUI

// MARK: - YouTube Search View
/// Экран поиска роликов YouTube с прямой интеграцией в создание комнаты.
/// Пользователь ищет → выбирает ролик → URL подставляется в RoomCreation.
struct YouTubeSearchView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [YouTubeSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    /// Колбэк: выбранный ролик (URL + тайтл).
    let onSelect: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(spacing: 0) {
                    searchBar
                    Divider().background(Color.raveSurface)

                    if isLoading {
                        loadingState
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle(loc.string(.searchTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.string(.cancel)) { dismiss() }
                        .foregroundColor(.ravePrimary)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.raveTextSecondary)

            TextField(loc.string(.searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .foregroundColor(.raveTextPrimary)
                .submitLabel(.search)
                .onSubmit { performSearch() }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.raveTextSecondary)
                }
            }

            Button(loc.string(.searchButton)) { performSearch() }
                .font(.subheadline.bold())
                .foregroundColor(.ravePrimary)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.raveCard)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.ravePrimary)
            Text(loc.string(.loading))
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.raveWarning)
            Text(loc.string(.searchError))
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.center)
            Button(loc.string(.searchButton)) { performSearch() }
                .font(.subheadline.bold())
                .foregroundColor(.ravePrimary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 44))
                .foregroundColor(.raveTextTertiary)
            Text(hasSearched ? loc.string(.searchEmpty) : loc.string(.searchHint))
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(results) { item in
                    YouTubeSearchRow(item: item) {
                        selectItem(item)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        results = []

        Task {
            do {
                let found = try await searchService().search(query: q)
                results = found
                hasSearched = true
            } catch {
                errorMessage = error.localizedDescription
                hasSearched = true
            }
            isLoading = false
        }
    }

    private func selectItem(_ item: YouTubeSearchResult) {
        onSelect(item.url, item.title)
        dismiss()
    }

    /// Получаем сервис из environment (DI). Fallback на дефолтный URL.
    private func searchService() -> YouTubeSearchService {
        // Используем тот же base URL что и MediaService
        YouTubeSearchService()
    }
}

// MARK: - Search Result Row

private struct YouTubeSearchRow: View {
    let item: YouTubeSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    thumbnail
                        .frame(width: 120, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let dur = item.formattedDuration {
                        Text(dur)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                .frame(width: 120, height: 68)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.raveTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let channel = item.channel {
                        Text(channel)
                            .font(.caption2)
                            .foregroundColor(.raveTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.ravePrimary)
            }
            .padding(10)
            .background(Color.raveCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.raveSurface, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.raveSurface)
                }
            }
        } else {
            Rectangle().fill(Color.raveSurface)
            Image(systemName: "play.rectangle")
                .foregroundColor(.raveTextTertiary)
        }
    }
}
