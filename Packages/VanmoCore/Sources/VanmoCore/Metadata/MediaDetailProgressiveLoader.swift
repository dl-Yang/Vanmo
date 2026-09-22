import Foundation

public enum MediaDetailLoadComponent: String, Sendable {
    case metadata
    case seasons
    case collections
}

public enum MediaDetailLoadEvent: Sendable {
    case cached(MetadataCacheRecord)
    case metadata(MetadataCacheRecord)
    case seasons([SeasonInfo])
    case collections([ServerMediaItem])
    case failed(MediaDetailLoadComponent, String)
    case finished
}

@MainActor
public final class MediaDetailProgressiveLoader {
    typealias CacheLoader = (MetadataCacheKey) async -> MetadataCacheRecord?
    typealias MetadataLoader = (
        MediaItem,
        Bool,
        MediaServerConnectionSnapshot?
    ) async throws -> MetadataCacheRecord?
    typealias SeasonLoader = (
        MediaItem,
        MediaServerConnectionSnapshot?
    ) async throws -> [SeasonInfo]
    typealias CollectionLoader = (
        MediaItem,
        MediaServerConnectionSnapshot?
    ) async throws -> [ServerMediaItem]
    typealias RecordStore = (MetadataCacheRecord) async throws -> MetadataCacheRecord
    typealias ArtworkScheduler = (MetadataCacheRecord) async -> Void

    private let loadCache: CacheLoader
    private let loadMetadata: MetadataLoader
    private let loadSeasons: SeasonLoader
    private let loadCollections: CollectionLoader
    private let storeRecord: RecordStore
    private let scheduleArtwork: ArtworkScheduler

    public init() {
        loadCache = { key in
            await MetadataCache.shared.load(for: key)
        }
        loadMetadata = { item, force, connection in
            try await MetadataRefreshCoordinator.shared.prepareRefreshDraft(
                item,
                force: force,
                connection: connection
            )
        }
        loadSeasons = Self.fetchSeasons
        loadCollections = Self.fetchCollections
        storeRecord = { record in
            try await MetadataCache.shared.store(record)
        }
        scheduleArtwork = { record in
            await MetadataCache.shared.scheduleImageCaching(for: record)
        }
    }

    init(
        loadCache: @escaping CacheLoader,
        loadMetadata: @escaping MetadataLoader,
        loadSeasons: @escaping SeasonLoader,
        loadCollections: @escaping CollectionLoader,
        storeRecord: @escaping RecordStore,
        scheduleArtwork: @escaping ArtworkScheduler
    ) {
        self.loadCache = loadCache
        self.loadMetadata = loadMetadata
        self.loadSeasons = loadSeasons
        self.loadCollections = loadCollections
        self.storeRecord = storeRecord
        self.scheduleArtwork = scheduleArtwork
    }

    public func updates(
        for item: MediaItem,
        connection: MediaServerConnectionSnapshot?,
        autoDownloadMetadata: Bool,
        force: Bool
    ) -> AsyncStream<MediaDetailLoadEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                let startedAt = Date()
#if DEBUG
                print(
                    "[Debug][DetailMetadata] phase=start type=\(item.mediaType.rawValue) "
                        + "metadata=\(autoDownloadMetadata) seasons=\(item.mediaType == .tvShow)"
                )
#endif
                let key = MetadataCacheKey.from(item)
                if let cached = await loadCache(key) {
                    continuation.yield(.cached(cached))
#if DEBUG
                    Self.logPhase("cache", startedAt: startedAt)
#endif
                }

                await withTaskGroup(of: MediaDetailLoadEvent?.self) { group in
                    if autoDownloadMetadata {
                        group.addTask { @MainActor [loadMetadata, storeRecord, scheduleArtwork] in
                            do {
                                guard let draft = try await loadMetadata(item, force, connection) else {
                                    return nil
                                }
                                let stored = try await storeRecord(draft)
                                Task(priority: .utility) {
                                    await scheduleArtwork(stored)
                                }
                                return .metadata(stored)
                            } catch {
                                return .failed(.metadata, error.localizedDescription)
                            }
                        }
                    }

                    if item.mediaType == .tvShow, item.serverId?.isEmpty == false {
                        group.addTask { @MainActor [loadSeasons] in
                            do {
                                return .seasons(try await loadSeasons(item, connection))
                            } catch {
                                return .failed(.seasons, error.localizedDescription)
                            }
                        }
                    }

                    if item.mediaType != .boxSet, item.serverId?.isEmpty == false {
                        group.addTask { @MainActor [loadCollections] in
                            do {
                                return .collections(try await loadCollections(item, connection))
                            } catch {
                                return .failed(.collections, error.localizedDescription)
                            }
                        }
                    }

                    for await event in group {
                        guard !Task.isCancelled else { break }
                        if let event {
                            continuation.yield(event)
#if DEBUG
                            Self.logPhase(event.debugComponent, startedAt: startedAt)
#endif
                        }
                    }
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(.finished)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func fetchSeasons(
        item: MediaItem,
        connection: MediaServerConnectionSnapshot?
    ) async throws -> [SeasonInfo] {
        guard let serverID = item.serverId else { return [] }
        if connection?.type == .plex || item.fileURL.host == "plex-series" {
            if let connection {
                return try await PlexEpisodeFetcher.fetchSeasons(
                    seriesRatingKey: serverID,
                    connection: connection
                )
            }
            return try await PlexEpisodeFetcher.fetchSeasons(seriesRatingKey: serverID)
        }

        if let connection {
            return try await EmbyEpisodeFetcher.fetchSeasons(
                seriesId: serverID,
                connection: connection
            )
        }
        return try await EmbyEpisodeFetcher.fetchSeasons(seriesId: serverID)
    }

    private static func fetchCollections(
        item: MediaItem,
        connection: MediaServerConnectionSnapshot?
    ) async throws -> [ServerMediaItem] {
        guard let serverID = item.serverId else { return [] }
        if let connection {
            guard connection.type == .emby || connection.type == .jellyfin else { return [] }
            return try await EmbyCollectionsFetcher.fetchCollections(
                containing: serverID,
                connection: connection
            )
        }

        guard isEmbyOrigin(item) else { return [] }
        return try await EmbyCollectionsFetcher.fetchCollections(containing: serverID)
    }

    private static func isEmbyOrigin(_ item: MediaItem) -> Bool {
        if item.fileURL.scheme == "vanmo" {
            return ["series", "emby-container", "emby-item"].contains(item.fileURL.host?.lowercased())
        }
        guard let baseHost = EmbyCredentialStore.baseURL.flatMap({ URL(string: $0)?.host?.lowercased() }),
              let itemHost = item.fileURL.host?.lowercased() else {
            return false
        }
        return baseHost == itemHost
    }

#if DEBUG
    private nonisolated static func logPhase(_ phase: String, startedAt: Date) {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        print("[Debug][DetailMetadata] phase=\(phase) elapsedMs=\(milliseconds)")
    }
#endif
}

#if DEBUG
private extension MediaDetailLoadEvent {
    var debugComponent: String {
        switch self {
        case .cached:
            return "cache"
        case .metadata:
            return "metadata"
        case .seasons:
            return "seasons"
        case .collections:
            return "collections"
        case .failed(let component, _):
            return "\(component.rawValue)-failed"
        case .finished:
            return "finished"
        }
    }
}
#endif
