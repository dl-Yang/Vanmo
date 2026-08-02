import SwiftUI
import SwiftData
import VanmoCore

struct MacMediaDetailContent {
    var enrichedOverview: String?
    var enrichedGenres: [String]
    var logoURL: URL?
    var backdropURL: URL?
    var castMembers: [CastMemberDisplay]
    var seasons: [SeasonInfo]
    var collections: [ServerMediaItem]
}

@MainActor
final class MacMediaDetailStore: ObservableObject {
    @Published private(set) var content: MacMediaDetailContent?
    @Published private(set) var isLoading = false
    @Published private(set) var selectedSeason: Int?
    @Published private(set) var seasonEpisodes: [EpisodeInfo] = []
    @Published private(set) var isLoadingEpisodes = false
    @Published private(set) var isLoadingMoreEpisodes = false
    @Published private(set) var hasMoreEpisodes = false
    @Published private(set) var episodeTotalCount = 0
    @Published private(set) var isRefreshingMetadata = false
    @Published private(set) var isUpdatingFavorite = false
    @Published private(set) var isUpdatingWatched = false
    /// 详情心形以 Store 为准：Home 临时 MediaItem 的 isFavorite 不会可靠驱动 SwiftUI 刷新。
    @Published private(set) var isFavorite = false
    @Published var favoriteErrorMessage: String?
    @Published var refreshErrorMessage: String?

    private var loadedKey: String?
    private var loadGeneration = 0
    private var episodeStartIndex = 0
    private var episodeLoadGeneration = 0
    private var metadataCacheRecord: MetadataCacheRecord?
    private var metadataRootDirectory: URL?

    private let episodePageSize = 20

    var seasonNumbers: [Int] {
        (content?.seasons ?? []).map(\.seasonNumber)
    }

    var currentSeasonEpisodes: [EpisodeInfo] {
        seasonEpisodes
    }

    var nextEpisodeToPlay: EpisodeInfo? {
        seasonEpisodes
            .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
            .first
    }

    // MARK: - Loading

