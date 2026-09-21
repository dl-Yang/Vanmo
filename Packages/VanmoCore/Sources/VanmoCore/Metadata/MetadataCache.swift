import Foundation

public actor MetadataCache {
    public static let shared = MetadataCache()

    private let cacheDirectoryName = "Vanmo"
    private let metadataDirectoryName = "MetadataCache"
    private let indexFileName = "index.json"
    private let imagesDirectoryName = "images"
    private let imageDownloadConcurrency = 4

    private var index = MetadataCacheIndex()
    private var activeImageCachingKeys: Set<String> = []
    private var pendingImageRecords: [String: MetadataCacheRecord] = [:]
    private var pendingEpisodes: [String: [String: CachedEpisodeInfo]] = [:]

    public func load(for key: MetadataCacheKey) -> MetadataCacheRecord? {
        loadIndexIfNeeded()
        return index.records[key.cacheKey]
    }

    public func rootDirectoryURL() throws -> URL {
        try metadataRootURL(createDirectoryIfNeeded: false)
    }

    public func store(_ record: MetadataCacheRecord) throws -> MetadataCacheRecord {
        loadIndexIfNeeded()
        var stored = record
        if let existing = index.records[record.key.cacheKey] {
            stored = mergeExistingCache(existing, into: stored)
        }
        if let pending = pendingEpisodes.removeValue(forKey: record.key.cacheKey) {
            stored.episodes = mergeEpisodes(
                stored.episodes,
                with: Array(pending.values)
            )
        }
        stored.fetchedAt = Date()
        index.records[record.key.cacheKey] = stored
        try persistIndex()
        return stored
    }

    public func cacheEpisodes(
        _ episodes: [EpisodeInfo],
        for key: MetadataCacheKey
    ) throws {
        loadIndexIfNeeded()
        guard !episodes.isEmpty else { return }

        var cachedEpisodes: [CachedEpisodeInfo] = []
        for episode in episodes {
            cachedEpisodes.append(CachedEpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropLocalPath: nil,
                backdropRemoteURL: episode.backdropURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath
            ))
        }

        guard var record = index.records[key.cacheKey] else {
            var pending = pendingEpisodes[key.cacheKey] ?? [:]
            for episode in cachedEpisodes {
                pending[episode.id] = episode
            }
            pendingEpisodes[key.cacheKey] = pending
            return
        }
        record.episodes = mergeEpisodes(record.episodes, with: cachedEpisodes)
        index.records[key.cacheKey] = record
        try persistIndex()
        scheduleImageCaching(for: record)
    }

    public func scheduleImageCaching(for record: MetadataCacheRecord) {
        let cacheKey = record.key.cacheKey
        guard activeImageCachingKeys.insert(cacheKey).inserted else {
            pendingImageRecords[cacheKey] = record
            return
        }

        Task {
            do {
                _ = try await save(record)
            } catch {
                VanmoLogger.metadata.error(
                    "[MetadataCache] artwork caching failed: \(error.localizedDescription)"
                )
            }
            finishImageCaching(for: cacheKey)
        }
    }

    public func save(_ record: MetadataCacheRecord) async throws -> MetadataCacheRecord {
        loadIndexIfNeeded()

        let root = try metadataRootURL(createDirectoryIfNeeded: true)
        let imageRoot = root
            .appendingPathComponent(imagesDirectoryName, isDirectory: true)
            .appendingPathComponent(sanitizePathComponent(record.key.cacheKey), isDirectory: true)

        try FileManager.default.createDirectory(at: imageRoot, withIntermediateDirectories: true)

        var updated = record

        if let remote = record.logoRemoteURL {
            let relative = "\(imagesDirectoryName)/\(sanitizePathComponent(record.key.cacheKey))/logo.jpg"
            let destination = root.appendingPathComponent(relative)
            do {
                try await downloadImage(from: remote, to: destination)
                updated.logoLocalPath = relative
            } catch {
                VanmoLogger.metadata.error("[MetadataCache] logo download failed: \(error.localizedDescription)")
            }
        }

        if let remote = record.backdropRemoteURL {
            let relative = "\(imagesDirectoryName)/\(sanitizePathComponent(record.key.cacheKey))/backdrop.jpg"
            let destination = root.appendingPathComponent(relative)
            do {
                try await downloadImage(from: remote, to: destination)
                updated.backdropLocalPath = relative
            } catch {
                VanmoLogger.metadata.error("[MetadataCache] backdrop download failed: \(error.localizedDescription)")
            }
        }

        if !record.castMembers.isEmpty {
            let castRoot = imageRoot.appendingPathComponent("cast", isDirectory: true)
            try FileManager.default.createDirectory(at: castRoot, withIntermediateDirectories: true)

            let sanitizedKey = sanitizePathComponent(record.key.cacheKey)
            let imagesDir = imagesDirectoryName
            var cachedMembers: [CachedCastMember] = []
            for start in stride(from: 0, to: record.castMembers.count, by: imageDownloadConcurrency) {
                let end = min(start + imageDownloadConcurrency, record.castMembers.count)
                let batch = Array(record.castMembers[start..<end])
                let results = try await withThrowingTaskGroup(of: CachedCastMember.self) { group in
                    for member in batch {
                        group.addTask {
                            guard let remote = member.profileRemoteURL else { return member }
                            let fileName = "\(Self.sanitizePathComponent(member.id)).jpg"
                            let relative = "\(imagesDir)/\(sanitizedKey)/cast/\(fileName)"
                            let destination = root.appendingPathComponent(relative)
                            do {
                                try await self.downloadImage(from: remote, to: destination)
                                return CachedCastMember(
                                    id: member.id,
                                    name: member.name,
                                    role: member.role,
                                    profileLocalPath: relative,
                                    profileRemoteURL: member.profileRemoteURL
                                )
                            } catch {
                                VanmoLogger.metadata.error(
                                    "[MetadataCache] cast profile download failed: \(error.localizedDescription)"
                                )
                                return member
                            }
                        }
                    }

                    var batchResults: [CachedCastMember] = []
                    for try await member in group {
                        batchResults.append(member)
                    }
                    return batchResults
                }
                cachedMembers.append(contentsOf: results)
            }
            updated.castMembers = cachedMembers
        }

        if !record.episodes.isEmpty {
            let episodeRoot = imageRoot.appendingPathComponent("episodes", isDirectory: true)
            try FileManager.default.createDirectory(at: episodeRoot, withIntermediateDirectories: true)

            let sanitizedKey = sanitizePathComponent(record.key.cacheKey)
            let imagesDir = imagesDirectoryName
            var cachedEpisodes: [CachedEpisodeInfo] = []
            for start in stride(from: 0, to: record.episodes.count, by: imageDownloadConcurrency) {
                let end = min(start + imageDownloadConcurrency, record.episodes.count)
                let batch = Array(record.episodes[start..<end])
                let results = try await withThrowingTaskGroup(of: CachedEpisodeInfo.self) { group in
                    for episode in batch {
                        group.addTask {
                            guard let remote = episode.backdropRemoteURL else { return episode }
                            let fileName = "\(Self.sanitizePathComponent(episode.id)).jpg"
                            let relative = "\(imagesDir)/\(sanitizedKey)/episodes/\(fileName)"
                            let destination = root.appendingPathComponent(relative)
                            do {
                                try await self.downloadImage(from: remote, to: destination)
                                return CachedEpisodeInfo(
                                    id: episode.id,
                                    title: episode.title,
                                    seasonNumber: episode.seasonNumber,
                                    episodeNumber: episode.episodeNumber,
                                    duration: episode.duration,
                                    overview: episode.overview,
                                    streamURL: episode.streamURL,
                                    backdropLocalPath: relative,
                                    backdropRemoteURL: episode.backdropRemoteURL,
                                    fileSize: episode.fileSize,
                                    originalFileName: episode.originalFileName,
                                    container: episode.container,
                                    remotePath: episode.remotePath
                                )
                            } catch {
                                VanmoLogger.metadata.error(
                                    "[MetadataCache] episode backdrop download failed: \(error.localizedDescription)"
                                )
                                return episode
                            }
                        }
                    }

                    var batchResults: [CachedEpisodeInfo] = []
                    for try await episode in group {
                        batchResults.append(episode)
                    }
                    return batchResults
                }
                cachedEpisodes.append(contentsOf: results)
            }
            updated.episodes = cachedEpisodes.sorted {
                ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
            }
        }

        updated.fetchedAt = Date()
        let merged = mergeArtwork(from: updated, into: index.records[record.key.cacheKey])
        index.records[record.key.cacheKey] = merged
        try persistIndex()
        return merged
    }

    public func deleteAll() throws {
        let root = try metadataRootURL(createDirectoryIfNeeded: false)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        index = MetadataCacheIndex()
        pendingEpisodes.removeAll()
        pendingImageRecords.removeAll()
    }

    public func diskSize() throws -> Int64 {
        let root = try metadataRootURL(createDirectoryIfNeeded: false)
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }

        let resourceKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: resourceKeys),
                  attrs.isRegularFile == true else { continue }
            totalSize += Int64(attrs.totalFileAllocatedSize ?? 0)
        }
        return totalSize
    }

    public func downloadImage(from remoteURL: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 20
        if let token = EmbyCredentialStore.token,
           remoteURL.absoluteString.contains("api_key=") == false,
           remoteURL.host == EmbyCredentialStore.baseURL.flatMap({ URL(string: $0)?.host }) {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw MetadataCacheError.downloadFailed(remoteURL)
        }
        try data.write(to: destination, options: [.atomic])
    }

    private func loadIndexIfNeeded() {
        guard index.records.isEmpty else { return }
        do {
            let url = try indexURL(createDirectoryIfNeeded: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode(MetadataCacheIndex.self, from: data)
            guard loaded.schemaVersion == MetadataCacheIndex.currentSchemaVersion else { return }
            index = loaded
        } catch {
            VanmoLogger.metadata.error("[MetadataCache] load index failed: \(error.localizedDescription)")
        }
    }

    private func persistIndex() throws {
        let url = try indexURL(createDirectoryIfNeeded: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: url, options: [.atomic])
    }

    private func metadataRootURL(createDirectoryIfNeeded: Bool) throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MetadataCacheError.applicationSupportDirectoryUnavailable
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(metadataDirectoryName, isDirectory: true)

        if createDirectoryIfNeeded {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
        return directoryURL
    }

    private func indexURL(createDirectoryIfNeeded: Bool) throws -> URL {
        let root = try metadataRootURL(createDirectoryIfNeeded: createDirectoryIfNeeded)
        return root.appendingPathComponent(indexFileName)
    }

    private func sanitizePathComponent(_ value: String) -> String {
        Self.sanitizePathComponent(value)
    }

    private func finishImageCaching(for cacheKey: String) {
        activeImageCachingKeys.remove(cacheKey)
        guard let pending = pendingImageRecords.removeValue(forKey: cacheKey) else { return }
        scheduleImageCaching(for: pending)
    }

    private func mergeArtwork(
        from hydrated: MetadataCacheRecord,
        into current: MetadataCacheRecord?
    ) -> MetadataCacheRecord {
        guard var current else { return hydrated }
        current.logoLocalPath = hydrated.logoLocalPath ?? current.logoLocalPath
        current.backdropLocalPath = hydrated.backdropLocalPath ?? current.backdropLocalPath

        let hydratedCast = Dictionary(
            hydrated.castMembers.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        current.castMembers = current.castMembers.map { member in
            guard let cached = hydratedCast[member.id], cached.profileLocalPath != nil else {
                return member
            }
            return CachedCastMember(
                id: member.id,
                name: member.name,
                role: member.role,
                profileLocalPath: cached.profileLocalPath,
                profileRemoteURL: member.profileRemoteURL
            )
        }

        let hydratedEpisodes = Dictionary(
            hydrated.episodes.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        current.episodes = current.episodes.map { episode in
            guard let cached = hydratedEpisodes[episode.id], cached.backdropLocalPath != nil else {
                return episode
            }
            return CachedEpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropLocalPath: cached.backdropLocalPath,
                backdropRemoteURL: episode.backdropRemoteURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath
            )
        }
        return current
    }

    private func mergeExistingCache(
        _ existing: MetadataCacheRecord,
        into refreshed: MetadataCacheRecord
    ) -> MetadataCacheRecord {
        var merged = refreshed
        if existing.logoRemoteURL == refreshed.logoRemoteURL {
            merged.logoLocalPath = existing.logoLocalPath
        }
        if existing.backdropRemoteURL == refreshed.backdropRemoteURL {
            merged.backdropLocalPath = existing.backdropLocalPath
        }

        let existingCast = Dictionary(
            existing.castMembers.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        merged.castMembers = refreshed.castMembers.map { member in
            guard let cached = existingCast[member.id],
                  cached.profileRemoteURL == member.profileRemoteURL else {
                return member
            }
            return CachedCastMember(
                id: member.id,
                name: member.name,
                role: member.role,
                profileLocalPath: cached.profileLocalPath,
                profileRemoteURL: member.profileRemoteURL
            )
        }
        merged.episodes = mergeEpisodes(existing.episodes, with: refreshed.episodes)
        return merged
    }

    private func mergeEpisodes(
        _ existing: [CachedEpisodeInfo],
        with incoming: [CachedEpisodeInfo]
    ) -> [CachedEpisodeInfo] {
        var byID = Dictionary(
            existing.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for episode in incoming {
            let previous = byID[episode.id]
            byID[episode.id] = CachedEpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropLocalPath: episode.backdropLocalPath ?? previous?.backdropLocalPath,
                backdropRemoteURL: episode.backdropRemoteURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath
            )
        }
        return byID.values.sorted {
            ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
        }
    }

    private static func sanitizePathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}

public enum MetadataCacheError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case downloadFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Application Support 目录不可用"
        case .downloadFailed(let url):
            return "下载图片失败：\(url.host ?? url.absoluteString)"
        }
    }
}
