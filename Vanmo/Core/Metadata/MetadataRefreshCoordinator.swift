import Foundation

actor MetadataRefreshCoordinator {
    static let shared = MetadataRefreshCoordinator()

    private let cache = MetadataCache.shared
    private let metadataService = MetadataService.shared

    nonisolated static func supportsRefresh(for item: MediaItem) -> Bool {
        resolveSource(for: item) != .unsupported
    }

    func refresh(_ item: MediaItem, force: Bool) async throws -> MetadataCacheRecord {
        let key = MetadataCacheKey.from(item)

        if !force, let cached = await cache.load(for: key) {
            await apply(record: cached, to: item)
            return cached
        }

        let draft = try await buildDraft(for: item, key: key)
        let saved = try await cache.save(draft)
        await apply(record: saved, to: item)
        return saved
    }

    @MainActor
    private func apply(record: MetadataCacheRecord, to item: MediaItem) async {
        let root = (try? await cache.rootDirectoryURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        await metadataService.applyCachedRecord(record, rootDirectory: root, to: item)
    }

    private func buildDraft(for item: MediaItem, key: MetadataCacheKey) async throws -> MetadataCacheRecord {
        switch Self.resolveSource(for: item) {
        case .embyLike:
            return try await buildEmbyLikeDraft(for: item, key: key)
        case .plexSeries:
            return try await buildPlexSeriesDraft(for: item, key: key)
        case .plexMovie:
            return try await buildPlexMovieDraft(for: item, key: key)
        case .unsupported:
            throw MetadataRefreshError.unsupportedSource
        }
    }

    private enum RefreshSource: Equatable {
        case embyLike
        case plexSeries
        case plexMovie
        case unsupported
    }

    private nonisolated static func resolveSource(for item: MediaItem) -> RefreshSource {
        switch item.fileURL.host?.lowercased() {
        case "plex-series":
            return .plexSeries
        case "series", "emby-container", "emby-item":
            return .embyLike
        default:
            if isEmbyStreamItem(item) {
                return .embyLike
            }
            if isPlexStreamItem(item) {
                return .plexMovie
            }
            return .unsupported
        }
    }

    private nonisolated static func isEmbyStreamItem(_ item: MediaItem) -> Bool {
        guard let serverId = item.serverId, !serverId.isEmpty,
              let baseURLStr = EmbyCredentialStore.baseURL,
              let baseHost = URL(string: baseURLStr)?.host?.lowercased(),
              let itemHost = item.fileURL.host?.lowercased() else {
            return false
        }
        return baseHost == itemHost
    }

    private nonisolated static func isPlexStreamItem(_ item: MediaItem) -> Bool {
        guard let serverId = item.serverId, !serverId.isEmpty,
              let baseURLStr = PlexCredentialStore.baseURL,
              let baseHost = URL(string: baseURLStr)?.host?.lowercased(),
              let itemHost = item.fileURL.host?.lowercased() else {
            return false
        }
        return baseHost == itemHost
    }

    private func buildEmbyLikeDraft(for item: MediaItem, key: MetadataCacheKey) async throws -> MetadataCacheRecord {
        guard let serverId = item.serverId, !serverId.isEmpty else {
            throw MetadataRefreshError.missingServerId
        }

        let detail = try await EmbyItemDetailFetcher.fetchDetail(itemId: serverId)
        let source: MetadataSource = EmbyCredentialStore.apiPrefix.isEmpty ? .jellyfin : .emby

        var episodes: [CachedEpisodeInfo] = []
        if item.mediaType == .tvShow {
            let fetched = try await EmbyEpisodeFetcher.fetchEpisodes(seriesId: serverId)
            episodes = fetched.map(makeCachedEpisode)
        }

        let castMembers = detail.castMembers.map { $0.makeCachedMember() }

        return MetadataCacheRecord(
            key: key,
            title: detail.title,
            originalTitle: detail.originalTitle,
            year: detail.year,
            overview: detail.overview,
            rating: detail.rating,
            genres: detail.genres,
            director: detail.director,
            cast: detail.cast,
            castMembers: castMembers,
            originCountry: detail.originCountry,
            tmdbID: detail.tmdbID ?? item.tmdbID,
            logoLocalPath: nil,
            backdropLocalPath: nil,
            logoRemoteURL: detail.logoURL,
            backdropRemoteURL: detail.backdropURL,
            posterRemoteURL: detail.posterURL,
            episodes: episodes,
            fetchedAt: Date(),
            source: source
        )
    }

    private func buildPlexSeriesDraft(for item: MediaItem, key: MetadataCacheKey) async throws -> MetadataCacheRecord {
        guard let serverId = item.serverId, !serverId.isEmpty else {
            throw MetadataRefreshError.missingServerId
        }

        let detail = try await PlexItemDetailFetcher.fetchDetail(ratingKey: serverId)
        let fetched = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: serverId)
        let episodes = fetched.map(makeCachedEpisode)
        let castMembers = makeCastMembers(from: detail.cast)

        return MetadataCacheRecord(
            key: key,
            title: detail.showTitle ?? detail.title,
            originalTitle: detail.originalTitle,
            year: detail.year,
            overview: detail.overview,
            rating: detail.rating,
            genres: detail.genres,
            director: detail.director,
            cast: detail.cast,
            castMembers: castMembers,
            originCountry: detail.originCountry,
            tmdbID: detail.tmdbID ?? item.tmdbID,
            logoLocalPath: nil,
            backdropLocalPath: nil,
            logoRemoteURL: detail.logoURL,
            backdropRemoteURL: detail.backdropURL,
            posterRemoteURL: detail.posterURL,
            episodes: episodes,
            fetchedAt: Date(),
            source: .plex
        )
    }

    private func buildPlexMovieDraft(for item: MediaItem, key: MetadataCacheKey) async throws -> MetadataCacheRecord {
        guard let serverId = item.serverId, !serverId.isEmpty else {
            throw MetadataRefreshError.missingServerId
        }

        let detail = try await PlexItemDetailFetcher.fetchDetail(ratingKey: serverId)
        let castMembers = makeCastMembers(from: detail.cast)

        return MetadataCacheRecord(
            key: key,
            title: detail.title,
            originalTitle: detail.originalTitle,
            year: detail.year,
            overview: detail.overview,
            rating: detail.rating,
            genres: detail.genres,
            director: detail.director,
            cast: detail.cast,
            castMembers: castMembers,
            originCountry: detail.originCountry,
            tmdbID: detail.tmdbID ?? item.tmdbID,
            logoLocalPath: nil,
            backdropLocalPath: nil,
            logoRemoteURL: detail.logoURL,
            backdropRemoteURL: detail.backdropURL,
            posterRemoteURL: detail.posterURL,
            episodes: [],
            fetchedAt: Date(),
            source: .plex
        )
    }

    private func makeCachedEpisode(_ episode: EpisodeInfo) -> CachedEpisodeInfo {
        CachedEpisodeInfo(
            id: episode.id,
            title: episode.title,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
            duration: episode.duration,
            overview: episode.overview,
            streamURL: episode.streamURL,
            backdropLocalPath: nil,
            backdropRemoteURL: episode.backdropURL
        )
    }

    private func makeCastMembers(from names: [String]) -> [CachedCastMember] {
        names.map { name in
            CachedCastMember(
                id: name,
                name: name,
                role: nil,
                profileLocalPath: nil,
                profileRemoteURL: nil
            )
        }
    }
}

enum MetadataRefreshError: LocalizedError {
    case missingServerId
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .missingServerId:
            return "无法刷新：缺少服务器媒体 ID"
        case .unsupportedSource:
            return "此来源不支持元数据刷新，请使用媒体服务器中的条目"
        }
    }
}
