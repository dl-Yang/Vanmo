import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacLibraryViewModel: ObservableObject {
    @Published private(set) var recentlyPlayed: [MediaItem] = []

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
    /// 本次启动是否已完成初始加载；refreshAfterLibrarySync/loadInitialSections 成功后置位，
    /// 避免冷启动 RootView 与 HomeView 两条路径重复加载。
    private var hasLoadedInitial = false
    private var hasRefreshedLiveThisLaunch = false
    private var hasRestoredHomeCacheThisLaunch = false
    /// 内部刷新锁（不发布），避免已有缓存时因 isLoadingEmbyHome 抖动触发整页刷新。
    private var isRefreshingEmbyHome = false
    /// 当前 live 刷新进行中时，后来的刷新请求合并到这里，结束后补跑一次。
    private var pendingRefreshFolderPreviews = false
    private var pendingRefreshConnections: [SavedConnection]?
    /// 当前进行中的 live 刷新是否会拉取 folder preview。
    private var isRefreshingFolderPreviews = false
    /// 本轮 live 刷新是否改动了任一 folder preview / 结构，用于决定是否落盘。
    private var homeCacheDirtyThisRefresh = false

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
        // Emby live / 磁盘缓存已按服务端 DateCreated Descending 存好，直接返回，避免因
        // 缺失 addedAt 被 sortedByNewestFirst 反转顺序。
        if let items = folderPreviews[key] {
            return items
        }
        // 本地扫描预览在写入时已按 newest 切好。
        return scannedFolderPreviews[key] ?? []
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
            try await reloadHighlights(in: context)
            try loadScannedLibraries(connections: connections, in: context)
            try loadFolderBookmarks(connections: connections, in: context)
            await restoreHomeCacheIfNeeded(connections: connections)
            updateLibraryEmptyState(connections: connections)

            if !hasRefreshedLiveThisLaunch {
                hasRefreshedLiveThisLaunch = true
                if isRefreshingEmbyHome {
                    // RootView 等路径已在刷新：仅当进行中的刷新不会拉 preview 时才排队补跑。
                    if !isRefreshingFolderPreviews {
                        pendingRefreshConnections = connections
                        pendingRefreshFolderPreviews = true
                    }
                } else {
                    refreshEmbyHomeInBackground(
                        connections: connections,
                        in: context,
                        refreshFolderPreviews: true
                    )
                }
            }

            hasLoadedInitial = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func refreshAfterLibrarySync(connections: [SavedConnection], refreshEmbyLive: Bool = true) async {
        guard let context = modelContext else { return }

        // 冷启动时 RootView 可能先于 HomeView 触发刷新：先恢复磁盘缓存，避免首屏空白/更旧数据。
        if !hasRestoredHomeCacheThisLaunch {
            await restoreHomeCacheIfNeeded(connections: connections)
        }

        do {
            if refreshEmbyLive {
                await refreshEmbyAndPersist(
                    connections: connections,
                    in: context,
                    refreshFolderPreviews: true
                )
                hasRefreshedLiveThisLaunch = true
            }
            try await reloadHighlights(in: context)
            try loadScannedLibraries(connections: connections, in: context)
            try loadFolderBookmarks(connections: connections, in: context)
            updateLibraryEmptyState(connections: connections)
            hasLoadedInitial = true
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
            try await reloadHighlights(in: context)
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
        // sectionItems 目前无 UI 消费者，这里不做主线程全量 fetch + 排序，
        // 只更新空态判断，避免每次切换 filter/section/sortOption 时卡顿。
        if let connections = currentConnectionsSnapshot() {
            updateLibraryEmptyState(connections: connections)
        }
    }

    /// 删除连接前同步剔除内存中的 MediaItem / 首页缓存，必须在 modelContext.delete + save 之前调用。
    func removeItems(forConnectionId connectionId: UUID) {
        recentlyPlayed.removeAll { item in
            guard !item.isDeleted else { return true }
            return item.sourceConnectionId == connectionId
        }
        sectionItems.removeAll { item in
            guard !item.isDeleted else { return true }
            return item.sourceConnectionId == connectionId
        }

        let keyPrefix = "\(connectionId.uuidString)::"
        folderPreviews = folderPreviews.filter { !$0.key.hasPrefix(keyPrefix) }
        folderTotalCounts = folderTotalCounts.filter { !$0.key.hasPrefix(keyPrefix) }
        scannedFolderPreviews = scannedFolderPreviews.filter { !$0.key.hasPrefix(keyPrefix) }
        scannedFolderTotalCounts = scannedFolderTotalCounts.filter { !$0.key.hasPrefix(keyPrefix) }

        serverCollectionFolders[connectionId] = nil
        embyConnectionsById[connectionId] = nil
        scannedLibraryFolders[connectionId] = nil
        scannedConnectionsById[connectionId] = nil
        serverConnectionErrors[connectionId] = nil

        folderBookmarks.removeAll { $0.connectionId == connectionId }
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
        if hasConfiguredEmbyConnections != !embyConnections.isEmpty {
            hasConfiguredEmbyConnections = !embyConnections.isEmpty
        }
        guard !embyConnections.isEmpty else {
            if !serverCollectionFolders.isEmpty { serverCollectionFolders = [:] }
            if !embyConnectionsById.isEmpty { embyConnectionsById = [:] }
            if !folderPreviews.isEmpty { folderPreviews = [:] }
            if !folderTotalCounts.isEmpty { folderTotalCounts = [:] }
            if !serverConnectionErrors.isEmpty { serverConnectionErrors = [:] }
            await homeCollectionCache.clear()
            return
        }

        if isRefreshingEmbyHome {
            // 仅当需要补跑 preview，或已有排队任务时，才更新 pending 连接列表。
            let needsFollowUp = refreshFolderPreviews && !isRefreshingFolderPreviews
            if needsFollowUp || pendingRefreshConnections != nil {
                pendingRefreshConnections = connections
                if needsFollowUp {
                    pendingRefreshFolderPreviews = true
                }
            }
            return
        }

        isRefreshingEmbyHome = true
        isRefreshingFolderPreviews = refreshFolderPreviews
        homeCacheDirtyThisRefresh = false
        // 仅在尚无缓存可展示时才把 loading 暴露给 UI，避免整页闪烁。
        if serverCollectionFolders.isEmpty {
            isLoadingEmbyHome = true
        }
        if embyHomeError != nil {
            embyHomeError = nil
        }
        defer {
            isRefreshingEmbyHome = false
            isRefreshingFolderPreviews = false
            if isLoadingEmbyHome {
                isLoadingEmbyHome = false
            }
            if let pendingConnections = pendingRefreshConnections {
                let shouldRefreshPreviews = pendingRefreshFolderPreviews
                pendingRefreshConnections = nil
                pendingRefreshFolderPreviews = false
                Task { [weak self] in
                    guard let self else { return }
                    await self.refreshEmbyAndPersist(
                        connections: pendingConnections,
                        in: context,
                        refreshFolderPreviews: shouldRefreshPreviews
                    )
                    do {
                        try await self.reloadHighlights(in: context)
                        try self.loadScannedLibraries(connections: pendingConnections, in: context)
                    } catch {
                        self.errorMessage = error.localizedDescription
                        self.showError = true
                    }
                    self.updateLibraryEmptyState(connections: pendingConnections)
                }
            }
        }

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

                applyServerFoldersIfChanged(connectionId: connection.id, folders: folders)
                applyEmbyConnectionIfNeeded(connection)
                if serverConnectionErrors[connection.id] != nil {
                    serverConnectionErrors.removeValue(forKey: connection.id)
                    homeCacheDirtyThisRefresh = true
                }

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
                if serverCollectionFolders[connection.id] != nil {
                    serverCollectionFolders.removeValue(forKey: connection.id)
                    homeCacheDirtyThisRefresh = true
                }
                applyEmbyConnectionIfNeeded(connection)
                if serverConnectionErrors[connection.id] != error.localizedDescription {
                    serverConnectionErrors[connection.id] = error.localizedDescription
                }
                VanmoLogger.network.error("[MacLibraryHome] refresh failed for \(connection.name): \(error.localizedDescription)")
            }
        }

        let activeFolderKeys = Set(foldersByServer.values.flatMap { folders in
            folders.map { folderCacheKey(for: $0) }
        })
        pruneInactiveFolderPreviews(keeping: activeFolderKeys)
        applyEmbyConnectionsIfChanged(connectionsById)
        applyServerConnectionErrorsIfChanged(errorsByServer)
        if embyHomeError != firstError {
            embyHomeError = firstError
        }

        // 未刷新 preview，或本轮没有任何结构/preview 变化时，不落盘。
        if refreshFolderPreviews, homeCacheDirtyThisRefresh {
            await persistHomeCache()
        }
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
                    let mapped = page.items.map { serverItem in
                        let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                        item.sourceConnectionId = connectionId
                        return item
                    }
                    applyFolderPreviewIfChanged(
                        key: key,
                        items: mapped,
                        totalCount: page.totalRecordCount
                    )
                } else {
                    // 请求失败：有旧数据则保留；无旧数据则写入空数组，结束骨架屏。
                    if folderPreviews[key] == nil {
                        folderPreviews[key] = []
                    }
                    VanmoLogger.network.error("[MacLibraryHome] folder preview failed for \(folderName)")
                }

                if let folder = iterator.next() {
                    submit(folder)
                    inFlight += 1
                }
            }
        }
    }

    /// 仅当 preview 内容或总数真正变化时才写入 @Published，避免整页刷新。
    private func applyFolderPreviewIfChanged(
        key: String,
        items: [MediaItem],
        totalCount: Int?
    ) {
        let existingItems = folderPreviews[key]
        let existingTotal = folderTotalCounts[key]
        let previewChanged = !arePreviewItemsEquivalent(existingItems, items)
        let totalChanged = existingTotal != totalCount

        guard previewChanged || totalChanged else {
            return
        }

        if previewChanged {
            folderPreviews[key] = items
        }
        if totalChanged {
            if let totalCount {
                folderTotalCounts[key] = totalCount
            } else {
                folderTotalCounts.removeValue(forKey: key)
            }
        }
        homeCacheDirtyThisRefresh = true
    }

    private func arePreviewItemsEquivalent(_ lhs: [MediaItem]?, _ rhs: [MediaItem]) -> Bool {
        guard let lhs else { return false }
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if !arePreviewItemsEquivalent(left, right) {
                return false
            }
        }
        return true
    }

    private func arePreviewItemsEquivalent(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        // 忽略 poster 查询串里的 api_key，以及 addedAt 精度差异，
        // 只按首页可见内容判断是否需要刷新该 folder。
        // streamURL path 变化仍视为变化，避免长期保留过期直链。
        lhs.serverId == rhs.serverId
            && lhs.title == rhs.title
            && lhs.showTitle == rhs.showTitle
            && lhs.seasonNumber == rhs.seasonNumber
            && lhs.episodeNumber == rhs.episodeNumber
            && lhs.mediaType == rhs.mediaType
            && posterPath(lhs.posterURL) == posterPath(rhs.posterURL)
            && streamPath(lhs.fileURL) == streamPath(rhs.fileURL)
            && lhs.year == rhs.year
            && lhs.rating == rhs.rating
            && abs(lhs.lastPlaybackPosition - rhs.lastPlaybackPosition) < 0.5
            && abs(lhs.duration - rhs.duration) < 0.5
    }

    private func posterPath(_ url: URL?) -> String {
        url?.path ?? ""
    }

    private func streamPath(_ url: URL) -> String {
        url.path
    }

    private func applyServerFoldersIfChanged(connectionId: UUID, folders: [CollectionFolder]) {
        if areFoldersEquivalent(serverCollectionFolders[connectionId], folders) {
            return
        }
        serverCollectionFolders[connectionId] = folders
        homeCacheDirtyThisRefresh = true
    }

    private func areFoldersEquivalent(_ lhs: [CollectionFolder]?, _ rhs: [CollectionFolder]) -> Bool {
        guard let lhs else { return false }
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.name == right.name
                && left.collectionType == right.collectionType
                && left.serverConnectionId == right.serverConnectionId
                && left.serverConnectionName == right.serverConnectionName
        }
    }

    private func applyEmbyConnectionIfNeeded(_ connection: SavedConnection) {
        if embyConnectionsById[connection.id]?.id == connection.id,
           embyConnectionsById[connection.id]?.name == connection.name {
            return
        }
        embyConnectionsById[connection.id] = connection
    }

    private func applyEmbyConnectionsIfChanged(_ connectionsById: [UUID: SavedConnection]) {
        let existingIds = Set(embyConnectionsById.keys)
        let newIds = Set(connectionsById.keys)
        guard existingIds != newIds else {
            for (_, connection) in connectionsById {
                applyEmbyConnectionIfNeeded(connection)
            }
            return
        }
        embyConnectionsById = connectionsById
    }

    private func applyServerConnectionErrorsIfChanged(_ errorsByServer: [UUID: String]) {
        guard serverConnectionErrors != errorsByServer else { return }
        serverConnectionErrors = errorsByServer
    }

    private func pruneInactiveFolderPreviews(keeping activeFolderKeys: Set<String>) {
        let stalePreviewKeys = folderPreviews.keys.filter { !activeFolderKeys.contains($0) }
        let staleTotalKeys = folderTotalCounts.keys.filter { !activeFolderKeys.contains($0) }
        guard !stalePreviewKeys.isEmpty || !staleTotalKeys.isEmpty else { return }
        for key in stalePreviewKeys {
            folderPreviews.removeValue(forKey: key)
        }
        for key in staleTotalKeys {
            folderTotalCounts.removeValue(forKey: key)
        }
        homeCacheDirtyThisRefresh = true
    }

    // MARK: - Home Collection Cache

    private func restoreHomeCacheIfNeeded(connections: [SavedConnection]) async {
        let embyConnections = embyLikeConnections(from: connections)
        hasConfiguredEmbyConnections = !embyConnections.isEmpty
        guard !embyConnections.isEmpty else {
            await homeCollectionCache.clear()
            return
        }

        // 已有内存数据或正在拉 preview 时，禁止用磁盘旧缓存覆盖，避免污染即将 persist 的快照。
        if hasRestoredHomeCacheThisLaunch {
            return
        }
        if isRefreshingEmbyHome && isRefreshingFolderPreviews {
            return
        }
        if !serverCollectionFolders.isEmpty || !folderPreviews.isEmpty {
            hasRestoredHomeCacheThisLaunch = true
            return
        }

        guard let snapshot = await homeCollectionCache.load() else {
            return
        }

        // await 之后再次校验，避免挂起期间 live 刷新已写入更新数据却被旧缓存覆盖。
        if hasRestoredHomeCacheThisLaunch
            || !serverCollectionFolders.isEmpty
            || !folderPreviews.isEmpty
            || (isRefreshingEmbyHome && isRefreshingFolderPreviews) {
            return
        }

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
                restoredPreviewsByFolder[key] = folderCache.preview.enumerated().map { index, cache in
                    let item = makePreviewItem(from: cache)
                    item.sourceConnectionId = connection.id
                    // 旧缓存没有 addedAt：按数组下标补齐，保证「越靠前越新」，
                    // 即使后续误用 sortedByNewestFirst 也不会把服务端顺序反转。
                    if cache.addedAt == nil {
                        item.addedAt = Date(timeIntervalSinceNow: -TimeInterval(index))
                    }
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

        // 旧缓存缺 addedAt：把补齐后的顺序写回磁盘，避免下次启动再踩排序坑。
        // live 刷新进行中时跳过，交给本轮/下一轮 dirty persist，避免旧快照覆盖新数据。
        let needsAddedAtBackfill = snapshot.connections.contains { connection in
            connection.folders.contains { folder in
                folder.preview.contains { $0.addedAt == nil }
            }
        }
        if needsAddedAtBackfill, !isRefreshingEmbyHome {
            await persistHomeCache()
        }
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
        if let addedAt = cache.addedAt {
            item.addedAt = addedAt
        }
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
            streamURL: item.fileURL,
            addedAt: item.addedAt
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
                try await self.reloadHighlights(in: context)
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
        let fetched = try context.fetch(descriptor).filter { bookmark in
            bookmark.deletedAt == nil && activeConnectionIds.contains(bookmark.connectionId)
        }
        // 内容未变化时跳过赋值，避免无谓的 objectWillChange 引发整页重绘。
        guard !areBookmarksEquivalent(folderBookmarks, fetched) else { return }
        folderBookmarks = fetched
    }

    private func areBookmarksEquivalent(_ lhs: [FolderBookmark], _ rhs: [FolderBookmark]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.persistentModelID == right.persistentModelID
                && left.title == right.title
                && left.path == right.path
        }
    }

    private func reloadHighlights(in context: ModelContext) async throws {
        let snapshot = try await loadHighlightSnapshot(in: context)
        recentlyPlayed = snapshot.playedIds.compactMap { id -> MediaItem? in
            guard let item = context.model(for: id) as? MediaItem, !item.isDeleted else { return nil }
            return item
        }
    }

    private func loadHighlightSnapshot(in context: ModelContext) async throws -> InitialSnapshot {
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

            return InitialSnapshot(
                playedIds: Array(playedItems.prefix(limit).map(\.persistentModelID))
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
    }

    private nonisolated static var recentlyPlayedPredicate: Predicate<MediaItem> {
        #Predicate<MediaItem> { item in
            item.lastPlayedAt != nil
        }
    }
}
