import SwiftUI
import SwiftData
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var allItems: [MediaItem] = []
    @Published private(set) var recentlyPlayed: [MediaItem] = []
    @Published private(set) var recentlyAdded: [MediaItem] = []
    @Published private(set) var movies: [MediaItem] = []
    @Published private(set) var tvShows: [MediaItem] = []
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var isLoading = false

    @Published var filterMode: LibraryFilterMode = .region
    @Published var selectedCategory: LibraryCategory = .all
    @Published var viewMode: LibraryViewMode = .grid
    @Published var sortOption: LibrarySortOption = .addedDate

    @Published var selectedGenres: Set<String> = []
    @Published var selectedPerson: String?

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
            let fetched = try context.fetch(FetchDescriptor<MediaItem>())
            let libraryItems = fetched.filter { $0.mediaType != .tvEpisode }
            allItems = libraryItems

            recentlyPlayed = libraryItems
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                .prefix(20)
                .map { $0 }

            recentlyAdded = libraryItems
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(20)
                .map { $0 }

            movies = libraryItems.filter { $0.mediaType == .movie }
            tvShows = libraryItems.filter { $0.mediaType == .tvShow }
            favorites = libraryItems.filter { $0.isFavorite }
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

    // MARK: - Region Sections

    var regionSections: [RegionSection] {
        let baseItems = sortedItems((movies + tvShows).uniqued())
        var dict: [String: [MediaItem]] = [:]

        for item in baseItems {
            let region = CountryMapper.regionGroup(for: item.originCountry)
            let key = "\(region)-\(item.mediaType.rawValue)"
            dict[key, default: []].append(item)
        }

        let minCount = 4
        var others: [String: [MediaItem]] = [:]

        var sections = dict.compactMap { key, items -> RegionSection? in
            let parts = key.split(separator: "-", maxSplits: 1)
            guard parts.count == 2,
                  let mediaType = MediaType(rawValue: String(parts[1])) else { return nil }
            let regionName = String(parts[0])

            if items.count < minCount {
                let otherKey = mediaType.rawValue
                others[otherKey, default: []].append(contentsOf: items)
                return nil
            }

            return RegionSection(
                id: key,
                regionName: regionName,
                mediaType: mediaType,
                items: items
            )
        }

        for (typeRaw, items) in others {
            if let mediaType = MediaType(rawValue: typeRaw), !items.isEmpty {
                sections.append(RegionSection(
                    id: "其他-\(typeRaw)",
                    regionName: "其他",
                    mediaType: mediaType,
                    items: items
                ))
            }
        }

        return sections.sorted { $0.items.count > $1.items.count }
    }

    // MARK: - Genre Filtering

    var allGenres: [String] {
        let genres = allItems.flatMap(\.genres)
        var seen = Set<String>()
        return genres.filter { seen.insert($0).inserted }
    }

    var genreFilteredItems: [MediaItem] {
        guard !selectedGenres.isEmpty else {
            return sortedItems((movies + tvShows).uniqued())
        }
        let base = (movies + tvShows).uniqued()
        return sortedItems(base.filter { item in
            !selectedGenres.isDisjoint(with: item.genres)
        })
    }

    // MARK: - Person Filtering

    var topPersons: [PersonInfo] {
        var personCounts: [String: Int] = [:]

        for item in allItems {
            if let director = item.director {
                personCounts[director, default: 0] += 1
            }
            for actor in item.cast {
                personCounts[actor, default: 0] += 1
            }
        }

        return personCounts
            .sorted { $0.value > $1.value }
            .prefix(50)
            .map { PersonInfo(name: $0.key, count: $0.value, profileURL: nil) }
    }

    var personFilteredItems: [MediaItem] {
        guard let person = selectedPerson else {
            return []
        }
        let base = (movies + tvShows).uniqued()
        return sortedItems(base.filter { item in
            item.director == person || item.cast.contains(person)
        })
    }

    // MARK: - Legacy Category Filter

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
        return sortedItems(items)
    }

    // MARK: - Sorting

    private func sortedItems(_ items: [MediaItem]) -> [MediaItem] {
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

// MARK: - Supporting Types

enum LibraryFilterMode: String, CaseIterable {
    case region
    case genre
    case person

    var displayName: String {
        switch self {
        case .region: return "地区"
        case .genre: return "类型"
        case .person: return "人物"
        }
    }

    var icon: String {
        switch self {
        case .region: return "globe.asia.australia"
        case .genre: return "theatermasks"
        case .person: return "person.2"
        }
    }
}

struct RegionSection: Identifiable {
    let id: String
    let regionName: String
    let mediaType: MediaType
    let items: [MediaItem]

    var displayTitle: String {
        "\(regionName) · \(mediaType.displayName)"
    }
}

struct PersonInfo: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
    let profileURL: URL?
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
