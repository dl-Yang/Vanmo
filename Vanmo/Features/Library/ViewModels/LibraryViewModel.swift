import SwiftUI
import SwiftData

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [MediaItem] = []
    @Published private(set) var recentlyAdded: [MediaItem] = []
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var totalFavoritesCount = 0
    @Published private(set) var favoriteMovieCount = 0
    @Published private(set) var favoriteTVShowCount = 0
    @Published private(set) var loadedItems: [MediaItem] = []

    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isReloadingSection = false
    @Published private(set) var hasMore = true
    @Published private(set) var isLibraryEmpty = true

    @Published var viewMode: LibraryViewMode = .grid
    @Published var sortOption: LibrarySortOption = .addedDate
    @Published var section: LibrarySection = .movie
    @Published var selectedGenres: Set<String> = []
    @Published var selectedRegions: Set<String> = []

    @Published var showError = false
    @Published var errorMessage = ""

    private let pageSize = 30
    private let highlightSectionLimit = 20
    private var dbOffset = 0
    private var modelContext: ModelContext?
    private var loadedItemIDs: Set<PersistentIdentifier> = []
    private var hasLoadedInitial = false

    var hasActiveFilters: Bool {
        !selectedGenres.isEmpty || !selectedRegions.isEmpty
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Initial Load

    func loadInitialSections() async {
        guard let context = modelContext else { return }
        let isFirstLoad = !hasLoadedInitial
        if isFirstLoad {
            isLoading = true
        }
        defer {
            if isFirstLoad {
                isLoading = false
            }
        }

        if isFirstLoad {
            resetPagedItems()
        }

        let container = context.container
        let limit = highlightSectionLimit

        do {
            let snapshot: InitialSnapshot = try await Task.detached(priority: .userInitiated) {
                let bgCtx = ModelContext(container)

                var addedDescriptor = FetchDescriptor<MediaItem>(
                    sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
                )
                addedDescriptor.fetchLimit = limit * 3
                let addedIds = try bgCtx.fetch(addedDescriptor)
                    .filter { $0.mediaType != .tvEpisode }
                    .prefix(limit)
                    .map(\.persistentModelID)

                var playedDescriptor = FetchDescriptor<MediaItem>(
                    predicate: Self.recentlyPlayedPredicate,
                    sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
                )
                playedDescriptor.fetchLimit = limit * 3
                let playedIds = try bgCtx.fetch(playedDescriptor)
                    .filter { $0.mediaType != .tvEpisode }
                    .prefix(limit)
                    .map(\.persistentModelID)

                let favoriteItems = try bgCtx.fetch(Self.favoriteDescriptor)
                    .filter { $0.mediaType != .tvEpisode }

                return InitialSnapshot(
                    addedIds: Array(addedIds),
                    playedIds: Array(playedIds),
                    favoriteIds: Array(favoriteItems.prefix(limit).map(\.persistentModelID)),
                    favoriteTotal: favoriteItems.count,
                    favoriteMovieCount: favoriteItems.filter { $0.mediaType == .movie }.count,
                    favoriteTVShowCount: favoriteItems.filter { $0.mediaType == .tvShow }.count
                )
            }.value

            recentlyAdded = snapshot.addedIds.compactMap { context.model(for: $0) as? MediaItem }
            recentlyPlayed = snapshot.playedIds.compactMap { context.model(for: $0) as? MediaItem }
            favorites = snapshot.favoriteIds.compactMap { context.model(for: $0) as? MediaItem }
            totalFavoritesCount = snapshot.favoriteTotal
            favoriteMovieCount = snapshot.favoriteMovieCount
            favoriteTVShowCount = snapshot.favoriteTVShowCount

            if isFirstLoad {
                try await loadFirstPage()
                hasLoadedInitial = true
            }
            isLibraryEmpty = recentlyAdded.isEmpty && recentlyPlayed.isEmpty && favorites.isEmpty && loadedItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Filter Updates

    func changeSection(_ newSection: LibrarySection) async {
        guard section != newSection else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            section = newSection
        }
        await reloadPagedItems()
    }

    func reloadForSortChange() async {
        await reloadPagedItems()
    }

    func reloadForFilterChange() async {
        await reloadPagedItems()
    }

    private func reloadPagedItems() async {
        guard modelContext != nil else { return }
        isReloadingSection = true
        defer { isReloadingSection = false }

        resetPagedItems()

        do {
            try await loadFirstPage()
            isLibraryEmpty = recentlyAdded.isEmpty && recentlyPlayed.isEmpty && favorites.isEmpty && loadedItems.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Pagination

    func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard hasMore, !isLoadingMore, !isLoading, !isReloadingSection else { return }
        let threshold = 5
        guard let index = loadedItems.firstIndex(where: { $0.id == item.id }) else { return }
        if index >= loadedItems.count - threshold {
            await loadNextPage()
        }
    }

    private func loadFirstPage() async throws {
        let result = try await fetchNextBatch(startDBOffset: 0)
        let items = result.ids.compactMap { modelContext?.model(for: $0) as? MediaItem }
        appendItems(items)
        dbOffset = result.dbScanned
        hasMore = !result.reachedEnd
    }

    func loadNextPage() async {
        guard modelContext != nil, hasMore, !isLoadingMore, !isReloadingSection else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetchNextBatch(startDBOffset: dbOffset)
            let items = result.ids.compactMap { modelContext?.model(for: $0) as? MediaItem }
            appendItems(items)
            dbOffset += result.dbScanned
            hasMore = !result.reachedEnd
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 从指定数据库偏移开始扫描，过滤后累积到一页数据。
    /// SwiftData 对数组字段和枚举常量的复杂 predicate 支持有限，这里保留数据库分页扫描，
    /// 再在后台上下文内完成 mediaType / genre AND / region OR 过滤。
    private func fetchNextBatch(startDBOffset: Int) async throws -> BatchResult {
        guard let context = modelContext else {
            return BatchResult(ids: [], dbScanned: 0, reachedEnd: true)
        }
        let container = context.container
        let query = LibraryQuery(
            section: section,
            selectedGenres: selectedGenres,
            selectedRegions: selectedRegions,
            sortOption: sortOption
        )
        let target = pageSize
        let batchSize = pageSize * 2

        return try await Task.detached(priority: .userInitiated) {
            let bgCtx = ModelContext(container)
            var collectedIds: [PersistentIdentifier] = []
            var dbScanned = 0
            var reachedEnd = false

            while collectedIds.count < target {
                var descriptor = FetchDescriptor<MediaItem>(
                    sortBy: Self.sortDescriptors(for: query.sortOption)
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = startDBOffset + dbScanned

                let batch = try bgCtx.fetch(descriptor)
                if batch.isEmpty {
                    reachedEnd = true
                    break
                }

                dbScanned += batch.count
                let filtered = batch.filter { Self.matchesQuery($0, query: query) }
                collectedIds.append(contentsOf: filtered.map(\.persistentModelID))

                if batch.count < batchSize {
                    reachedEnd = true
                    break
                }
            }

            return BatchResult(ids: collectedIds, dbScanned: dbScanned, reachedEnd: reachedEnd)
        }.value
    }

    // MARK: - Item Actions

    func toggleFavorite(_ item: MediaItem) {
        item.isFavorite.toggle()
        try? modelContext?.save()
        updateFavoriteSnapshot(afterToggling: item)
    }

    func markAsWatched(_ item: MediaItem) {
        item.isWatched = true
        try? modelContext?.save()
    }

    func deleteItem(_ item: MediaItem) {
        let wasFavorite = item.isFavorite
        modelContext?.delete(item)
        try? modelContext?.save()

        loadedItemIDs.remove(item.persistentModelID)
        loadedItems.removeAll { $0.id == item.id }
        recentlyAdded.removeAll { $0.id == item.id }
        recentlyPlayed.removeAll { $0.id == item.id }
        favorites.removeAll { $0.id == item.id }
        if wasFavorite {
            totalFavoritesCount = max(0, totalFavoritesCount - 1)
            if item.mediaType == .movie {
                favoriteMovieCount = max(0, favoriteMovieCount - 1)
            } else if item.mediaType == .tvShow {
                favoriteTVShowCount = max(0, favoriteTVShowCount - 1)
            }
        }
        isLibraryEmpty = recentlyAdded.isEmpty && recentlyPlayed.isEmpty && favorites.isEmpty && loadedItems.isEmpty
    }

    // MARK: - Internals

    private func resetPagedItems() {
        dbOffset = 0
        hasMore = true
        loadedItems = []
        loadedItemIDs = []
    }

    private func appendItems(_ items: [MediaItem]) {
        for item in items where loadedItemIDs.insert(item.persistentModelID).inserted {
            loadedItems.append(item)
        }
    }

    private func updateFavoriteSnapshot(afterToggling item: MediaItem) {
        if item.isFavorite {
            totalFavoritesCount += favorites.contains(where: { $0.id == item.id }) ? 0 : 1
            if item.mediaType == .movie {
                favoriteMovieCount += 1
            } else if item.mediaType == .tvShow {
                favoriteTVShowCount += 1
            }
            favorites.removeAll { $0.id == item.id }
            favorites.insert(item, at: 0)
            if favorites.count > highlightSectionLimit {
                favorites.removeLast(favorites.count - highlightSectionLimit)
            }
        } else {
            totalFavoritesCount = max(0, totalFavoritesCount - 1)
            if item.mediaType == .movie {
                favoriteMovieCount = max(0, favoriteMovieCount - 1)
            } else if item.mediaType == .tvShow {
                favoriteTVShowCount = max(0, favoriteTVShowCount - 1)
            }
            favorites.removeAll { $0.id == item.id }
        }
    }

    private struct InitialSnapshot: Sendable {
        let addedIds: [PersistentIdentifier]
        let playedIds: [PersistentIdentifier]
        let favoriteIds: [PersistentIdentifier]
        let favoriteTotal: Int
        let favoriteMovieCount: Int
        let favoriteTVShowCount: Int
    }

    private struct BatchResult: Sendable {
        let ids: [PersistentIdentifier]
        let dbScanned: Int
        let reachedEnd: Bool
    }

    private struct LibraryQuery: Sendable {
        let section: LibrarySection
        let selectedGenres: Set<String>
        let selectedRegions: Set<String>
        let sortOption: LibrarySortOption
    }

    private nonisolated static var recentlyPlayedPredicate: Predicate<MediaItem> {
        #Predicate<MediaItem> { item in
            item.lastPlayedAt != nil
        }
    }

    private nonisolated static var favoriteDescriptor: FetchDescriptor<MediaItem> {
        FetchDescriptor(
            predicate: #Predicate<MediaItem> { item in
                item.isFavorite
            },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
    }

    private nonisolated static func sortDescriptors(for option: LibrarySortOption) -> [SortDescriptor<MediaItem>] {
        switch option {
        case .title:
            return [SortDescriptor(\.title, order: .forward)]
        case .addedDate:
            return [SortDescriptor(\.addedAt, order: .reverse)]
        case .year:
            return [SortDescriptor(\.year, order: .reverse)]
        case .rating:
            return [SortDescriptor(\.rating, order: .reverse)]
        }
    }

    private nonisolated static func matchesQuery(_ item: MediaItem, query: LibraryQuery) -> Bool {
        item.mediaType == query.section.mediaType
            && matchesGenres(item, selectedGenres: query.selectedGenres)
            && matchesRegions(item, selectedRegions: query.selectedRegions)
    }

    private nonisolated static func matchesGenres(_ item: MediaItem, selectedGenres: Set<String>) -> Bool {
        guard !selectedGenres.isEmpty else { return true }
        let itemGenres = Set(item.genres)
        return selectedGenres.allSatisfy { selectedGenre in
            !LibraryFilters.aliases(for: selectedGenre).isDisjoint(with: itemGenres)
        }
    }

    private nonisolated static func matchesRegions(_ item: MediaItem, selectedRegions: Set<String>) -> Bool {
        guard !selectedRegions.isEmpty else { return true }
        guard !item.originCountry.isEmpty else { return false }

        let itemCodes = Set(item.originCountry.map { $0.uppercased() })
        let selectedFilters = selectedRegions.compactMap(LibraryFilters.region(for:))
        let selectedCodes = selectedFilters.reduce(into: Set<String>()) { result, region in
            guard !region.isOther else { return }
            result.formUnion(region.isoCodes)
        }

        if !selectedCodes.isDisjoint(with: itemCodes) {
            return true
        }

        guard selectedFilters.contains(where: \.isOther) else {
            return false
        }

        return !itemCodes.isSubset(of: LibraryFilters.allRegionCodes)
    }
}

// MARK: - Supporting Types

enum LibraryViewMode: String, Sendable {
    case grid, list
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum LibrarySortOption: String, CaseIterable, Sendable {
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
