import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacLibraryViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [MediaItem] = []
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var totalFavoritesCount = 0
    @Published private(set) var favoriteMovieCount = 0
    @Published private(set) var favoriteTVShowCount = 0

    @Published private(set) var serverCollectionFolders: [UUID: [CollectionFolder]] = [:]
    @Published private(set) var embyConnectionsById: [UUID: SavedConnection] = [:]
    @Published private(set) var folderPreviews: [String: [MediaItem]] = [:]
    @Published private(set) var folderTotalCounts: [String: Int] = [:]
    @Published private(set) var hasConfiguredEmbyConnections = false
    @Published private(set) var isLoadingEmbyHome = false
    @Published private(set) var embyHomeError: String?
    @Published private(set) var serverConnectionErrors: [UUID: String] = [:]
    @Published private(set) var scannedLibraryFolders: [UUID: [CollectionFolder]] = [:]
    @Published private(set) var scannedConnectionsById: [UUID: SavedConnection] = [:]
    @Published private(set) var scannedFolderPreviews: [String: [MediaItem]] = [:]
    @Published private(set) var scannedFolderTotalCounts: [String: Int] = [:]
    @Published private(set) var folderBookmarks: [FolderBookmark] = []

    @Published private(set) var sectionItems: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLibraryEmpty = true

    @Published var sortOption: MacLibrarySortOption = .addedDate
    @Published var showError = false
    @Published var errorMessage = ""

    private let highlightSectionLimit = 20
    private let folderPreviewPageSize = 12
    private let homeCollectionCache = MacHomeCollectionCache.shared
    private var modelContext: ModelContext?
    private var hasLoadedInitial = false
    private var hasRefreshedLiveThisLaunch = false
    private var hasRestoredHomeCacheThisLaunch = false

    var orderedEmbyConnections: [SavedConnection] {
        embyConnectionsById.values.sorted {
            ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }
    }

    var orderedScannedConnections: [SavedConnection] {
        scannedConnectionsById.values.sorted {
            ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func connection(for folder: CollectionFolder) -> SavedConnection? {
        embyConnectionsById[folder.serverConnectionId] ?? scannedConnectionsById[folder.serverConnectionId]
    }

    func isFolderPreviewLoaded(_ folder: CollectionFolder) -> Bool {
        let key = folderCacheKey(for: folder)
        return folderPreviews.keys.contains(key) || scannedFolderPreviews.keys.contains(key)
    }

    func previewItems(for folder: CollectionFolder) -> [MediaItem] {
        let key = folderCacheKey(for: folder)
        let items = folderPreviews[key] ?? scannedFolderPreviews[key] ?? []
        return sortedByNewestFirst(items)
    }

    func homeVisibleFolders(for connectionId: UUID) -> [CollectionFolder] {
        (serverCollectionFolders[connectionId] ?? []).filter(isFolderVisibleOnHome)
    }

    func homeVisibleScannedFolders(for connectionId: UUID) -> [CollectionFolder] {
        (scannedLibraryFolders[connectionId] ?? []).filter(isFolderVisibleOnHome)
    }

    func sortedSectionItems() -> [MediaItem] {
        MacLibrarySorting.sorted(sectionItems, by: sortOption)
    }

    // MARK: - Initial Load

    func loadInitialSections(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }
        guard !hasLoadedInitial else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await reloadHighlights(in: context, connections: connections)
            try loadScannedLibraries(connections: connections, in: context)
            try loadFolderBookmarks(connections: connections, in: context)
            await restoreHomeCacheIfNeeded(connections: connections)
            reloadSectionItems(filter: .all, section: .home)
            updateLibraryEmptyState(connections: connections)

            if !hasRefreshedLiveThisLaunch {
                hasRefreshedLiveThisLaunch = true
                refreshEmbyHomeInBackground(
                    connections: connections,
                    in: context,
                    refreshFolderPreviews: !hasRestoredHomeCacheThisLaunch
                )
            }

            hasLoadedInitial = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refreshAfterLibrarySync(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }

        do {
            await refreshEmbyAndPersist(
                connections: connections,
                in: context,
                refreshFolderPreviews: true
            )
            try await reloadHighlights(in: context, connections: connections)
            try loadScannedLibraries(connections: connections, in: context)
            try loadFolderBookmarks(connections: connections, in: context)
            updateLibraryEmptyState(connections: connections)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refreshEmbyHome(connections: [SavedConnection]) async {
        guard let context = modelContext else { return }
        await refreshEmbyAndPersist(
            connections: connections,
            in: context,
            refreshFolderPreviews: true
        )
        do {
            try await reloadHighlights(in: context, connections: connections)
            try loadScannedLibraries(connections: connections, in: context)
            try loadFolderBookmarks(connections: connections, in: context)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        updateLibraryEmptyState(connections: connections)
    }

    func refreshFolderBookmarks(connections: [SavedConnection]) {
        guard let context = modelContext else { return }
        do {
            try loadFolderBookmarks(connections: connections, in: context)
            updateLibraryEmptyState(connections: connections)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func reload(filter: MacLibraryFilter = .all, section: MacSidebarSection = .home) {
        reloadSectionItems(filter: filter, section: section)
        if let connections = currentConnectionsSnapshot() {
            updateLibraryEmptyState(connections: connections)
        }
    }

    func reloadSectionItems(filter: MacLibraryFilter, section: MacSidebarSection) {
        guard let modelContext else {
            sectionItems = []
            return
        }

        do {
            let items = try fetchItems(from: modelContext, filter: filter, section: section)
            sectionItems = MacLibrarySorting.sorted(items, by: sortOption)
        } catch {
            sectionItems = []
        }
    }

    // MARK: - Emby Live Refresh

    private func refreshEmbyAndPersist(
        connections: [SavedConnection],
        in context: ModelContext,
        refreshFolderPreviews: Bool = true
    ) async {
        let embyConnections = embyLikeConnections(from: connections)
        hasConfiguredEmbyConnections = !embyConnections.isEmpty
        guard !embyConnections.isEmpty else {
            serverCollectionFolders = [:]
            embyConnectionsById = [:]
            folderPreviews = [:]
            folderTotalCounts = [:]
            serverConnectionErrors = [:]
            await homeCollectionCache.clear()
            return
        }

        if isLoadingEmbyHome { return }

        isLoadingEmbyHome = true
        embyHomeError = nil
        defer { isLoadingEmbyHome = false }

        let activeConnectionIds = Set(embyConnections.map(\.id))
        var foldersByServer = serverCollectionFolders.filter { activeConnectionIds.contains($0.key) }
        var connectionsById = Dictionary(uniqueKeysWithValues: embyConnections.map { ($0.id, $0) })
        var errorsByServer = serverConnectionErrors.filter { activeConnectionIds.contains($0.key) }
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
                errorsByServer.removeValue(forKey: connection.id)

                serverCollectionFolders[connection.id] = folders
                embyConnectionsById[connection.id] = connection
                serverConnectionErrors.removeValue(forKey: connection.id)

                let liveItems = resume + serverFavorites
                if !liveItems.isEmpty {
                    do {
                        let scanner = MediaScanner(modelContainer: context.container)
                        _ = try await scanner.importServerMediaItems(
                            liveItems,
                            connectionId: connection.id,
                            in: context
                        )
                    } catch {
                        VanmoLogger.network.error(
                            "[MacLibraryHome] persist live items failed for \(connection.name): \(error.localizedDescription)"
                        )
                    }
                }

                if refreshFolderPreviews {
                    await fetchFolderPreviewsConcurrently(
                        folders: folders,
                        connection: connection,
                        service: service
                    )
                }
            } catch {
                firstError = firstError ?? error.localizedDescription
                connectionsById[connection.id] = connection
                foldersByServer.removeValue(forKey: connection.id)
                errorsByServer[connection.id] = error.localizedDescription
                serverCollectionFolders.removeValue(forKey: connection.id)
                embyConnectionsById[connection.id] = connection
                serverConnectionErrors[connection.id] = error.localizedDescription
                VanmoLogger.network.error("[MacLibraryHome] refresh failed for \(connection.name): \(error.localizedDescription)")
            }
        }

        let activeFolderKeys = Set(foldersByServer.values.flatMap { folders in
            folders.map { folderCacheKey(for: $0) }
        })
        folderPreviews = folderPreviews.filter { activeFolderKeys.contains($0.key) }
        folderTotalCounts = folderTotalCounts.filter { activeFolderKeys.contains($0.key) }

        serverCollectionFolders = foldersByServer
        embyConnectionsById = connectionsById
        serverConnectionErrors = errorsByServer
        embyHomeError = firstError
        await persistHomeCache()
    }

    private func fetchFolderPreviewsConcurrently(
        folders: [CollectionFolder],
        connection: SavedConnection,
        service: EmbyService,
        maxConcurrent: Int = 6
    ) async {
        let connectionId = connection.id
        let pageSize = folderPreviewPageSize

        await withTaskGroup(of: (String, String, ServerItemsPage?).self) { group in
            var iterator = folders.makeIterator()

            func submit(_ folder: CollectionFolder) {
                let key = folderCacheKey(for: folder)
                let folderId = folder.id
                let folderName = folder.name
                let collectionType = folder.collectionType
                group.addTask {
                    let page = try? await service.fetchCollectionFolderItems(
                        parentId: folderId,
                        collectionType: collectionType,
                        startIndex: 0,
                        pageSize: pageSize,
                        sortBy: "DateCreated",
                        sortOrder: "Descending"
                    )
                    return (key, folderName, page)
                }
            }

            var inFlight = 0
            while inFlight < maxConcurrent, let folder = iterator.next() {
                submit(folder)
                inFlight += 1
            }

            for await (key, folderName, page) in group {
                inFlight -= 1
                if let page {
                    folderPreviews[key] = page.items.map { serverItem in
                        let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                        item.sourceConnectionId = connectionId
                        return item
                    }
                    folderTotalCounts[key] = page.totalRecordCount
                } else {
                    folderPreviews[key] = []
                    VanmoLogger.network.error("[MacLibraryHome] folder preview failed for \(folderName)")
                }

                if let folder = iterator.next() {
                    submit(folder)
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Home Collection Cache

    private func restoreHomeCacheIfNeeded(connections: [SavedConnection]) async {
        let embyConnections = embyLikeConnections(from: connections)
        hasConfiguredEmbyConnections = !embyConnections.isEmpty
        guard !embyConnections.isEmpty else {
            await homeCollectionCache.clear()
            return
        }

        guard let snapshot = await homeCollectionCache.load() else { return }
        let activeConnectionsById = Dictionary(uniqueKeysWithValues: embyConnections.map { ($0.id, $0) })

        var restoredFoldersByServer: [UUID: [CollectionFolder]] = [:]
        var restoredConnectionsById: [UUID: SavedConnection] = [:]
        var restoredPreviewsByFolder: [String: [MediaItem]] = [:]
        var restoredTotalCountsByFolder: [String: Int] = [:]

        for connectionCache in snapshot.connections {
            guard let connection = activeConnectionsById[connectionCache.connectionId] else { continue }

            let folders = connectionCache.folders.map { folderCache in
                CollectionFolder(
                    id: folderCache.id,
                    name: folderCache.name,
                    collectionType: folderCache.collectionType,
                    posterURL: folderCache.posterURL,
                    serverConnectionId: connection.id,
                    serverConnectionName: connection.name
                )
            }

            guard !folders.isEmpty else { continue }
            restoredFoldersByServer[connection.id] = folders
            restoredConnectionsById[connection.id] = connection

            for folderCache in connectionCache.folders {
                let key = folderCacheKey(connectionId: connection.id, folderId: folderCache.id)
                restoredPreviewsByFolder[key] = folderCache.preview.map { cache in
                    let item = makePreviewItem(from: cache)
                    item.sourceConnectionId = connection.id
                    return item
                }
                if let totalCount = folderCache.totalCount {
                    restoredTotalCountsByFolder[key] = totalCount
                }
            }
        }

        guard !restoredFoldersByServer.isEmpty else { return }
        serverCollectionFolders = restoredFoldersByServer
        embyConnectionsById = restoredConnectionsById
        folderPreviews = restoredPreviewsByFolder
        folderTotalCounts = restoredTotalCountsByFolder
        hasRestoredHomeCacheThisLaunch = true
    }

    private func makePreviewItem(from cache: MacHomePreviewItemCache) -> MediaItem {
        let item = MediaItem(
            title: cache.title,
            fileURL: cache.streamURL,
            mediaType: MediaType(rawValue: cache.mediaType) ?? .other,
            duration: cache.duration
        )
        item.serverId = cache.serverId
        item.showTitle = cache.showTitle
        item.seasonNumber = cache.seasonNumber
        item.episodeNumber = cache.episodeNumber
        item.posterURL = cache.posterURL
        item.year = cache.year
        item.rating = cache.rating
        item.lastPlaybackPosition = cache.lastPlaybackPosition
        return item
    }

    private func persistHomeCache() async {
        let snapshot = makeHomeCacheSnapshot()
        guard !snapshot.connections.isEmpty else {
            await homeCollectionCache.clear()
            return
        }
        await homeCollectionCache.save(snapshot)
    }

    private func makeHomeCacheSnapshot() -> MacHomeCollectionCacheSnapshot {
        let connectionCaches = orderedEmbyConnections.compactMap { connection -> MacHomeConnectionCache? in
            guard let folders = serverCollectionFolders[connection.id], !folders.isEmpty else {
                return nil
            }

            let folderCaches = folders.map { folder in
                let key = folderCacheKey(for: folder)
                return MacHomeFolderCache(
                    id: folder.id,
                    name: folder.name,
                    collectionType: folder.collectionType,
                    posterURL: folder.posterURL,
                    totalCount: folderTotalCounts[key],
                    preview: (folderPreviews[key] ?? []).map(makePreviewCache)
                )
            }

            return MacHomeConnectionCache(
                connectionId: connection.id,
                connectionName: connection.name,
                folders: folderCaches
            )
        }

        return MacHomeCollectionCacheSnapshot(connections: connectionCaches)
    }

    private func makePreviewCache(from item: MediaItem) -> MacHomePreviewItemCache {
        MacHomePreviewItemCache(
            serverId: item.serverId,
            title: item.title,
            showTitle: item.showTitle,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            mediaType: item.mediaType.rawValue,
            posterURL: item.posterURL,
            year: item.year,
            rating: item.rating,
            lastPlaybackPosition: item.lastPlaybackPosition,
            duration: item.duration,
            streamURL: item.fileURL
        )
    }

    private func refreshEmbyHomeInBackground(
        connections: [SavedConnection],
        in context: ModelContext,
        refreshFolderPreviews: Bool
    ) {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshEmbyAndPersist(
                connections: connections,
                in: context,
                refreshFolderPreviews: refreshFolderPreviews
            )
            do {
                try await self.reloadHighlights(in: context, connections: connections)
                try self.loadScannedLibraries(connections: connections, in: context)
            } catch {
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
            self.updateLibraryEmptyState(connections: connections)
        }
    }

    // MARK: - SwiftData Read

    private func loadScannedLibraries(
        connections: [SavedConnection],
        in context: ModelContext
    ) throws {
        let scannedConnections = scannableConnections(from: connections)
        guard !scannedConnections.isEmpty else {
            scannedLibraryFolders = [:]
            scannedConnectionsById = [:]
            scannedFolderPreviews = [:]
            scannedFolderTotalCounts = [:]
            return
        }

        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let allItems = try context.fetch(descriptor)

        var foldersByConnection: [UUID: [CollectionFolder]] = [:]
        var connectionsById: [UUID: SavedConnection] = [:]
        var previewsByFolder: [String: [MediaItem]] = [:]
        var totalCountsByFolder: [String: Int] = [:]

        for connection in scannedConnections {
            let items = allItems.filter { $0.sourceConnectionId == connection.id }
            guard !items.isEmpty else { continue }

            var folders: [CollectionFolder] = []
            let movieItems = items.filter { $0.mediaType == .movie }
            if !movieItems.isEmpty {
                let folder = makeScannedFolder(
                    id: scannedFolderId(connectionId: connection.id, collectionType: .movies),
                    name: "电影",
                    collectionType: .movies,
                    connection: connection
                )
                folders.append(folder)
                let key = folderCacheKey(for: folder)
                previewsByFolder[key] = newestPreviewSlice(from: movieItems)
                totalCountsByFolder[key] = movieItems.count
            }

            let showItems = makeShowPreviewItems(from: items)
            if !showItems.isEmpty {
                let folder = makeScannedFolder(
                    id: scannedFolderId(connectionId: connection.id, collectionType: .tvshows),
                    name: "电视剧",
                    collectionType: .tvshows,
                    connection: connection
                )
                folders.append(folder)
                let key = folderCacheKey(for: folder)
                previewsByFolder[key] = newestPreviewSlice(from: showItems)
                totalCountsByFolder[key] = showItems.count
            }

            guard !folders.isEmpty else { continue }
            foldersByConnection[connection.id] = folders
            connectionsById[connection.id] = connection
        }

        scannedLibraryFolders = foldersByConnection
        scannedConnectionsById = connectionsById
        scannedFolderPreviews = previewsByFolder
        scannedFolderTotalCounts = totalCountsByFolder
    }

    private func loadFolderBookmarks(
        connections: [SavedConnection],
        in context: ModelContext
    ) throws {
        let activeConnectionIds = Set(connections.map(\.id))
        let descriptor = FetchDescriptor<FolderBookmark>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        folderBookmarks = try context.fetch(descriptor).filter { bookmark in
            bookmark.deletedAt == nil && activeConnectionIds.contains(bookmark.connectionId)
        }
    }

    private func reloadHighlights(
        in context: ModelContext,
        connections: [SavedConnection]
    ) async throws {
        let snapshot = try await loadHighlightSnapshot(in: context, connections: connections)
        recentlyPlayed = snapshot.playedIds.compactMap { context.model(for: $0) as? MediaItem }
        favorites = snapshot.favoriteIds.compactMap { context.model(for: $0) as? MediaItem }
        totalFavoritesCount = snapshot.favoriteTotal
        favoriteMovieCount = snapshot.favoriteMovieCount
        favoriteTVShowCount = snapshot.favoriteTVShowCount
    }

    private func loadHighlightSnapshot(
        in context: ModelContext,
        connections: [SavedConnection]
    ) async throws -> InitialSnapshot {
        let container = context.container
        let limit = highlightSectionLimit
        let hiddenConnectionIds = Set(serverConnectionErrors.keys)

        return try await Task.detached(priority: .userInitiated) {
            let bgCtx = ModelContext(container)
            func isVisibleHighlight(_ item: MediaItem) -> Bool {
                if let sourceConnectionId = item.sourceConnectionId,
                   hiddenConnectionIds.contains(sourceConnectionId) {
                    return false
                }
                return true
            }

            let playedDescriptor = FetchDescriptor<MediaItem>(
                predicate: Self.recentlyPlayedPredicate,
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
            let playedItems = try bgCtx.fetch(playedDescriptor).filter(isVisibleHighlight)
            let favoriteItems = try bgCtx.fetch(Self.favoriteDescriptor).filter(isVisibleHighlight)

            return InitialSnapshot(
                playedIds: Array(playedItems.prefix(limit).map(\.persistentModelID)),
                favoriteIds: Array(favoriteItems.prefix(limit).map(\.persistentModelID)),
                favoriteTotal: favoriteItems.count,
                favoriteMovieCount: favoriteItems.filter { $0.mediaType == .movie }.count,
                favoriteTVShowCount: favoriteItems.filter { $0.mediaType == .tvShow }.count
            )
        }.value
    }

    private func updateLibraryEmptyState(connections: [SavedConnection]) {
        let hasCollectionFolders = serverCollectionFolders.values.contains { !$0.isEmpty }
        let hasScannedLibraryFolders = scannedLibraryFolders.values.contains { !$0.isEmpty }
        let hasFolderBookmarks = !folderBookmarks.isEmpty
        let hasRelevantConnection = !connections.isEmpty
        isLibraryEmpty =
            recentlyPlayed.isEmpty &&
            favorites.isEmpty &&
            !hasCollectionFolders &&
            !hasScannedLibraryFolders &&
            !hasFolderBookmarks &&
            !hasRelevantConnection
    }

    private func isFolderVisibleOnHome(_ folder: CollectionFolder) -> Bool {
        guard folder.collectionType == .movies || folder.collectionType == .tvshows else {
            return false
        }
        let key = folderCacheKey(for: folder)
        if let total = folderTotalCounts[key] {
            return total > 0
        }
        if let total = scannedFolderTotalCounts[key] {
            return total > 0
        }
        if let preview = folderPreviews[key] {
            return !preview.isEmpty
        }
        if let preview = scannedFolderPreviews[key] {
            return !preview.isEmpty
        }
        return true
    }

    private func fetchItems(
        from context: ModelContext,
        filter: MacLibraryFilter,
        section: MacSidebarSection
    ) throws -> [MediaItem] {
        var items = try context.fetch(FetchDescriptor<MediaItem>())

        switch section {
        case .home:
            break
        case .movies:
            items = items.filter { $0.mediaType == .movie }
        case .tvShows:
            items = items.filter { $0.mediaType == .tvShow || $0.mediaType == .tvEpisode }
        case .favorites:
            items = items.filter(\.isFavorite)
        }

        switch filter {
        case .all:
            break
        case .unwatched:
            items = items.filter { !$0.isWatched }
        case .recentlyAdded:
            items = items.sorted { $0.addedAt > $1.addedAt }
        case .movies:
            items = items.filter { $0.mediaType == .movie }
        case .tvShows:
            items = items.filter { $0.mediaType == .tvShow || $0.mediaType == .tvEpisode }
        }

        return items
    }

    private func makeScannedFolder(
        id: String,
        name: String,
        collectionType: EmbyCollectionType,
        connection: SavedConnection
    ) -> CollectionFolder {
        CollectionFolder(
            id: id,
            name: name,
            collectionType: collectionType,
            posterURL: nil,
            serverConnectionId: connection.id,
            serverConnectionName: connection.name
        )
    }

    private func scannedFolderId(connectionId: UUID, collectionType: EmbyCollectionType) -> String {
        "scanned-\(connectionId.uuidString)-\(collectionType.rawValue)"
    }

    private func makeShowPreviewItems(from items: [MediaItem]) -> [MediaItem] {
        let episodeItems = items.filter { $0.mediaType == .tvEpisode || $0.mediaType == .tvShow }
        let grouped = Dictionary(grouping: episodeItems) { normalizedShowTitle(for: $0) }

        return sortedByNewestFirst(grouped.compactMap { showTitle, episodes in
            guard let representative = episodes.sorted(by: episodeSortPredicate).first else { return nil }
            let latestAddedAt = episodes.map(\.addedAt).max() ?? representative.addedAt
            let item = MediaItem(
                title: showTitle,
                fileURL: representative.fileURL,
                mediaType: .tvShow,
                fileSize: representative.fileSize,
                duration: representative.duration
            )
            item.posterURL = representative.posterURL
            item.backdropURL = representative.backdropURL
            item.year = representative.year
            item.rating = representative.rating
            item.showTitle = showTitle
            item.sourceConnectionId = representative.sourceConnectionId
            item.addedAt = latestAddedAt
            return item
        })
    }

    private func sortedByNewestFirst(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    private func newestPreviewSlice(from items: [MediaItem]) -> [MediaItem] {
        Array(sortedByNewestFirst(items).prefix(folderPreviewPageSize))
    }

    private func normalizedShowTitle(for item: MediaItem) -> String {
        let rawTitle = item.showTitle ?? item.title
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? item.displayTitle : trimmed
    }

    private func episodeSortPredicate(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let lhsSeason = lhs.seasonNumber ?? Int.max
        let rhsSeason = rhs.seasonNumber ?? Int.max
        if lhsSeason != rhsSeason {
            return lhsSeason < rhsSeason
        }

        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode {
            return lhsEpisode < rhsEpisode
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func embyLikeConnections(from connections: [SavedConnection]) -> [SavedConnection] {
        connections.filter { $0.type == .emby || $0.type == .jellyfin }
    }

    private func scannableConnections(from connections: [SavedConnection]) -> [SavedConnection] {
        connections.filter { connection in
            switch connection.type {
            case .emby, .jellyfin, .iptv:
                return false
            default:
                return true
            }
        }
    }

    private func currentConnectionsSnapshot() -> [SavedConnection]? {
        let ids = Set(embyConnectionsById.keys).union(scannedConnectionsById.keys)
        guard !ids.isEmpty else { return nil }
        return Array(embyConnectionsById.values) + Array(scannedConnectionsById.values)
    }

    private nonisolated func folderCacheKey(for folder: CollectionFolder) -> String {
        folderCacheKey(connectionId: folder.serverConnectionId, folderId: folder.id)
    }

    private nonisolated func folderCacheKey(connectionId: UUID, folderId: String) -> String {
        "\(connectionId.uuidString)::\(folderId)"
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
