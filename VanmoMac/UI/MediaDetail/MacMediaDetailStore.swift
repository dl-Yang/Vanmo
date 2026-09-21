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
final class MacMediaDetailSummaryState: ObservableObject {
    @Published var content: MacMediaDetailContent?
    @Published var isLoading = false
}

@MainActor
final class MacMediaDetailCastState: ObservableObject {
    @Published var members: [CastMemberDisplay] = []
}

@MainActor
final class MacMediaDetailCollectionState: ObservableObject {
    @Published var items: [ServerMediaItem] = []
}

@MainActor
final class MacMediaDetailEpisodeState: ObservableObject {
    @Published var seasons: [SeasonInfo] = []
    @Published var selectedSeason: Int?
    @Published var episodes: [EpisodeInfo] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = false
    @Published var totalCount = 0
}

@MainActor
final class MacMediaDetailActionState: ObservableObject {
    @Published var isRefreshingMetadata = false
    @Published var refreshErrorMessage: String?
}

@MainActor
final class MacMediaDetailStore: ObservableObject {
    let summaryState = MacMediaDetailSummaryState()
    let castState = MacMediaDetailCastState()
    let collectionState = MacMediaDetailCollectionState()
    let episodeState = MacMediaDetailEpisodeState()
    let actionState = MacMediaDetailActionState()

    var content: MacMediaDetailContent? {
        get {
            guard var value = summaryState.content else { return nil }
            value.castMembers = castState.members
            value.seasons = episodeState.seasons
            value.collections = collectionState.items
            return value
        }
        set {
            summaryState.content = newValue.map {
                MacMediaDetailContent(
                    enrichedOverview: $0.enrichedOverview,
                    enrichedGenres: $0.enrichedGenres,
                    logoURL: $0.logoURL,
                    backdropURL: $0.backdropURL,
                    castMembers: [],
                    seasons: [],
                    collections: []
                )
            }
            castState.members = newValue?.castMembers ?? []
            episodeState.seasons = newValue?.seasons ?? []
            collectionState.items = newValue?.collections ?? []
        }
    }

    var isLoading: Bool {
        get { summaryState.isLoading }
        set { summaryState.isLoading = newValue }
    }

    var selectedSeason: Int? {
        get { episodeState.selectedSeason }
        set { episodeState.selectedSeason = newValue }
    }

    var seasonEpisodes: [EpisodeInfo] {
        get { episodeState.episodes }
        set { episodeState.episodes = newValue }
    }

    var isLoadingEpisodes: Bool {
        get { episodeState.isLoading }
        set { episodeState.isLoading = newValue }
    }

    var isLoadingMoreEpisodes: Bool {
        get { episodeState.isLoadingMore }
        set { episodeState.isLoadingMore = newValue }
    }

    var hasMoreEpisodes: Bool {
        get { episodeState.hasMore }
        set { episodeState.hasMore = newValue }
    }

    var episodeTotalCount: Int {
        get { episodeState.totalCount }
        set { episodeState.totalCount = newValue }
    }

    @Published private(set) var isUpdatingFavorite = false
    @Published private(set) var isUpdatingWatched = false
    /// 详情心形以 Store 为准：Home 临时 MediaItem 的 isFavorite 不会可靠驱动 SwiftUI 刷新。
    @Published private(set) var isFavorite = false
    @Published var favoriteErrorMessage: String?

    var isRefreshingMetadata: Bool {
        get { actionState.isRefreshingMetadata }
        set { actionState.isRefreshingMetadata = newValue }
    }

    var refreshErrorMessage: String? {
        get { actionState.refreshErrorMessage }
        set { actionState.refreshErrorMessage = newValue }
    }

    private var loadedKey: String?
    private var loadGeneration = 0
    private var episodeStartIndex = 0
    private var episodeLoadGeneration = 0
    private var metadataCacheRecord: MetadataCacheRecord?
    private var metadataRootDirectory: URL?
    private var initialEpisodeTask: Task<Void, Never>?
    private let metadataLoader = MediaDetailProgressiveLoader()

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

#if DEBUG
    func installDebugHeroWalkEpisodesIfNeeded(for item: MediaItem) {
        guard DownloadHeroWalkFixtures.requestedKind == .series, item.mediaType == .tvShow else { return }
        guard let episodes = try? DownloadHeroWalkFixtures.seriesEpisodes() else { return }
        if content == nil {
            content = MacMediaDetailContent(
                enrichedOverview: item.overview,
                enrichedGenres: [],
                logoURL: nil,
                backdropURL: nil,
                castMembers: [],
                seasons: [SeasonInfo(seasonNumber: 1)],
                collections: []
            )
        } else {
            content?.seasons = [SeasonInfo(seasonNumber: 1)]
        }
        selectedSeason = 1
        seasonEpisodes = episodes
        hasMoreEpisodes = false
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
    }
#endif

