import SwiftUI

// MARK: - YouTube Search View (v33)
/// 🔧 v33: YouTube-style search screen with:
///   - Trending videos on load (before user types anything)
///   - Category chips (Music, Gaming, News, etc.)
///   - Search results when user types
///   - Grid layout for thumbnails (YouTube-style)
struct YouTubeSearchView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [YouTubeSearchResult] = []
    @State private var trending: [YouTubeSearchResult] = []
    @State private var isLoading = false
    @State private var isLoadingTrending = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var selectedCategory: YouTubeCategory?

    /// Колбэк: выбранный ролик (URL + тайтл + thumbnailURL).
    /// 🔧 v33: added thumbnailURL — needed to show cover in "Смотрят сейчас" + history.
    let onSelect: (String, String, String?) -> Void

    /// Static categories (mirror of backend /media/categories)
    private let categories: [YouTubeCategory] = YouTubeCategory.all

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                VStack(spacing: 0) {
                    searchBar
                    Divider().background(Color.raveSurface)

                    // Category chips (YouTube-style horizontal scroll)
                    if !hasSearched {
                        categoryChips
                    }

                    // Content
                    if isLoading {
                        loadingState
                    } else if let errorMessage, hasSearched {
                        errorState(errorMessage)
                    } else if hasSearched && results.isEmpty {
                        emptyState
                    } else {
                        contentList
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
            .task {
                // v33: load trending on appear
                if trending.isEmpty && !hasSearched {
                    await loadTrending()
                }
            }
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
                    errorMessage = nil
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

    // MARK: - Category Chips (YouTube-style)

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        selectedCategory = category
                        if category.query.isEmpty {
                            // "Все" — show trending
                            hasSearched = false
                            results = []
                            Task { await loadTrending() }
                        } else {
                            // Search by category
                            query = category.query
                            performSearch()
                        }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedCategory?.id == category.id ? .black : .raveTextPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedCategory?.id == category.id ?
                                AnyShapeStyle(Color.ravePrimary) :
                                AnyShapeStyle(Color.raveCard)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Content List (trending or search results)

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // Section header
                if !hasSearched && !trending.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("Популярное на YouTube")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.raveTextPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                // Grid of video cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 14) {
                    let items = hasSearched ? results : trending
                    ForEach(items) { item in
                        YouTubeVideoCard(item: item) {
                            selectItem(item)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
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

    private func loadTrending() async {
        isLoadingTrending = true
        do {
            let trendingResults = try await searchService().trending()
            trending = trendingResults
        } catch {
            // Silent fail for trending — user can still search
            print("[YouTubeSearchView] Trending load failed: \(error.localizedDescription)")
        }
        isLoadingTrending = false
    }

    private func selectItem(_ item: YouTubeSearchResult) {
        // v33: forward thumbnailURL so room cards + history show cover
        onSelect(item.url, item.title, item.thumbnailURL)
        dismiss()
    }

    /// Получаем сервис из environment (DI). Fallback на дефолтный URL.
    private func searchService() -> YouTubeSearchService {
        // Используем тот же base URL что и MediaService
        YouTubeSearchService()
    }
}

// MARK: - YouTube Category Model

struct YouTubeCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String

    static let all: [YouTubeCategory] = [
        YouTubeCategory(id: "0", title: "🔥 Все", query: ""),
        YouTubeCategory(id: "10", title: "🎵 Музыка", query: "music"),
        YouTubeCategory(id: "20", title: "🎮 Игры", query: "gaming"),
        YouTubeCategory(id: "25", title: "📰 Новости", query: "news"),
        YouTubeCategory(id: "23", title: "😂 Комедии", query: "comedy"),
        YouTubeCategory(id: "24", title: "🎬 Развлечения", query: "entertainment"),
        YouTubeCategory(id: "22", title: "👥 Люди", query: "people"),
        YouTubeCategory(id: "27", title: "📚 Образование", query: "education"),
        YouTubeCategory(id: "28", title: "🔬 Наука", query: "science"),
        YouTubeCategory(id: "17", title: "⚽ Спорт", query: "sport"),
        YouTubeCategory(id: "19", title: "✈️ Путешествия", query: "travel"),
        YouTubeCategory(id: "2", title: "🚗 Авто", query: "cars"),
        YouTubeCategory(id: "1", title: "🎥 Фильмы", query: "movies"),
    ]
}

// MARK: - YouTube Video Card (grid-style, YouTube-like)

private struct YouTubeVideoCard: View {
    let item: YouTubeSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail (16:9)
                ZStack(alignment: .bottomTrailing) {
                    thumbnail
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let dur = item.formattedDuration {
                        Text(dur)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(5)
                    }
                }

                // Title + channel
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.raveTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let channel = item.channel {
                        Text(channel)
                            .font(.system(size: 11))
                            .foregroundColor(.raveTextSecondary)
                            .lineLimit(1)
                    }
                }
            }
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
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .foregroundColor(.raveTextTertiary)
                        )
                }
            }
        } else {
            Rectangle().fill(Color.raveSurface)
                .overlay(
                    Image(systemName: "play.rectangle")
                        .foregroundColor(.raveTextTertiary)
                )
        }
    }
}

// MARK: - Legacy Search Result Row (kept for backward compat)

private struct YouTubeSearchRow: View {
    let item: YouTubeSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
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
