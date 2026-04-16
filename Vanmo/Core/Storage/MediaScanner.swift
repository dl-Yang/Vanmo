import Foundation
import SwiftData
import AVFoundation

actor MediaScanner {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    @MainActor
    func scanLocalDirectory(_ directoryURL: URL, in context: ModelContext) async throws -> [MediaItem] {
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

            context.insert(item)
            newItems.append(item)

            VanmoLogger.library.info("Scanned: \(parsed.title)")
        }

        try context.save()
        VanmoLogger.library.info("Scan complete: \(newItems.count) new items found")
        return newItems
    }

    func scanRemoteDirectory(
        service: RemoteFileService,
        path: String,
        in context: ModelContext
    ) async throws -> [MediaItem] {
        let files = try await service.listDirectory(path: path)
        var newItems: [MediaItem] = []

        for file in files where file.isVideo {
            let streamURL = try await service.streamURL(for: file)
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

            await MainActor.run {
                context.insert(item)
            }
            newItems.append(item)
        }

        await MainActor.run {
            try? context.save()
        }

        return newItems
    }

    @MainActor
    func importServerMediaItems(
        _ serverItems: [ServerMediaItem],
        in context: ModelContext
    ) async throws -> [MediaItem] {
        let existingServerIds = try existingServerIds(in: context)
        var newItems: [MediaItem] = []

        for serverItem in serverItems {
            guard !existingServerIds.contains(serverItem.serverId) else { continue }

            let item = MediaItem(
                title: serverItem.title,
                fileURL: serverItem.streamURL,
                mediaType: serverItem.mediaType,
                fileSize: serverItem.fileSize,
                duration: serverItem.duration
            )

            item.serverId = serverItem.serverId
            item.seriesId = serverItem.seriesId
            item.originalTitle = serverItem.originalTitle
            item.year = serverItem.year
            item.overview = serverItem.overview
            item.posterURL = serverItem.posterURL
            item.backdropURL = serverItem.backdropURL
            item.rating = serverItem.rating
            item.genres = serverItem.genres
            item.director = serverItem.director
            item.cast = serverItem.cast
            item.originCountry = serverItem.originCountry
            item.tmdbID = serverItem.tmdbID
            item.showTitle = serverItem.showTitle
            item.seasonNumber = serverItem.seasonNumber
            item.episodeNumber = serverItem.episodeNumber
            item.episodeTitle = serverItem.episodeTitle

            context.insert(item)
            newItems.append(item)
        }

        try context.save()
        VanmoLogger.library.info("Imported \(newItems.count) media items from server")
        return newItems
    }

    // MARK: - Private

    @MainActor
    private func existingFileURLs(in context: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try context.fetch(descriptor)
        return Set(items.map { $0.fileURL.absoluteString })
    }

    @MainActor
    private func existingServerIds(in context: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try context.fetch(descriptor)
        return Set(items.compactMap(\.serverId))
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
