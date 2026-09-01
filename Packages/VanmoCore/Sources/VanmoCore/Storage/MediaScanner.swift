import Foundation
import SwiftData

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

            let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = Int64(attributes.fileSize ?? 0)

            let remoteFile = RemoteFile(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                size: fileSize,
                isDirectory: false,
                modifiedDate: attributes.contentModificationDate,
                type: .video
            )

            guard let item = MediaItemFactory.makeMediaItem(
                from: remoteFile,
                streamURL: fileURL,
                connectionId: nil,
                directoryPath: fileURL.deletingLastPathComponent().path
            ) else { continue }

            context.insert(item)
            newItems.append(item)
            VanmoLogger.library.info("Scanned: \(item.title)")
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
        options: RemoteScanOptions = RemoteScanOptions(),
        shouldPause: (@Sendable () async -> Void)? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanResult {
        let existing = try await MainActor.run {
            try existingServerItemMap(connectionId: connectionId, in: context)
        }

        let state = RemoteScanAccumulator(
            options: options,
            connectionId: connectionId,
            rootPath: path,
            existing: existing
        )

        let maxWorkers = options.maxConcurrentDirectories
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<maxWorkers {
                group.addTask {
                    await self.scanWorker(
                        service: service,
                        state: state,
                        context: context,
                        shouldPause: shouldPause,
                        onProgress: onProgress
                    )
                }
            }
        }

        let snapshot = await state.snapshot(rootPath: path)
        await flushBatchIfNeeded(context: context, pendingInBatch: snapshot.pendingInBatch, force: true)

        let status: ScanCompletionStatus
        if snapshot.wasCancelled {
            status = .cancelled
        } else if !snapshot.issues.isEmpty {
            status = .partial
        } else {
            status = .completed
        }

        var prunedCount = 0
        let canPrune = options.pruneMissing
            && !options.isPartialScan
            && status == .completed
            && snapshot.issues.isEmpty
            && connectionId != nil

        if canPrune, let connectionId {
            prunedCount = try await MainActor.run {
                try pruneMissingItems(
                    connectionId: connectionId,
                    seenKeys: snapshot.seenKeys,
                    in: context
                )
            }
            if prunedCount > 0 {
                try await MainActor.run { try context.save() }
            }
        }

        VanmoLogger.library.info(
            "Remote scan finished under \(path): inserted=\(snapshot.insertedItems.count) updated=\(snapshot.updatedCount) unchanged=\(snapshot.unchangedCount) pruned=\(prunedCount) status=\(status.rawValue)"
        )

        onProgress?(ScanProgress(
            scannedDirectories: snapshot.scannedDirectories,
            discoveredVideos: snapshot.discoveredVideos,
            insertedCount: snapshot.insertedItems.count,
            updatedCount: snapshot.updatedCount,
            unchangedCount: snapshot.unchangedCount,
            prunedCount: prunedCount,
            currentDirectory: path,
            stats: snapshot.stats
        ))

        return ScanResult(
            status: status,
            insertedItems: snapshot.insertedItems,
            updatedCount: snapshot.updatedCount,
            unchangedCount: snapshot.unchangedCount,
            prunedCount: prunedCount,
            seenKeys: snapshot.seenKeys,
            issues: snapshot.issues,
            stats: snapshot.stats,
            probeCandidates: snapshot.probeCandidates
        )
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

    // MARK: - Workers

    private func scanWorker(
        service: RemoteFileService,
        state: RemoteScanAccumulator,
        context: ModelContext,
        shouldPause: (@Sendable () async -> Void)?,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) async {
        while let work = await state.claimNextDirectory() {
            let (current, depth) = work

            do {
                try Task.checkCancellation()
            } catch {
                await state.markCancelled()
                await state.recordIssue(ScanIssue(kind: .cancelled, path: current, message: error.localizedDescription))
                break
            }

            if let shouldPause {
                await shouldPause()
            }

            let files: [RemoteFile]
            do {
                await RemoteRequestLimiter.shared.acquire(for: service.type)
                files = try await service.listDirectory(path: current)
            } catch {
                VanmoLogger.library.error("Failed to list \(current): \(error.localizedDescription)")
                await state.recordIssue(ScanIssue(
                    kind: .directoryListFailed,
                    path: current,
                    message: error.localizedDescription
                ))
                continue
            }

            await state.markDirectoryScanned(current)
            let progressSnapshot = await state.progressSnapshot(currentDirectory: current)
            onProgress?(progressSnapshot)

            let nfoByFileName = await loadNFOMap(from: files, service: service, directoryPath: current)

            for file in files {
                if file.isDirectory {
                    let maxDepth = await state.maxDepth
                    if depth < maxDepth {
                        await state.enqueueDirectory(file.path, depth: depth + 1)
                    }
                    continue
                }

                guard file.isVideo else { continue }
                await state.markVideoDiscovered()

                let activeConnectionId = await state.connectionId
                let key = serverItemKey(serverId: file.path, connectionId: activeConnectionId)
                await state.markSeen(key: key)

                let storageURL = PlaybackURLResolver.storageURL(for: file, service: service)

                if let existingItem = await state.existingItem(for: key) {
                    if existingItem.sourceConnectionId == nil, let activeConnectionId {
                        await MainActor.run {
                            existingItem.sourceConnectionId = activeConnectionId
                        }
                        await state.incrementPendingBatch()
                    }

                    let forceFullScan = await state.forceFullScan
                    let changed = MediaItemFactory.remoteFileChanged(
                        existing: existingItem,
                        file: file,
                        forceFullScan: forceFullScan
                    )

                    if !changed {
                        await state.incrementUnchanged()
                        continue
                    }

                    await MainActor.run {
                        MediaItemFactory.applyRemoteFileMetadata(
                            file,
                            streamURL: storageURL,
                            connectionId: activeConnectionId,
                            directoryPath: current,
                            nfoByFileName: nfoByFileName,
                            to: existingItem
                        )
                    }
                    await state.recordUpdated(existingItem)
                    await flushBatchIfNeeded(context: context, pendingInBatch: await state.pendingBatchCount(), force: false, batchSize: await state.batchSize, reset: { await state.resetPendingBatch() })
                    continue
                }

                guard let item = MediaItemFactory.makeMediaItem(
                    from: file,
                    streamURL: storageURL,
                    connectionId: activeConnectionId,
                    directoryPath: current,
                    nfoByFileName: nfoByFileName
                ) else {
                    continue
                }

                await MainActor.run { context.insert(item) }
                await state.recordInserted(item, key: key)
                await flushBatchIfNeeded(context: context, pendingInBatch: await state.pendingBatchCount(), force: false, batchSize: await state.batchSize, reset: { await state.resetPendingBatch() })
            }
        }
    }

    private func flushBatchIfNeeded(
        context: ModelContext,
        pendingInBatch: Int,
        force: Bool,
        batchSize: Int = 200,
        reset: (() async -> Void)? = nil
    ) async {
        guard force || pendingInBatch >= batchSize else { return }
        guard pendingInBatch > 0 else { return }
        await MainActor.run { try? context.save() }
        if let reset {
            await reset()
        }
    }

    private func loadNFOMap(
        from files: [RemoteFile],
        service: RemoteFileService,
        directoryPath: String
    ) async -> [String: ParsedNFOMetadata] {
        var map: [String: ParsedNFOMetadata] = [:]

        for file in files where NFOMetadataParser.isNFOFileName(file.name) {
            guard file.size <= 512 * 1024 else { continue }

            if let data = await readNFOData(for: file, service: service),
               let parsed = NFOMetadataParser.parse(data: data, fileName: file.name) {
                map[file.name.lowercased()] = parsed
            }
        }

        return map
    }

    private func readNFOData(for file: RemoteFile, service: RemoteFileService) async -> Data? {
        if service.type == .localFolder {
            let url = URL(fileURLWithPath: file.path)
            return try? Data(contentsOf: url)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("nfo")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            await RemoteRequestLimiter.shared.acquire(for: service.type)
            try await service.download(file: file, to: tempURL) { _ in }
            return try Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }

    @MainActor
    private func pruneMissingItems(
        connectionId: UUID,
        seenKeys: Set<String>,
        in context: ModelContext
    ) throws -> Int {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.sourceConnectionId == connectionId
            }
        )
        let items = try context.fetch(descriptor)
        var removed = 0

        for item in items {
            guard let serverId = item.serverId else { continue }
            let key = serverItemKey(serverId: serverId, connectionId: connectionId)
            if !seenKeys.contains(key) {
                context.delete(item)
                removed += 1
            }
        }

        return removed
    }

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
        if let contentRating = serverItem.contentRating, !contentRating.isEmpty {
            item.contentRating = contentRating
        }
        item.mediaType = serverItem.mediaType
        item.fileURL = serverItem.streamURL
        item.fileSize = serverItem.fileSize
        item.originalFileName = serverItem.originalFileName
        item.container = serverItem.container
        if let width = serverItem.videoWidth, width > 0 {
            item.videoWidth = width
        }
        if let height = serverItem.videoHeight, height > 0 {
            item.videoHeight = height
        }
        if let dynamicRange = serverItem.dynamicRange, !dynamicRange.isEmpty {
            item.dynamicRange = dynamicRange
        }
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
}