    func load(item: MediaItem, modelContext: ModelContext, autoDownloadMetadata: Bool) async {
        // Home 预览项是临时对象，isFavorite 常不准；打开详情时从 SwiftData 对齐。
        syncFavoriteState(for: item, in: modelContext)

        let key = detailKey(for: item)
        guard loadedKey != key else { return }
        loadedKey = key
        loadGeneration += 1
        let generation = loadGeneration
        defer {
            if generation == loadGeneration {
                isLoading = false
                if Task.isCancelled {
                    loadedKey = nil
                }
            }
        }

        isLoading = true
        resetEpisodePagingState()
        content = baseContent(for: item)

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
        loadGeneration += 1
        let generation = loadGeneration
        initialEpisodeTask?.cancel()
        episodeLoadGeneration += 1

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: true,
            force: force,
            generation: generation
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

    /// 缓存、详情、季和合集按完成顺序发布，避免最慢请求阻塞其它组件。
    private func performAggregate(
        item: MediaItem,
        modelContext: ModelContext,
        autoDownloadMetadata: Bool,
        force: Bool,
        generation: Int
    ) async {
        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        metadataRootDirectory = root
        let connection = try? mediaServerConnectionSnapshot(for: item, in: modelContext)
        let canRefresh = supportsMetadataRefresh(for: item, in: modelContext)
        let updates = metadataLoader.updates(
            for: item,
            connection: connection,
            autoDownloadMetadata: autoDownloadMetadata && canRefresh,
            force: force
        )

        for await event in updates {
            guard generation == loadGeneration, !Task.isCancelled, !item.isDeleted else { return }
            switch event {
            case .cached(let record), .metadata(let record):
                applyMetadataRecord(record, root: root, item: item)
                if episodeState.seasons.isEmpty, item.mediaType == .tvShow {
                    applySeasons(seasonInfos(from: record), item: item, modelContext: modelContext)
                }
            case .seasons(let seasons):
                applySeasons(seasons, item: item, modelContext: modelContext)
            case .collections(let collections):
                collectionState.items = collections
            case .failed(let component, let message):
                if component == .metadata {
                    refreshErrorMessage = message
                }
            case .finished:
                isLoading = false
            }
        }

        guard generation == loadGeneration else { return }
        isLoading = false
    }

    private func baseContent(for item: MediaItem) -> MacMediaDetailContent {
        let members = item.cast.prefix(5).map { name in
            CastMemberDisplay(id: name, name: name, role: nil, profileURL: nil)
        }
        return MacMediaDetailContent(
            enrichedOverview: item.overview,
            enrichedGenres: item.genres,
            logoURL: item.logoURL,
            backdropURL: item.backdropURL ?? item.posterURL,
            castMembers: members,
            seasons: [],
            collections: []
        )
    }

    private func applyMetadataRecord(
        _ record: MetadataCacheRecord,
        root: URL,
        item: MediaItem
    ) {
        metadataCacheRecord = record
        var snapshot = summaryState.content ?? baseContent(for: item)
        if let overview = record.overview, !overview.isEmpty {
            snapshot.enrichedOverview = overview
        }
        if !record.genres.isEmpty {
            snapshot.enrichedGenres = record.genres
        }
        snapshot.logoURL = record.resolvedLogoURL(rootDirectory: root) ?? snapshot.logoURL
        if let backdrop = record.resolvedBackdropURL(rootDirectory: root) ?? record.posterRemoteURL {
            snapshot.backdropURL = backdrop
        }
        summaryState.content = snapshot

        let members = record.makeCastDisplays(rootDirectory: root)
        if !members.isEmpty {
            castState.members = members
        }
    }

    private func applySeasons(
        _ seasons: [SeasonInfo],
        item: MediaItem,
        modelContext: ModelContext
    ) {
        guard !seasons.isEmpty else { return }
        episodeState.seasons = seasons
        let previousSeason = selectedSeason
        if let previousSeason, seasons.contains(where: { $0.seasonNumber == previousSeason }) {
            selectedSeason = previousSeason
        } else {
            selectedSeason = seasons.first?.seasonNumber
        }

        initialEpisodeTask?.cancel()
        initialEpisodeTask = Task { [weak self] in
            guard let self else { return }
            await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
        }
    }

    func invalidate() {
        loadGeneration += 1
        episodeLoadGeneration += 1
        loadedKey = nil
        initialEpisodeTask?.cancel()
        isLoading = false
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
    }

    private func resetEpisodePagingState() {
        initialEpisodeTask?.cancel()
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

    private func loadSeasonEpisodes(item: MediaItem, modelContext: ModelContext, reset: Bool) async {
        guard !Task.isCancelled,
              loadedKey == detailKey(for: item),
              item.mediaType == .tvShow else {
            return
        }
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
            let cacheKey = MetadataCacheKey.from(item)
            Task(priority: .utility) {
                try? await MetadataCache.shared.cacheEpisodes(page.items, for: cacheKey)
            }
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
            let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext)
            let writeMediaServer = snapshot != nil || (!item.isFavoriteCloudSynced && item.serverId != nil)
            if writeMediaServer {
                try await EmbyFavoriteUpdater.setFavorite(
                    item,
                    isFavorite: targetFavorite,
                    connection: snapshot
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

}

extension Notification.Name {
    /// 与 iOS 共用通知名字符串。Mac 端 `object` 传 `MediaItem.id`（UUID）；接收方当前忽略 object。
    static let mediaFavoriteDidChange = Notification.Name("mediaFavoriteDidChange")
}
