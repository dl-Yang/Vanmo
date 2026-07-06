import Foundation
import SwiftData
import AVFoundation

public actor MediaScanner {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @MainActor
    public func scanLocalDirectory(_ directoryURL: URL, in context: ModelContext) async throws -> [MediaItem] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var newItems: [MediaItem] = []

        let existingURLs = try existingFileURLs(in: context)

        for case let fileURL as URL in enumerator {
            guard fileURL.isVideoFile else { continue }
            guard !existingURLs.contains(fileURL.absoluteString) else { continue }

            let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(attributes.fileSize ?? 0)

            let duration = await videoDuration(for: fileURL)
            let parsed = FileNameParser.parse(fileURL.lastPathComponent)

            let item = MediaItem(
                title: parsed.title,
                fileURL: fileURL,
                mediaType: parsed.isTV ? .tvEpisode : .movie,
                fileSize: fileSize,
                duration: duration
            )

            item.year = parsed.year
            item.seasonNumber = parsed.season
            item.episodeNumber = parsed.episode
            if parsed.isTV {
                item.showTitle = parsed.title
            }
            item.originalFileName = fileURL.lastPathComponent
            item.container = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension.lowercased()

            context.insert(item)
            newItems.append(item)

            VanmoLogger.library.info("Scanned: \(parsed.title)")
        }

        try context.save()
        VanmoLogger.library.info("Scan complete: \(newItems.count) new items found")
        return newItems
    }

    public func scanRemoteDirectory(
        service: RemoteFileService,
        path: String,
        connectionId: UUID? = nil,
        in context: ModelContext,
        maxDepth: Int = 8,
        batchSize: Int = 200
    ) async throws -> [MediaItem] {
        var existing = try await MainActor.run {
            try existingServerItemMap(connectionId: connectionId, in: context)
        }
        var newItems: [MediaItem] = []
        var pendingInBatch = 0

        var queue: [(path: String, depth: Int)] = [(path, 0)]
        var visited: Set<String> = []

        while !queue.isEmpty {
            try Task.checkCancellation()
            let (current, depth) = queue.removeFirst()

            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let files: [RemoteFile]
            do {
                files = try await service.listDirectory(path: current)
            } catch {
                VanmoLogger.library.error("Failed to list \(current): \(error.localizedDescription)")
                continue
            }

            for file in files {
                if file.isDirectory {
                    if depth < maxDepth {
                        queue.append((file.path, depth + 1))
                    }
                    continue
                }
                guard file.isVideo else { continue }
                let key = serverItemKey(serverId: file.path, connectionId: connectionId)
                if let existingItem = existing[key] {
                    if existingItem.sourceConnectionId == nil, let connectionId {
                        await MainActor.run {
                            existingItem.sourceConnectionId = connectionId
                        }
                        pendingInBatch += 1
                    }
                    continue
                }

                let streamURL: URL
                do {
                    if service.type.usesEphemeralStreamURLs {
                        streamURL = service.type.catalogPlaybackURL(serverPath: file.path)
                    } else {
                        streamURL = try await service.streamURL(for: file)
                    }
                } catch {
                    VanmoLogger.library.error("Failed to get stream URL for \(file.name): \(error.localizedDescription)")
                    continue
                }

                let parsed = FileNameParser.parse(file.name)

                let item = MediaItem(
                    title: parsed.title,
                    fileURL: streamURL,
                    mediaType: parsed.isTV ? .tvEpisode : .movie,
                    fileSize: file.size
                )
                item.year = parsed.year
                item.seasonNumber = parsed.season
                item.episodeNumber = parsed.episode
                if parsed.isTV {
                    item.showTitle = parsed.title
                }
                item.serverId = file.path
                item.sourceConnectionId = connectionId
                item.originalFileName = file.name
                let ext = (file.name as NSString).pathExtension
                item.container = ext.isEmpty ? nil : ext.lowercased()

                await MainActor.run { context.insert(item) }
                newItems.append(item)
                existing[key] = item
                pendingInBatch += 1

                if pendingInBatch >= batchSize {
                    await MainActor.run { try? context.save() }
                    pendingInBatch = 0
                }
            }
        }

        if pendingInBatch > 0 {
            await MainActor.run { try? context.save() }
        }

        VanmoLogger.library.info("Remote scan complete: \(newItems.count) new items found under \(path)")
        return newItems
    }

    @MainActor
    public func importServerMediaItems(
        _ serverItems: [ServerMediaItem],
        connectionId: UUID? = nil,
        in context: ModelContext
    ) async throws -> [MediaItem] {
        let existingMap = try existingServerItemMap(connectionId: connectionId, in: context)
        var newItems: [MediaItem] = []

        for serverItem in serverItems {
            let key = serverItemKey(serverId: serverItem.serverId, connectionId: connectionId)
            if let existing = existingMap[key] {
                apply(serverItem: serverItem, connectionId: connectionId, to: existing)
            } else {
                let item = MediaItem(
                    title: serverItem.title,
                    fileURL: serverItem.streamURL,
                    mediaType: serverItem.mediaType,
                    fileSize: serverItem.fileSize,
                    duration: serverItem.duration
                )
                apply(serverItem: serverItem, connectionId: connectionId, to: item)
                context.insert(item)
                newItems.append(item)
            }
        }

        try context.save()
        VanmoLogger.library.info("Imported \(newItems.count) new / updated \(serverItems.count - newItems.count) existing media items from server")
        return newItems
    }

    // MARK: - Private

    @MainActor
    private func apply(
        serverItem: ServerMediaItem,
        connectionId: UUID?,
        to item: MediaItem
    ) {
        item.title = serverItem.title
        item.originalTitle = serverItem.originalTitle
        item.year = serverItem.year
        item.overview = serverItem.overview
        item.posterURL = serverItem.posterURL
        item.backdropURL = serverItem.backdropURL
        item.logoURL = serverItem.logoURL
        item.rating = serverItem.rating
        item.mediaType = serverItem.mediaType
        item.fileURL = serverItem.streamURL
        item.fileSize = serverItem.fileSize
        item.originalFileName = serverItem.originalFileName
        item.container = serverItem.container
        if serverItem.duration > 0 {
            item.duration = serverItem.duration
        }
        item.genres = serverItem.genres
        item.director = serverItem.director
        item.cast = serverItem.cast
        item.originCountry = serverItem.originCountry
        item.tmdbID = serverItem.tmdbID
        item.serverId = serverItem.serverId
        if let connectionId {
            item.sourceConnectionId = connectionId
        }
        item.seriesId = serverItem.seriesId
        item.showTitle = serverItem.showTitle
        item.seasonNumber = serverItem.seasonNumber
        item.episodeNumber = serverItem.episodeNumber
        item.episodeTitle = serverItem.episodeTitle

        // Live API 元数据：服务器是 resume / favorite 的权威来源。
        if let serverPlayed = serverItem.lastPlayedAt {
            if let existingPlayed = item.lastPlayedAt {
                item.lastPlayedAt = max(serverPlayed, existingPlayed)
            } else {
                item.lastPlayedAt = serverPlayed
            }
        }
        if serverItem.lastPlaybackPosition > 0 {
            item.lastPlaybackPosition = serverItem.lastPlaybackPosition
        }
        if serverItem.isFavoriteOnServer {
            item.isFavorite = true
        }
    }

    @MainActor
    private func existingFileURLs(in context: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try context.fetch(descriptor)
        return Set(items.map { $0.fileURL.absoluteString })
    }

    @MainActor
    private func existingServerItemMap(
        connectionId: UUID?,
        in context: ModelContext
    ) throws -> [String: MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try context.fetch(descriptor)
        var map: [String: MediaItem] = [:]
        for item in items {
            if let sid = item.serverId {
                guard connectionId == nil || item.sourceConnectionId == connectionId else { continue }
                let key = serverItemKey(serverId: sid, connectionId: item.sourceConnectionId)
                map[key] = item
            }
        }
        return map
    }

    private nonisolated func serverItemKey(serverId: String, connectionId: UUID?) -> String {
        if let connectionId {
            return "\(connectionId.uuidString)::\(serverId)"
        }
        return serverId
    }

    private func videoDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds.isFinite ? duration.seconds : 0
        } catch {
            return 0
        }
    }
}
