import Foundation

struct HomeCollectionCacheSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    let connections: [HomeConnectionCache]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        savedAt: Date = Date(),
        connections: [HomeConnectionCache]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.connections = connections
    }
}

struct HomeConnectionCache: Codable, Sendable {
    let connectionId: UUID
    let connectionName: String
    let folders: [HomeFolderCache]
}

struct HomeFolderCache: Codable, Sendable {
    let id: String
    let name: String
    let collectionType: EmbyCollectionType
    let posterURL: URL?
    let totalCount: Int?
    let preview: [HomePreviewItemCache]
}

struct HomePreviewItemCache: Codable, Sendable {
    let serverId: String?
    let title: String
    let showTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let mediaType: String
    let posterURL: URL?
    let year: Int?
    let rating: Double?
    let lastPlaybackPosition: TimeInterval
    let duration: TimeInterval
    let streamURL: URL
}

actor HomeCollectionCache {
    static let shared = HomeCollectionCache()

    private let cacheDirectoryName = "Vanmo"
    private let cacheFileName = "home_collection_cache.json"

    func load() -> HomeCollectionCacheSnapshot? {
        do {
            let url = try cacheURL(createDirectoryIfNeeded: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(HomeCollectionCacheSnapshot.self, from: data)
            guard snapshot.schemaVersion == HomeCollectionCacheSnapshot.currentSchemaVersion else {
                return nil
            }
            return snapshot
        } catch {
            VanmoLogger.library.error("[HomeCollectionCache] load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ snapshot: HomeCollectionCacheSnapshot) {
        do {
            let url = try cacheURL(createDirectoryIfNeeded: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            VanmoLogger.library.error("[HomeCollectionCache] save failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        do {
            let url = try cacheURL(createDirectoryIfNeeded: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        } catch {
            VanmoLogger.library.error("[HomeCollectionCache] clear failed: \(error.localizedDescription)")
        }
    }

    private func cacheURL(createDirectoryIfNeeded: Bool) throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw HomeCollectionCacheError.applicationSupportDirectoryUnavailable
        }

        let directoryURL = applicationSupportURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if createDirectoryIfNeeded {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
        return directoryURL.appendingPathComponent(cacheFileName)
    }
}

private enum HomeCollectionCacheError: LocalizedError {
    case applicationSupportDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Application Support directory is unavailable"
        }
    }
}