// MARK: - Scan accumulator

private actor RemoteScanAccumulator {
    struct Snapshot {
        let insertedItems: [MediaItem]
        let updatedCount: Int
        let unchangedCount: Int
        let seenKeys: Set<String>
        let issues: [ScanIssue]
        let scannedDirectories: Int
        let discoveredVideos: Int
        let stats: ScanProgressStats
        let probeCandidates: [MediaItem]
        let pendingInBatch: Int
        let wasCancelled: Bool
    }

    let options: RemoteScanOptions
    let connectionId: UUID?
    var existing: [String: MediaItem]

    private var queue: [(path: String, depth: Int)]
    private var queueIndex = 0
    private var visited: Set<String> = []
    private var seenKeys: Set<String> = []
    private var insertedItems: [MediaItem] = []
    private var probeCandidates: [MediaItem] = []
    private var updatedCount = 0
    private var unchangedCount = 0
    private var issues: [ScanIssue] = []
    private var scannedDirectories = 0
    private var discoveredVideos = 0
    private var pendingInBatch = 0
    private var wasCancelled = false
    private var movieCount = 0
    private var tvEpisodeCount = 0
    private var otherCount = 0
    private var lowConfidenceCount = 0

    init(options: RemoteScanOptions, connectionId: UUID?, rootPath: String, existing: [String: MediaItem]) {
        self.options = options
        self.connectionId = connectionId
        self.existing = existing
        self.queue = [(rootPath, 0)]
    }

    var maxDepth: Int { options.maxDepth }
    var batchSize: Int { options.batchSize }
    var forceFullScan: Bool { options.forceFullScan }

    func claimNextDirectory() -> (String, Int)? {
        while queueIndex < queue.count {
            let item = queue[queueIndex]
            queueIndex += 1
            if visited.insert(item.path).inserted {
                return item
            }
        }
        return nil
    }

    func enqueueDirectory(_ path: String, depth: Int) {
        queue.append((path, depth))
    }

    func existingItem(for key: String) -> MediaItem? {
        existing[key]
    }

    func markSeen(key: String) {
        seenKeys.insert(key)
    }

    func markDirectoryScanned(_ path: String) {
        scannedDirectories += 1
    }

    func markVideoDiscovered() {
        discoveredVideos += 1
    }

    func incrementUnchanged() {
        unchangedCount += 1
    }

    func incrementPendingBatch() {
        pendingInBatch += 1
    }

    func pendingBatchCount() -> Int { pendingInBatch }

    func resetPendingBatch() {
        pendingInBatch = 0
    }

    func recordIssue(_ issue: ScanIssue) {
        issues.append(issue)
    }

    func markCancelled() {
        wasCancelled = true
    }

    func recordInserted(_ item: MediaItem, key: String) {
        insertedItems.append(item)
        existing[key] = item
        pendingInBatch += 1
        trackStats(for: item)
        if MediaProbeApplicator.shouldProbe(item: item) {
            probeCandidates.append(item)
        }
    }

    func recordUpdated(_ item: MediaItem) {
        updatedCount += 1
        pendingInBatch += 1
        trackStats(for: item)
        if MediaProbeApplicator.shouldProbe(item: item) {
            probeCandidates.append(item)
        }
    }

    private func trackStats(for item: MediaItem) {
        switch item.mediaType {
        case .movie:
            movieCount += 1
        case .tvEpisode:
            tvEpisodeCount += 1
        default:
            otherCount += 1
        }
        if let confidence = item.identificationConfidence,
           confidence < ScanLibraryQueries.defaultLowConfidenceThreshold {
            lowConfidenceCount += 1
        }
    }

    func progressSnapshot(currentDirectory: String) -> ScanProgress {
        ScanProgress(
            scannedDirectories: scannedDirectories,
            discoveredVideos: discoveredVideos,
            insertedCount: insertedItems.count,
            updatedCount: updatedCount,
            unchangedCount: unchangedCount,
            currentDirectory: currentDirectory,
            stats: ScanProgressStats(
                movieCount: movieCount,
                tvEpisodeCount: tvEpisodeCount,
                otherCount: otherCount,
                lowConfidenceCount: lowConfidenceCount
            )
        )
    }

    func snapshot(rootPath: String) -> Snapshot {
        Snapshot(
            insertedItems: insertedItems,
            updatedCount: updatedCount,
            unchangedCount: unchangedCount,
            seenKeys: seenKeys,
            issues: issues,
            scannedDirectories: scannedDirectories,
            discoveredVideos: discoveredVideos,
            stats: ScanProgressStats(
                movieCount: movieCount,
                tvEpisodeCount: tvEpisodeCount,
                otherCount: otherCount,
                lowConfidenceCount: lowConfidenceCount
            ),
            probeCandidates: probeCandidates,
            pendingInBatch: pendingInBatch,
            wasCancelled: wasCancelled
        )
    }
}
