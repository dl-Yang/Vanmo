import SwiftUI
import SwiftData

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [MediaItem] = []
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var totalFavoritesCount = 0
    @Published private(set) var favoriteMovieCount = 0
    @Published private(set) var favoriteTVShowCount = 0

    @Published private(set) var serverCollectionFolders: [UUID: [CollectionFolder]] = [:]
    @Published private(set) var embyConnectionsById: [UUID: SavedConnection] = [:]
    @Published private(set) var hasConfiguredEmbyConnections = false
    @Published private(set) var isLoadingEmbyHome = false
    @Published private(set) var embyHomeError: String?

    @Published private(set) var isLoading = false
    @Published private(set) var isLibraryEmpty = true

    @Published var viewMode: LibraryViewMode = .grid
    @Published var sortOption: LibrarySortOption = .addedDate
    @Published var selectedGenres: Set<String> = []
    @Published var selectedRegions: Set<String> = []

    @Published var showError = false
    @Published var errorMessage = ""

    private let highlightSectionLimit = 20
    private var modelContext: ModelContext?
    private var hasLoadedInitial = false
    /// App 启动后是否已经向 Emby 拉过一次 live 数据并写入 SwiftData。
    /// 真值表示后续进入首页 / 切 tab 时不再触发网络请求。
    private var hasRefreshedLiveThisLaunch = false

    var orderedEmbyConnections: [SavedConnection] {
        embyConnectionsById.values.sorted {
            ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }
    }

    var hasActiveFilters: Bool {
        !selectedGenres.isEmpty || !selectedRegions.isEmpty
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func connection(for folder: CollectionFolder) -> SavedConnection? {
        embyConnectionsById[folder.serverConnectionId]
    }

    // MARK: - Initial Load

    /// 首页进入时调用。首次启动会拉一次 live 数据写入 SwiftData，再读 SwiftData；
    /// 之后切 tab 重新进入会立即返回，避免重复刷新闪烁。
    func loadInitialSections(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }

        if hasLoadedInitial {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await reloadHighlights(in: context)

            if !hasRefreshedLiveThisLaunch {
                hasRefreshedLiveThisLaunch = true
                await refreshEmbyAndPersist(connections: connections, in: context)
                try await reloadHighlights(in: context)
            }

            hasLoadedInitial = true
            updateLibraryEmptyState(connections: connections)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 数据同步完成后（用户新连接服务器）重读 SwiftData，并对 Emby 服务器再做一次 live 刷新。
    func refreshAfterLibrarySync(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }

        do {
            await refreshEmbyAndPersist(connections: connections, in: context)
            try await reloadHighlights(in: context)
            updateLibraryEmptyState(connections: connections)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 用户下拉刷新触发：强制重新拉取 live 数据并刷新 SwiftData。
    func refreshEmbyHome(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }
        await refreshEmbyAndPersist(connections: connections, in: context)
        do {
            try await reloadHighlights(in: context)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        updateLibraryEmptyState(connections: connections)
    }

    // MARK: - Emby Live Refresh + Persist

    private func refreshEmbyAndPersist(
        connections: [SavedConnection],
        in context: ModelContext
    ) async {
        let embyConnections = connections.filter { $0.type == .emby || $0.type == .jellyfin }
        hasConfiguredEmbyConnections = !embyConnections.isEmpty
        guard !embyConnections.isEmpty else {
            serverCollectionFolders = [:]
            embyConnectionsById = [:]
            return
        }

        isLoadingEmbyHome = true
        embyHomeError = nil
        defer { isLoadingEmbyHome = false }

        var foldersByServer: [UUID: [CollectionFolder]] = [:]
        var connectionsById: [UUID: SavedConnection] = [:]
        var allLiveItems: [ServerMediaItem] = []
        var firstError: String?

        for connection in embyConnections {
            do {
                let service = try await EmbyConnectionHelper.connect(connection)
                defer { Task { await service.disconnect() } }

                let folders = try await service.fetchVirtualFolders(
                    connectionId: connection.id,
                    connectionName: connection.name
                )
                let resume = try await service.fetchResumeItems(limit: highlightSectionLimit)
                let serverFavorites = try await service.fetchFavoriteItems()

                connectionsById[connection.id] = connection
                foldersByServer[connection.id] = folders
                allLiveItems.append(contentsOf: resume)
                allLiveItems.append(contentsOf: serverFavorites)
            } catch {
                firstError = firstError ?? error.localizedDescription
                VanmoLogger.network.error("[LibraryHome] refresh failed for \(connection.name): \(error.localizedDescription)")
            }
        }

        serverCollectionFolders = foldersByServer
        embyConnectionsById = connectionsById
        embyHomeError = firstError

        if !allLiveItems.isEmpty {
            do {
                let scanner = MediaScanner(modelContainer: context.container)
                _ = try await scanner.importServerMediaItems(allLiveItems, in: context)
            } catch {
                VanmoLogger.network.error("[LibraryHome] persist live items failed: \(error.localizedDescription)")
            }
        }
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
    }

    // MARK: - SwiftData Read

    private func reloadHighlights(in context: ModelContext) async throws {
        let snapshot = try await loadHighlightSnapshot(in: context)
        recentlyPlayed = snapshot.playedIds.compactMap { context.model(for: $0) as? MediaItem }
        favorites = snapshot.favoriteIds.compactMap { context.model(for: $0) as? MediaItem }
        totalFavoritesCount = snapshot.favoriteTotal
        favoriteMovieCount = snapshot.favoriteMovieCount
        favoriteTVShowCount = snapshot.favoriteTVShowCount
    }

    private func loadHighlightSnapshot(in context: ModelContext) async throws -> InitialSnapshot {
        let container = context.container
        let limit = highlightSectionLimit

        return try await Task.detached(priority: .userInitiated) {
            let bgCtx = ModelContext(container)

            // 继续观看：lastPlayedAt 非空即视为可恢复播放，不再额外按 mediaType 过滤，
            // 让 Emby resume API 返回的 Episode 也能进入这个区。
            var playedDescriptor = FetchDescriptor<MediaItem>(
                predicate: Self.recentlyPlayedPredicate,
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
            playedDescriptor.fetchLimit = limit
            let playedIds = try bgCtx.fetch(playedDescriptor).map(\.persistentModelID)

            let favoriteItems = try bgCtx.fetch(Self.favoriteDescriptor)

            return InitialSnapshot(
                playedIds: playedIds,
                favoriteIds: Array(favoriteItems.prefix(limit).map(\.persistentModelID)),
                favoriteTotal: favoriteItems.count,
                favoriteMovieCount: favoriteItems.filter { $0.mediaType == .movie }.count,
                favoriteTVShowCount: favoriteItems.filter { $0.mediaType == .tvShow }.count
            )
        }.value
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

    private func updateLibraryEmptyState(connections: [SavedConnection]) {
        let hasCollectionFolders = serverCollectionFolders.values.contains { !$0.isEmpty }
        let hasAnyConnection = !connections.isEmpty
        isLibraryEmpty =
            recentlyPlayed.isEmpty &&
            favorites.isEmpty &&
            !hasCollectionFolders &&
            !hasAnyConnection
    }

    private struct InitialSnapshot: Sendable {
        let playedIds: [PersistentIdentifier]
        let favoriteIds: [PersistentIdentifier]
        let favoriteTotal: Int
        let favoriteMovieCount: Int
        let favoriteTVShowCount: Int
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
