import SwiftUI
import SwiftData
import VanmoCore

@MainActor
final class MacMediaDetailStore: ObservableObject {
    @Published private(set) var castMembers: [CastMemberDisplay] = []
    @Published private(set) var episodes: [EpisodeInfo] = []
    @Published private(set) var collections: [ServerMediaItem] = []
    @Published private(set) var enrichedOverview: String?
    @Published private(set) var enrichedGenres: [String] = []
    @Published var selectedSeason: Int?
    @Published var isLoadingEpisodes = false
    @Published var isRefreshingMetadata = false
    @Published var isUpdatingFavorite = false
    @Published var isUpdatingWatched = false
    @Published var favoriteErrorMessage: String?
    @Published var refreshErrorMessage: String?

    var seasonNumbers: [Int] {
        Array(Set(episodes.map(\.seasonNumber))).sorted()
    }

    var currentSeasonEpisodes: [EpisodeInfo] {
        let season = selectedSeason ?? seasonNumbers.first ?? 1
        return episodes
            .filter { $0.seasonNumber == season }
            .sorted { $0.episodeNumber < $1.episodeNumber }
    }

    func setCast(_ members: [CastMemberDisplay]) {
        guard castMembers != members else { return }
        castMembers = members
    }

    func setEpisodes(_ newEpisodes: [EpisodeInfo]) {
        episodes = newEpisodes
        if selectedSeason == nil {
            selectedSeason = seasonNumbers.first
        }
    }

    func setCollections(_ newCollections: [ServerMediaItem]) {
        guard collections.map(\.serverId) != newCollections.map(\.serverId) else { return }
        collections = newCollections
    }

    func loadCachedMetadata(for item: MediaItem) async {
        let key = MetadataCacheKey.from(item)
        guard let record = await MetadataCache.shared.load(for: key) else { return }
        await applyRecord(record, to: item)
    }

    func refreshMetadata(for item: MediaItem, modelContext: ModelContext, force: Bool) async {
        guard supportsMetadataRefresh(for: item, in: modelContext) else { return }
        guard !isRefreshingMetadata else { return }

        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }

        do {
            let connection = try? mediaServerConnectionSnapshot(for: item, in: modelContext)
            if let draft = try await MetadataRefreshCoordinator.shared.prepareRefreshDraft(
                item,
                force: force,
                connection: connection
            ) {
                await applyRecord(draft, to: item)
                let record = try await MetadataCache.shared.save(draft)
                await applyRecord(record, to: item)
            } else if let record = await MetadataCache.shared.load(for: MetadataCacheKey.from(item)) {
                await applyRecord(record, to: item)
            }
        } catch {
            refreshErrorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(for item: MediaItem, modelContext: ModelContext) async {
        guard !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }

        let targetFavorite = !item.isFavorite

        do {
            if item.serverId != nil {
                try await EmbyFavoriteUpdater.setFavorite(
                    item,
                    isFavorite: targetFavorite,
                    connection: try? mediaServerConnectionSnapshot(for: item, in: modelContext)
                )
            }
            item.isFavorite = targetFavorite
            if item.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.markMediaFavoriteChanged(item, in: modelContext)
            }
            try modelContext.save()
            if item.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.requestSync(reason: "favorite", context: modelContext)
            }
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
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

        if item.isProgressCloudSynced {
            CloudSyncCoordinator.shared.markMediaProgressChanged(item, in: modelContext)
            try? modelContext.save()
            CloudSyncCoordinator.shared.requestSync(reason: "watched", context: modelContext)
        } else {
            try? modelContext.save()
        }
    }

    func loadEpisodes(for item: MediaItem, modelContext: ModelContext) async {
        guard item.mediaType == .tvShow, let seriesServerId = item.serverId else { return }

        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        do {
            let loaded: [EpisodeInfo]
            switch item.fileURL.host {
            case "plex-series":
                if let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext) {
                    loaded = try await PlexEpisodeFetcher.fetchEpisodes(
                        seriesRatingKey: seriesServerId,
                        connection: snapshot
                    )
                } else {
                    loaded = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: seriesServerId)
                }
            default:
                if let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext) {
                    loaded = try await EmbyEpisodeFetcher.fetchEpisodes(
                        seriesId: seriesServerId,
                        connection: snapshot
                    )
                } else {
                    loaded = try await EmbyEpisodeFetcher.fetchEpisodes(seriesId: seriesServerId)
                }
            }
            setEpisodes(loaded)
            await mergeEpisodeBackdropsFromCache(for: item)
        } catch {
            VanmoLogger.library.error("[MacMediaDetail] Failed to load episodes: \(error.localizedDescription)")
            setEpisodes([])
        }
    }

    func loadCollections(for item: MediaItem, modelContext: ModelContext) async {
        guard let serverId = item.serverId, item.mediaType != .boxSet else {
            setCollections([])
            return
        }

        do {
            if let snapshot = try? mediaServerConnectionSnapshot(for: item, in: modelContext) {
                guard snapshot.type == .emby || snapshot.type == .jellyfin else {
                    setCollections([])
                    return
                }
                setCollections(
                    try await EmbyCollectionsFetcher.fetchCollections(containing: serverId, connection: snapshot)
                )
            } else if isEmbyOriginItem(item) {
                setCollections(try await EmbyCollectionsFetcher.fetchCollections(containing: serverId))
            } else {
                setCollections([])
            }
        } catch {
            VanmoLogger.library.error("[MacMediaDetail] Failed to load collections: \(error.localizedDescription)")
            setCollections([])
        }
    }

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

    private func applyRecord(_ record: MetadataCacheRecord, to item: MediaItem) async {
        if let overview = record.overview, !overview.isEmpty {
            enrichedOverview = overview
            if item.overview?.isEmpty != false {
                item.overview = overview
            }
        }
        if !record.genres.isEmpty {
            enrichedGenres = record.genres
        }

        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        setCast(record.makeCastDisplays(rootDirectory: root))

        if item.mediaType == .tvShow, !record.episodes.isEmpty {
            if episodes.isEmpty {
                setEpisodes(record.episodes.map { $0.makeEpisodeInfo(rootDirectory: root) })
            } else {
                let cachedByID = Dictionary(uniqueKeysWithValues: record.episodes.map { ($0.id, $0) })
                setEpisodes(episodes.map { episode in
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
                        backdropURL: cachedEpisode.backdropURL
                    )
                })
            }
        }
    }

    private func mergeEpisodeBackdropsFromCache(for item: MediaItem) async {
        let key = MetadataCacheKey.from(item)
        guard let record = await MetadataCache.shared.load(for: key),
              !record.episodes.isEmpty else { return }

        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let cachedByID = Dictionary(uniqueKeysWithValues: record.episodes.map { ($0.id, $0) })

        setEpisodes(episodes.map { episode in
            guard episode.backdropURL == nil, let cached = cachedByID[episode.id] else {
                return episode
            }
            return EpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropURL: cached.makeEpisodeInfo(rootDirectory: root).backdropURL
            )
        })
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
