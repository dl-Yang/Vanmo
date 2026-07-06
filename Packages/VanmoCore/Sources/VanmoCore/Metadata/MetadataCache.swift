import Foundation

public actor MetadataCache {
    public static let shared = MetadataCache()

    private let cacheDirectoryName = "Vanmo"
    private let metadataDirectoryName = "MetadataCache"
    private let indexFileName = "index.json"
    private let imagesDirectoryName = "images"

    private var index = MetadataCacheIndex()

    public func load(for key: MetadataCacheKey) -> MetadataCacheRecord? {
        loadIndexIfNeeded()
        return index.records[key.cacheKey]
    }

    public func rootDirectoryURL() throws -> URL {
        try metadataRootURL(createDirectoryIfNeeded: false)
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
            updated.castMembers = try await withThrowingTaskGroup(of: CachedCastMember.self) { group in
                for member in record.castMembers {
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
                            VanmoLogger.metadata.error("[MetadataCache] cast profile download failed: \(error.localizedDescription)")
                            return member
                        }
                    }
                }

                var results: [CachedCastMember] = []
                for try await member in group {
                    results.append(member)
                }
                return results
            }
        }

        if !record.episodes.isEmpty {
            let episodeRoot = imageRoot.appendingPathComponent("episodes", isDirectory: true)
            try FileManager.default.createDirectory(at: episodeRoot, withIntermediateDirectories: true)

            let sanitizedKey = sanitizePathComponent(record.key.cacheKey)
            let imagesDir = imagesDirectoryName
            updated.episodes = try await withThrowingTaskGroup(of: CachedEpisodeInfo.self) { group in
                for episode in record.episodes {
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
                                backdropRemoteURL: episode.backdropRemoteURL
                            )
                        } catch {
                            VanmoLogger.metadata.error("[MetadataCache] episode backdrop download failed: \(error.localizedDescription)")
                            return episode
                        }
                    }
                }

                var results: [CachedEpisodeInfo] = []
                for try await episode in group {
                    results.append(episode)
                }
                return results.sorted {
                    ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
                }
            }
        }

        updated.fetchedAt = Date()
        index.records[record.key.cacheKey] = updated
        try persistIndex()
        return updated
    }

    public func deleteAll() throws {
        let root = try metadataRootURL(createDirectoryIfNeeded: false)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        index = MetadataCacheIndex()
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
