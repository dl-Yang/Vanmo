import Combine
import Foundation
import SwiftData

@MainActor
public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    @Published public private(set) var tasks: [DownloadTaskSnapshot] = []
    @Published public private(set) var destination = DownloadPreferences.destination

    public var hasPausableTasks: Bool {
        tasks.contains { $0.status == .queued || $0.status == .downloading }
    }

    public var hasResumableTasks: Bool {
        tasks.contains { $0.status == .paused }
    }

    private let store: DownloadTaskStore
    private var modelContext: ModelContext?
    private var worker: Task<Void, Never>?
    private var isSuspended = false
    private var didRestore = false
    private var resolvedDirectories: [DownloadDestination: ResolvedDownloadDirectory] = [:]

    public init(storeRootDirectory: URL? = nil) {
        self.store = DownloadTaskStore(rootDirectory: storeRootDirectory)
    }

    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func restoreAndResume() async {
        guard !didRestore else {
            resume()
            return
        }
        didRestore = true
        do {
            var restored = try await store.load()
            for index in restored.indices where restored[index].status == .downloading {
                restored[index].status = .queued
                restored[index].updatedAt = Date()
            }
            tasks = restored.sorted { $0.createdAt > $1.createdAt }
            try await reconcilePartSizes()
            try await persist()
            resume()
        } catch {
            didRestore = false
            VanmoLogger.network.error("[Download] restore failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func enqueue(_ request: DownloadRequest) async throws -> UUID {
        let ids = try await enqueue([request])
        guard let id = ids.first else {
            throw DownloadError.sourceUnavailable
        }
        return id
    }

    @discardableResult
    public func enqueue(_ requests: [DownloadRequest]) async throws -> [UUID] {
        guard !requests.isEmpty else { return [] }
        var ids: [UUID] = []
        var didInsertTask = false

        for request in requests {
            if let duplicate = duplicateTask(for: request) {
                ids.append(duplicate.id)
                continue
            }

            let snapshot = DownloadTaskSnapshot(request: request, destination: destination)
            tasks.insert(snapshot, at: 0)
            ids.append(snapshot.id)
            didInsertTask = true
        }

        guard didInsertTask else { return ids }
        try await persist()
        startWorkerIfNeeded()
        return ids
    }

    public func retry(_ id: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        do {
            try await store.removePart(for: id)
            let completedURL = try completedFileURL(for: tasks[index])
            if FileManager.default.fileExists(atPath: completedURL.path) {
                try FileManager.default.removeItem(at: completedURL)
            }
            tasks[index].status = .queued
            tasks[index].receivedBytes = 0
            tasks[index].errorMessage = nil
            tasks[index].completedAt = nil
            tasks[index].updatedAt = Date()
            try await persist()
            startWorkerIfNeeded()
        } catch {
            markFailed(id, error: error)
            try? await persist()
        }
    }

    public func delete(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let cancelledActiveTask = tasks.contains { ids.contains($0.id) && $0.status == .downloading }
        if cancelledActiveTask {
            worker?.cancel()
        }

        for task in tasks where ids.contains(task.id) {
            try? await store.removePart(for: task.id)
            if task.status == .completed, let url = try? completedFileURL(for: task) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        tasks.removeAll { ids.contains($0.id) }
        try? await persist()
        if !cancelledActiveTask {
            startWorkerIfNeeded()
        }
    }

    public func pause(_ id: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .queued || tasks[index].status == .downloading else {
            return
        }
        let wasDownloading = tasks[index].status == .downloading
        tasks[index].status = .paused
        tasks[index].updatedAt = Date()
        if wasDownloading {
            worker?.cancel()
        }
        try? await persist()
    }

    public func resume(_ id: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .paused else {
            return
        }
        tasks[index].status = .queued
        tasks[index].updatedAt = Date()
        try? await persist()
        startWorkerIfNeeded()
    }

    public func pauseAll() async {
        let hasDownloadingTask = tasks.contains { $0.status == .downloading }
        var didChange = false
        for index in tasks.indices where tasks[index].status == .queued || tasks[index].status == .downloading {
            tasks[index].status = .paused
            tasks[index].updatedAt = Date()
            didChange = true
        }
        guard didChange else { return }
        if hasDownloadingTask {
            worker?.cancel()
        }
        try? await persist()
    }

    public func resumeAll() async {
        var didChange = false
        for index in tasks.indices where tasks[index].status == .paused {
            tasks[index].status = .queued
            tasks[index].updatedAt = Date()
            didChange = true
        }
        guard didChange else { return }
        try? await persist()
        startWorkerIfNeeded()
    }

    public func suspend() async {
        isSuspended = true
        worker?.cancel()
        if let index = tasks.firstIndex(where: { $0.status == .downloading }) {
            tasks[index].status = .queued
            tasks[index].updatedAt = Date()
        }
        try? await persist()
    }

    public func resume() {
        isSuspended = false
        startWorkerIfNeeded()
    }

    public func setCustomDirectory(_ url: URL) throws {
        try DownloadPreferences.setCustomDirectory(url)
        destination = DownloadPreferences.destination
    }

    public func useDefaultDirectory() {
        DownloadPreferences.useDefaultDirectory()
        destination = DownloadPreferences.destination
    }

    public func completedFileURL(for id: UUID) throws -> URL {
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw DownloadError.sourceUnavailable
        }
        return try completedFileURL(for: task)
    }

    // MARK: - Queue

    private func startWorkerIfNeeded() {
        guard !isSuspended, worker == nil, tasks.contains(where: { $0.status == .queued }) else {
            return
        }
        worker = Task { [weak self] in
            await self?.runQueue()
        }
    }

    private func runQueue() async {
        defer {
            worker = nil
            if !isSuspended {
                startWorkerIfNeeded()
            }
        }
        while !Task.isCancelled, !isSuspended,
              let id = tasks
                .filter({ $0.status == .queued })
                .min(by: { $0.createdAt < $1.createdAt })?
                .id {
            await runTask(id)
        }
    }

    private func runTask(_ id: UUID) async {
        update(id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        try? await persist()

        do {
            guard let task = tasks.first(where: { $0.id == id }) else { return }
            try await perform(task)
        } catch is CancellationError {
            restoreQueuedStatusAfterCancellation(id)
            try? await persist()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                restoreQueuedStatusAfterCancellation(id)
            } else {
                markFailed(id, error: error)
            }
            try? await persist()
        }
    }

    private func perform(_ task: DownloadTaskSnapshot) async throws {
        let partURL = try await store.partURL(for: task.id)
        try FileManager.default.createDirectory(
            at: partURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }

        if let localURL = task.request.sourceFileURL, localURL.isFileURL {
            try await copyLocalFile(localURL, to: partURL, taskID: task.id)
        } else {
            let (service, remoteFile, type) = try await connectedService(for: task.request)
            defer { Task { await service.disconnect() } }

            if type == .smb {
                guard let smbService = service as? SMBService else {
                    throw DownloadError.unsupportedSource
                }
                try await downloadSMB(service: smbService, file: remoteFile, to: partURL, taskID: task.id)
            } else if type == .ftp {
                guard let ftpService = service as? FTPService else {
                    throw DownloadError.unsupportedSource
                }
                try await downloadFTP(service: ftpService, file: remoteFile, to: partURL, taskID: task.id)
            } else if type == .sftp {
                guard let sftpService = service as? SFTPService else {
                    throw DownloadError.unsupportedSource
                }
                try await downloadSFTP(service: sftpService, file: remoteFile, to: partURL, taskID: task.id)
            } else {
                let url = try await service.streamURL(for: remoteFile)
                guard url.scheme == "http" || url.scheme == "https" else {
                    throw DownloadError.unsupportedSource
                }
                try await downloadHTTP(
                    initialURL: url,
                    refreshURL: { try await service.streamURL(for: remoteFile) },
                    connectionType: type,
                    connectionId: task.request.sourceConnectionId,
                    to: partURL,
                    taskID: task.id
                )
            }
        }

        try Task.checkCancellation()
        try await finish(taskID: task.id, partURL: partURL)
    }

    // MARK: - Sources

    private func connectedService(
        for request: DownloadRequest
    ) async throws -> (RemoteFileService, RemoteFile, ConnectionType) {
        guard let connectionId = request.sourceConnectionId,
              let modelContext else {
            throw DownloadError.missingConnection
        }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try modelContext.fetch(descriptor).first,
              connection.deletedAt == nil else {
            throw DownloadError.missingConnection
        }
        guard DownloadEligibility.isSupported(connectionType: connection.type) else {
            throw DownloadError.unsupportedSource
        }

        let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        let service = RemoteServiceFactory.create(for: connection.type)
        try await service.connect(config: ConnectionConfig(from: connection, password: password))
        let file = RemoteFile(
            name: request.fileName,
            path: request.remotePath,
            size: request.totalBytes,
            isDirectory: false,
            modifiedDate: nil,
            type: .video
        )
        return (service, file, connection.type)
    }

    private func copyLocalFile(_ sourceURL: URL, to partURL: URL, taskID: UUID) async throws {
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        let total = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        var offset = fileSize(at: partURL)
        if total > 0, offset > total {
            try truncate(partURL)
            offset = 0
        }
        try source.seek(toOffset: UInt64(offset))
        let destination = try FileHandle(forWritingTo: partURL)
        defer { try? destination.close() }
        try destination.seekToEnd()

        update(taskID) {
            if total > 0 { $0.totalBytes = total }
            $0.receivedBytes = offset
        }
        while true {
            try Task.checkCancellation()
            guard let data = try source.read(upToCount: 1_048_576), !data.isEmpty else { break }
            try destination.write(contentsOf: data)
            offset += Int64(data.count)
            update(taskID) { $0.receivedBytes = offset }
            try await persist()
        }
        try destination.synchronize()
    }

    private func downloadSMB(
        service: SMBService,
        file: RemoteFile,
        to partURL: URL,
        taskID: UUID
    ) async throws {
        try await service.downloadResuming(file: file, to: partURL) { [weak self] received, total in
            Task { @MainActor in
                self?.update(taskID) {
                    $0.receivedBytes = received
                    if total > 0 { $0.totalBytes = total }
                }
            }
        }
        let bytes = fileSize(at: partURL)
        update(taskID) {
            $0.receivedBytes = bytes
            if $0.totalBytes == 0 { $0.totalBytes = bytes }
        }
        try await persist()
    }

    private func downloadFTP(
        service: FTPService,
        file: RemoteFile,
        to partURL: URL,
        taskID: UUID
    ) async throws {
        try await service.downloadResuming(file: file, to: partURL) { [weak self] received, total in
            Task { @MainActor in
                self?.update(taskID) {
                    $0.receivedBytes = received
                    if total > 0 { $0.totalBytes = total }
                }
            }
        }
        let bytes = fileSize(at: partURL)
        update(taskID) {
            $0.receivedBytes = bytes
            if $0.totalBytes == 0 { $0.totalBytes = bytes }
        }
        try await persist()
    }

    private func downloadSFTP(
        service: SFTPService,
        file: RemoteFile,
        to partURL: URL,
        taskID: UUID
    ) async throws {
        try await service.downloadResuming(file: file, to: partURL) { [weak self] received, total in
            Task { @MainActor in
                self?.update(taskID) {
                    $0.receivedBytes = received
                    if total > 0 { $0.totalBytes = total }
                }
            }
        }
        let bytes = fileSize(at: partURL)
        update(taskID) {
            $0.receivedBytes = bytes
            if $0.totalBytes == 0 { $0.totalBytes = bytes }
        }
        try await persist()
    }

    private func downloadHTTP(
        initialURL: URL,
        refreshURL: () async throws -> URL,
        connectionType: ConnectionType,
        connectionId: UUID?,
        to partURL: URL,
        taskID: UUID
    ) async throws {
        var needsForcedRefresh = false
        var refreshedCurrentChunk = false
        var currentURL = initialURL
        var offset = fileSize(at: partURL)
        let chunkSize: Int64 = 4 * 1_024 * 1_024

        while true {
            try Task.checkCancellation()
            let provider = makeHeaderProvider(
                connectionType: connectionType,
                connectionId: connectionId,
                forceRefresh: needsForcedRefresh
            )
            let requestUsedForcedRefresh = needsForcedRefresh
            needsForcedRefresh = false
            let fetcher = RemoteFetcher(originalURL: currentURL, headerProvider: provider)
            let upperBound = offset + chunkSize - 1
            let (temporaryURL, response) = try await fetcher.downloadFile(
                forInclusiveRange: offset...upperBound
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard let http = response as? HTTPURLResponse else {
                throw DownloadError.invalidResponse
            }

            if (http.statusCode == 401 || http.statusCode == 403), !refreshedCurrentChunk {
                if connectionType == .googleDrive, !requestUsedForcedRefresh {
                    needsForcedRefresh = true
                }
                currentURL = try await refreshURL()
                refreshedCurrentChunk = true
                continue
            }
            if http.statusCode == 416 {
                let knownTotal = tasks.first(where: { $0.id == taskID })?.totalBytes ?? 0
                if knownTotal > 0, offset == knownTotal { break }
                throw DownloadError.httpStatus(416)
            }
            guard (200...299).contains(http.statusCode) else {
                throw DownloadError.httpStatus(http.statusCode)
            }

            if http.statusCode == 200, offset > 0 {
                try truncate(partURL)
                offset = 0
                refreshedCurrentChunk = false
                update(taskID) { $0.receivedBytes = 0 }
                try await persist()
                continue
            }

            if http.statusCode == 200 {
                try? FileManager.default.removeItem(at: partURL)
                try FileManager.default.copyItem(at: temporaryURL, to: partURL)
                offset = fileSize(at: partURL)
                update(taskID) {
                    $0.receivedBytes = offset
                    $0.totalBytes = offset
                }
                try await persist()
                break
            }

            guard http.statusCode == 206 else {
                throw DownloadError.httpStatus(http.statusCode)
            }
            guard let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                  let returnedRange = RemoteFetcher.parseContentRangeSlice(contentRange),
                  returnedRange.lowerBound == offset else {
                throw DownloadError.invalidResponse
            }
            let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
            let expectedCount = returnedRange.upperBound - returnedRange.lowerBound + 1
            guard Int64(data.count) == expectedCount else {
                throw DownloadError.invalidResponse
            }
            let handle = try FileHandle(forWritingTo: partURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            offset += Int64(data.count)

            let total = RemoteFetcher.parseContentRangeTotal(contentRange)
            update(taskID) {
                $0.receivedBytes = offset
                if let total { $0.totalBytes = total }
            }
            try await persist()
            refreshedCurrentChunk = false
            if let total, offset >= total { break }
            if data.isEmpty { throw DownloadError.invalidResponse }
        }
    }

    private func makeHeaderProvider(
        connectionType: ConnectionType,
        connectionId: UUID?,
        forceRefresh: Bool
    ) -> (() async -> [String: String])? {
        if connectionType == .baiduNetdisk {
            return { ["User-Agent": BaiduNetdiskService.requiredUserAgent] }
        }
        if connectionType == .googleDrive, let connectionId {
            return {
                let token = try? await OAuthCoordinator.shared.validAccessToken(
                    for: .googleDrive,
                    connectionId: connectionId,
                    forceRefresh: forceRefresh
                )
                return token.map { ["Authorization": "Bearer \($0)"] } ?? [:]
            }
        }
        return nil
    }

    // MARK: - Completion and persistence

    private func finish(taskID: UUID, partURL: URL) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let resolved = try resolvedDirectory(for: tasks[index].destination)
        let finalURL = uniqueDestinationURL(
            in: resolved.url,
            preferredName: tasks[index].localFileName,
            excluding: taskID
        )
        let temporaryURL = resolved.url.appendingPathComponent(".\(UUID().uuidString).download")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try FileManager.default.copyItem(at: partURL, to: temporaryURL)
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        try FileManager.default.removeItem(at: partURL)

        let size = fileSize(at: finalURL)
        tasks[index].localFileName = finalURL.lastPathComponent
        tasks[index].status = .completed
        tasks[index].receivedBytes = size
        tasks[index].totalBytes = size
        tasks[index].completedAt = Date()
        tasks[index].updatedAt = Date()
        try await persist()
    }

    private func completedFileURL(for task: DownloadTaskSnapshot) throws -> URL {
        let resolved = try resolvedDirectory(for: task.destination)
        return resolved.url.appendingPathComponent(task.localFileName)
    }

    private func resolvedDirectory(for destination: DownloadDestination) throws -> ResolvedDownloadDirectory {
        if let resolved = resolvedDirectories[destination] {
            return resolved
        }
        let resolved = try DownloadDirectoryResolver.resolve(destination)
        resolvedDirectories[destination] = resolved
        return resolved
    }

    private func completedFileExists(for task: DownloadTaskSnapshot) -> Bool {
        guard let url = try? completedFileURL(for: task) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func duplicateTask(for request: DownloadRequest) -> DownloadTaskSnapshot? {
        tasks.first {
            $0.request.sourceKey == request.sourceKey
                && ($0.status != .completed || completedFileExists(for: $0))
        }
    }

    private func uniqueDestinationURL(in directory: URL, preferredName: String, excluding id: UUID) -> URL {
        var candidate = directory.appendingPathComponent(preferredName)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var suffix = 1
        let reservedNames = Set(tasks.filter { $0.id != id && $0.status == .completed }.map(\.localFileName))
        while FileManager.default.fileExists(atPath: candidate.path) || reservedNames.contains(candidate.lastPathComponent) {
            let name = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }

    private func reconcilePartSizes() async throws {
        for index in tasks.indices where tasks[index].status != .completed {
            let partURL = try await store.partURL(for: tasks[index].id)
            tasks[index].receivedBytes = fileSize(at: partURL)
        }
    }

    private func persist() async throws {
        try await store.save(tasks)
    }

    private func update(_ id: UUID, mutate: (inout DownloadTaskSnapshot) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
        tasks[index].updatedAt = Date()
    }

    private func markFailed(_ id: UUID, error: Error) {
        update(id) {
            $0.status = .failed
            $0.errorMessage = error.localizedDescription
        }
    }

    private func restoreQueuedStatusAfterCancellation(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .downloading else {
            return
        }
        tasks[index].status = .queued
        tasks[index].updatedAt = Date()
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func truncate(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
    }
}