    func load(item: MediaItem, modelContext: ModelContext, autoDownloadMetadata: Bool) async {
        // Home 预览项是临时对象，isFavorite 常不准；打开详情时从 SwiftData 对齐。
        syncFavoriteState(for: item, in: modelContext)

        let key = detailKey(for: item)
        guard loadedKey != key else { return }
        loadedKey = key
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        content = nil
        resetEpisodePagingState()

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: autoDownloadMetadata,
            force: false,
            generation: generation
        )
    }

    func refreshMetadata(for item: MediaItem, modelContext: ModelContext, force: Bool) async {
        guard !isRefreshingMetadata else { return }
        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: true,
            force: force,
            generation: loadGeneration
        )
    }

    func selectSeason(_ season: Int, item: MediaItem, modelContext: ModelContext) async {
        guard selectedSeason != season else { return }
        selectedSeason = season
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
    }

    func loadMoreEpisodes(item: MediaItem, modelContext: ModelContext) async {
        guard hasMoreEpisodes, !isLoadingMoreEpisodes, !isLoadingEpisodes else { return }
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: false)
    }

    /// 并行发起全部异步请求，等待全部完成后聚合成一份快照，对 UI 做一次性刷新。
    /// - Parameter generation: 本次加载的代际号，回写前校验，避免旧 item 的结果覆盖新 item。
    private func performAggregate(
        item: MediaItem,
        modelContext: ModelContext,
        autoDownloadMetadata: Bool,
        force: Bool,
        generation: Int
    ) async {
        let key = MetadataCacheKey.from(item)

        async let cacheRecordTask = MetadataCache.shared.load(for: key)
        async let networkRecordTask = fetchNetworkRecord(
            item: item,
            modelContext: modelContext,
            enabled: autoDownloadMetadata,
            force: force
        )
        async let seasonsTask = fetchSeasons(item: item, modelContext: modelContext)
        async let collectionsTask = fetchCollections(item: item, modelContext: modelContext)

        let cacheRecord = await cacheRecordTask
        let networkRecord = await networkRecordTask
        var loadedSeasons = await seasonsTask
        let loadedCollections = await collectionsTask

        // 代际 / 取消 / 已删：回写前丢弃，避免访问已 detach 的 MediaItem 属性。
        guard generation == loadGeneration, !Task.isCancelled, !item.isDeleted else {
            if generation == loadGeneration {
                isLoading = false
            }
            return
        }

        let record = networkRecord ?? cacheRecord
        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        guard generation == loadGeneration, !Task.isCancelled, !item.isDeleted else {
            if generation == loadGeneration {
                isLoading = false
            }
            return
        }

        metadataCacheRecord = record
        metadataRootDirectory = root

        if loadedSeasons.isEmpty, let record, item.mediaType == .tvShow {
            loadedSeasons = seasonInfos(from: record)
        }

        var snapshot = MacMediaDetailContent(
            enrichedOverview: nil,
            enrichedGenres: [],
            logoURL: item.logoURL,
            backdropURL: item.backdropURL,
            castMembers: [],
            seasons: loadedSeasons,
            collections: loadedCollections
        )

        if let record {
            if let overview = record.overview, !overview.isEmpty {
                snapshot.enrichedOverview = overview
                if item.overview?.isEmpty != false {
                    item.overview = overview
                }
            }
            if !record.genres.isEmpty {
                snapshot.enrichedGenres = record.genres
            }
            if let resolvedLogo = record.resolvedLogoURL(rootDirectory: root) {
                snapshot.logoURL = resolvedLogo
            }
            snapshot.castMembers = record.makeCastDisplays(rootDirectory: root)
            if let resolvedBackdrop = record.resolvedBackdropURL(rootDirectory: root) {
                snapshot.backdropURL = resolvedBackdrop
                item.backdropURL = resolvedBackdrop
            }
        }

        // 代际校验：加载期间若切换到其它 item（generation 已递增），丢弃本次结果，
        // 避免旧 item 的快照覆盖新 item，或误清新 item 的骨架态。
        guard generation == loadGeneration, !item.isDeleted else { return }

        content = snapshot
        let previousSeason = selectedSeason
        if let previousSeason, loadedSeasons.contains(where: { $0.seasonNumber == previousSeason }) {
            selectedSeason = previousSeason
        } else {
            selectedSeason = loadedSeasons.first?.seasonNumber
        }
        isLoading = false

        if item.mediaType == .tvShow, selectedSeason != nil {
            await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
        }
    }

    func invalidate() {
        loadGeneration += 1
        episodeLoadGeneration += 1
        isLoading = false
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
    }

    private func resetEpisodePagingState() {
        episodeLoadGeneration += 1
        selectedSeason = nil
        seasonEpisodes = []
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
        hasMoreEpisodes = false
        episodeTotalCount = 0
        episodeStartIndex = 0
        metadataCacheRecord = nil
        metadataRootDirectory = nil
    }

    // MARK: - Parallel fetch helpers

    private func fetchNetworkRecord(
        item: MediaItem,
        modelContext: ModelContext,
        enabled: Bool,
        force: Bool
    ) async -> MetadataCacheRecord? {
        guard enabled else { return nil }
        guard supportsMetadataRefresh(for: item, in: modelContext) else { return nil }

        do {
            let connection = try? mediaServerConnectionSnapshot(for: item, in: modelContext)
            if let draft = try await MetadataRefreshCoordinator.shared.prepareRefreshDraft(
                item,
                force: force,
                connection: connection
            ) {
                return try await MetadataCache.shared.save(draft)
            }
            return nil
        } catch {
            refreshErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func fetchSeasons(item: MediaItem, modelContext: ModelContext) async -> [SeasonInfo] {
        guard item.mediaType == .tvShow, let seriesServerId = item.serverId else { return [] }

        do {
            let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext)
            switch item.fileURL.host {
            case "plex-series":
                if let snapshot {
                    return try await PlexEpisodeFetcher.fetchSeasons(
                        seriesRatingKey: seriesServerId,
                        connection: snapshot
                    )
                }
                return try await PlexEpisodeFetcher.fetchSeasons(seriesRatingKey: seriesServerId)
            default:
                if let snapshot {
                    return try await EmbyEpisodeFetcher.fetchSeasons(
                        seriesId: seriesServerId,
                        connection: snapshot
                    )
                }
                return try await EmbyEpisodeFetcher.fetchSeasons(seriesId: seriesServerId)
            }
        } catch {
            VanmoLogger.library.error("[MacMediaDetail] Failed to load seasons: \(error.localizedDescription)")
            return []
        }
    }

    private func loadSeasonEpisodes(item: MediaItem, modelContext: ModelContext, reset: Bool) async {
        guard item.mediaType == .tvShow else { return }
        guard let season = selectedSeason else { return }

        if reset {
            episodeLoadGeneration += 1
            seasonEpisodes = []
            episodeStartIndex = 0
            episodeTotalCount = 0
            hasMoreEpisodes = false
            isLoadingEpisodes = true
            isLoadingMoreEpisodes = false
        } else {
            guard hasMoreEpisodes, !isLoadingMoreEpisodes, !isLoadingEpisodes else { return }
            isLoadingMoreEpisodes = true
        }

        let generation = episodeLoadGeneration
        let startIndex = reset ? 0 : episodeStartIndex

        defer {
            if generation == episodeLoadGeneration {
                isLoadingEpisodes = false
                isLoadingMoreEpisodes = false
            }
        }

        do {
            let page = try await fetchEpisodesPage(
                item: item,
                modelContext: modelContext,
                season: season,
                startIndex: startIndex,
                pageSize: episodePageSize
            )

            guard generation == episodeLoadGeneration, !item.isDeleted else { return }

            let merged = mergeEpisodeBackdrops(page.items, for: item)
            if reset {
                seasonEpisodes = merged
            } else {
                let existingIDs = Set(seasonEpisodes.map(\.id))
                seasonEpisodes.append(contentsOf: merged.filter { !existingIDs.contains($0.id) })
            }

            episodeStartIndex = startIndex + page.items.count
            episodeTotalCount = max(page.totalRecordCount, episodeStartIndex)
            // 满页则继续；末页不足 pageSize，或 totalSize 回退哨兵耗尽后自然停
            hasMoreEpisodes = page.items.count >= episodePageSize
                && episodeStartIndex < page.totalRecordCount
        } catch {
            VanmoLogger.library.error("[MacMediaDetail] Failed to load season episodes: \(error.localizedDescription)")
            guard generation == episodeLoadGeneration else { return }

            if reset, let fallback = cachedEpisodes(for: season, item: item), !fallback.isEmpty {
                seasonEpisodes = fallback
                episodeStartIndex = fallback.count
                episodeTotalCount = fallback.count
                hasMoreEpisodes = false
            } else if reset {
                seasonEpisodes = []
                episodeTotalCount = 0
                hasMoreEpisodes = false
            }
            // loadMore 失败保留 hasMore，便于再次滚动重试
        }
    }

    private func fetchEpisodesPage(
        item: MediaItem,
        modelContext: ModelContext,
        season: Int,
        startIndex: Int,
        pageSize: Int
    ) async throws -> EpisodePage {
        guard let seriesServerId = item.serverId else {
            throw NetworkError.notConnected
        }

        let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext)

        switch item.fileURL.host {
        case "plex-series":
            if let seasonKey = content?.seasons.first(where: { $0.seasonNumber == season })?.serverId {
                if let snapshot {
                    return try await PlexEpisodeFetcher.fetchEpisodesPage(
                        seasonRatingKey: seasonKey,
                        seasonNumber: season,
                        startIndex: startIndex,
                        pageSize: pageSize,
                        connection: snapshot
                    )
                }
                return try await PlexEpisodeFetcher.fetchEpisodesPage(
                    seasonRatingKey: seasonKey,
                    seasonNumber: season,
                    startIndex: startIndex,
                    pageSize: pageSize
                )
            }

            // cache 季列表无 ratingKey 时回退：拉全量再按季切片
            let all: [EpisodeInfo]
            if let snapshot {
                all = try await PlexEpisodeFetcher.fetchEpisodes(
                    seriesRatingKey: seriesServerId,
                    connection: snapshot
                )
            } else {
                all = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: seriesServerId)
            }
            let filtered = all
                .filter { $0.seasonNumber == season }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            let slice = Array(filtered.dropFirst(startIndex).prefix(pageSize))
            return EpisodePage(items: slice, totalRecordCount: filtered.count)
        default:
            if let snapshot {
                return try await EmbyEpisodeFetcher.fetchEpisodesPage(
                    seriesId: seriesServerId,
                    season: season,
                    startIndex: startIndex,
                    pageSize: pageSize,
                    connection: snapshot
                )
            }
            return try await EmbyEpisodeFetcher.fetchEpisodesPage(
                seriesId: seriesServerId,
                season: season,
                startIndex: startIndex,
                pageSize: pageSize
            )
        }
    }

    private func fetchCollections(item: MediaItem, modelContext: ModelContext) async -> [ServerMediaItem] {
        guard let serverId = item.serverId, item.mediaType != .boxSet else { return [] }

        do {
            if let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext) {
                guard snapshot.type == .emby || snapshot.type == .jellyfin else { return [] }
                return try await EmbyCollectionsFetcher.fetchCollections(containing: serverId, connection: snapshot)
            } else if isEmbyOriginItem(item) {
                return try await EmbyCollectionsFetcher.fetchCollections(containing: serverId)
            } else {
                return []
            }
        } catch {
            VanmoLogger.library.error("[MacMediaDetail] Failed to load collections: \(error.localizedDescription)")
            return []
        }
    }

    private func seasonInfos(from record: MetadataCacheRecord) -> [SeasonInfo] {
        Array(Set(record.episodes.map(\.seasonNumber)))
            .sorted()
            .map { SeasonInfo(seasonNumber: $0) }
    }

    private func cachedEpisodes(for season: Int, item: MediaItem) -> [EpisodeInfo]? {
        guard let record = metadataCacheRecord,
              let root = metadataRootDirectory,
              item.mediaType == .tvShow,
              !record.episodes.isEmpty else {
            return nil
        }
        return record.episodes
            .filter { $0.seasonNumber == season }
            .map { $0.makeEpisodeInfo(rootDirectory: root) }
            .sorted { $0.episodeNumber < $1.episodeNumber }
    }

    private func mergeEpisodeBackdrops(_ loaded: [EpisodeInfo], for item: MediaItem) -> [EpisodeInfo] {
        guard let record = metadataCacheRecord,
              let root = metadataRootDirectory,
              item.mediaType == .tvShow,
              !record.episodes.isEmpty else {
            return loaded
        }

        let cachedByID = Dictionary(record.episodes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return loaded.map { episode in
            guard episode.backdropURL == nil, let cached = cachedByID[episode.id] else {
                return episode
            }
            let cachedEpisode = cached.makeEpisodeInfo(rootDirectory: root)
            return EpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropURL: cachedEpisode.backdropURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath
            )
        }
    }

    // MARK: - User actions

    func toggleFavorite(for item: MediaItem, modelContext: ModelContext) async {
        guard !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }

        let targetFavorite = !isFavorite

        do {
            if item.serverId != nil {
                try await EmbyFavoriteUpdater.setFavorite(
                    item,
                    isFavorite: targetFavorite,
                    connection: try? mediaServerConnectionSnapshot(for: item, in: modelContext)
                )
            }
            try persistFavoriteState(
                for: item,
                isFavorite: targetFavorite,
                in: modelContext
            )
            if item.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.markMediaFavoriteChanged(item, in: modelContext)
            }
            try modelContext.save()
            if item.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.requestSync(reason: "favorite", context: modelContext)
            }
            isFavorite = targetFavorite
            NotificationCenter.default.post(name: .mediaFavoriteDidChange, object: item.id)
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }

    /// Home 文件夹预览等入口的 MediaItem 可能未插入 SwiftData；仅改内存对象无法被 Favorites 查询到。
    /// 对齐 iOS `updateStoredFavoriteState`：按 serverId 更新已存记录，必要时 insert。
    private func persistFavoriteState(
        for item: MediaItem,
        isFavorite: Bool,
        in modelContext: ModelContext
    ) throws {
        item.isFavorite = isFavorite

        guard let serverId = item.serverId else {
            if item.modelContext == nil, isFavorite {
                modelContext.insert(item)
            }
            return
        }

        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId &&
                    mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        if let storedItem = try modelContext.fetch(descriptor).first {
            storedItem.isFavorite = isFavorite
            return
        }

        if isFavorite {
            modelContext.insert(item)
        }
    }

    /// 将详情页临时 MediaItem 的收藏状态与 SwiftData 中同 serverId 记录对齐。
    private func syncFavoriteState(for item: MediaItem, in modelContext: ModelContext) {
        guard let serverId = item.serverId else {
            isFavorite = item.isFavorite
            return
        }

        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId &&
                    mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        guard let storedItem = try? modelContext.fetch(descriptor).first else {
            isFavorite = item.isFavorite
            return
        }

        item.isFavorite = storedItem.isFavorite
        isFavorite = storedItem.isFavorite
    }

    func toggleWatched(for item: MediaItem, modelContext: ModelContext) async {
        guard !isUpdatingWatched else { return }
        isUpdatingWatched = true
        defer { isUpdatingWatched = false }

        item.isWatched.toggle()
        if item.isWatched {
            item.lastPlaybackPosition = item.duration > 0 ? item.duration : item.lastPlaybackPosition
            item.lastPlayedAt = Date()
        } else {
            item.lastPlaybackPosition = 0
        }

        if item.serverId != nil {
            do {
                try await EmbyPlayedUpdater.setPlayed(
                    item,
                    isPlayed: item.isWatched,
                    connection: try? mediaServerConnectionSnapshot(for: item, in: modelContext)
                )
            } catch {
                VanmoLogger.network.error(
                    "[EmbyPlayback] toggle watched failed: \(error.localizedDescription)"
                )
            }
        }

        if item.isProgressCloudSynced {
            CloudSyncCoordinator.shared.markMediaProgressChanged(item, in: modelContext)
            try? modelContext.save()
            CloudSyncCoordinator.shared.requestSync(reason: "watched", context: modelContext)
        } else {
            try? modelContext.save()
        }
    }

    // MARK: - Item factory

    func makeCollectionItem(_ collection: ServerMediaItem, sourceConnectionId: UUID?) -> MediaItem {
        let collectionItem = ServerMediaItemMapper.makeMediaItem(from: collection)
        collectionItem.sourceConnectionId = sourceConnectionId
        return collectionItem
    }

    func makeEpisodeItem(from episode: EpisodeInfo, show: MediaItem) -> MediaItem {
        let episodeItem = MediaItem(
            title: show.title,
            fileURL: episode.streamURL,
            mediaType: .tvEpisode,
            duration: episode.duration
        )
        episodeItem.showTitle = show.showTitle ?? show.title
        episodeItem.seasonNumber = episode.seasonNumber
        episodeItem.episodeNumber = episode.episodeNumber
        episodeItem.episodeTitle = episode.title
        episodeItem.posterURL = show.posterURL
        episodeItem.backdropURL = episode.backdropURL ?? show.backdropURL
        episodeItem.serverId = episode.id
        episodeItem.seriesId = show.serverId ?? show.seriesId
        episodeItem.sourceConnectionId = show.sourceConnectionId
        return episodeItem
    }

    // MARK: - Support

    private func detailKey(for item: MediaItem) -> String {
        if let serverId = item.serverId {
            return "server:\(serverId)"
        }
        return "local:\(item.id.uuidString)"
    }

    private func supportsMetadataRefresh(for item: MediaItem, in modelContext: ModelContext) -> Bool {
        if (try? mediaServerConnectionSnapshot(for: item, in: modelContext)) != nil {
            return true
        }
        return MetadataRefreshCoordinator.supportsRefresh(for: item)
    }

    private func mediaServerConnectionSnapshot(
        for item: MediaItem,
        in modelContext: ModelContext
    ) throws -> MediaServerConnectionSnapshot? {
        try MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
    }

    private func isEmbyOriginItem(_ item: MediaItem) -> Bool {
        if item.fileURL.scheme == "vanmo" {
            switch item.fileURL.host?.lowercased() {
            case "series", "emby-container", "emby-item":
                return true
            default:
                return false
            }
        }
        guard let baseHost = EmbyCredentialStore.baseURL.flatMap({ URL(string: $0)?.host?.lowercased() }),
              let itemHost = item.fileURL.host?.lowercased() else {
            return false
        }
        return baseHost == itemHost
    }
}

extension Notification.Name {
    /// 与 iOS 共用通知名字符串。Mac 端 `object` 传 `MediaItem.id`（UUID）；接收方当前忽略 object。
    static let mediaFavoriteDidChange = Notification.Name("mediaFavoriteDidChange")
}
