import SwiftUI
import SwiftData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [MediaItem] = []
    @Published private(set) var recentlyAdded: [MediaItem] = []
    @Published private(set) var movies: [MediaItem] = []
    @Published private(set) var tvShows: [MediaItem] = []
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published var selectedCategory: LibraryCategory = .all
    @Published var viewMode: LibraryViewMode = .grid
    @Published var sortOption: LibrarySortOption = .addedDate
    @Published var showError = false
    @Published var errorMessage = ""

    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func load() async {
        guard let context = modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let allItems = try context.fetch(FetchDescriptor<MediaItem>())

            recentlyPlayed = allItems
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                .prefix(20)
                .map { $0 }

            recentlyAdded = allItems
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(20)
                .map { $0 }

            movies = allItems.filter { $0.mediaType == .movie }
            tvShows = allItems.filter { $0.mediaType == .tvShow || $0.mediaType == .tvEpisode }
            favorites = allItems.filter { $0.isFavorite }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func toggleFavorite(_ item: MediaItem) {
        item.isFavorite.toggle()
        try? modelContext?.save()
        Task { await load() }
    }

    func markAsWatched(_ item: MediaItem) {
        item.isWatched = true
        try? modelContext?.save()
    }

    func deleteItem(_ item: MediaItem) {
        modelContext?.delete(item)
        try? modelContext?.save()
        Task { await load() }
    }

    var filteredItems: [MediaItem] {
        let items: [MediaItem]
        switch selectedCategory {
        case .all:
            items = (movies + tvShows).uniqued()
        case .movies:
            items = movies
        case .tvShows:
            items = tvShows
        case .favorites:
            items = favorites
        case .unwatched:
            items = (movies + tvShows).filter { !$0.isWatched }
        }

        switch sortOption {
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .addedDate:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .year:
            return items.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating:
            return items.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }
}

enum LibraryCategory: String, CaseIterable {
    case all, movies, tvShows, favorites, unwatched

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .movies: return "电影"
        case .tvShows: return "剧集"
        case .favorites: return "收藏"
        case .unwatched: return "未观看"
        }
    }
}

enum LibraryViewMode: String {
    case grid, list
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum LibrarySortOption: String, CaseIterable {
    case addedDate, title, year, rating

    var displayName: String {
        switch self {
        case .addedDate: return "添加日期"
        case .title: return "标题"
        case .year: return "年份"
        case .rating: return "评分"
        }
    }
}

private extension Array where Element: Identifiable {
    func uniqued() -> [Element] {
        var seen = Set<String>()
        return filter { item in
            let id = "\(item.id)"
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
    }
}
