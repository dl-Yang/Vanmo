import Foundation
import SwiftData
import VanmoCore

@MainActor
public final class ScanCoordinator: ObservableObject {
    @Published public private(set) var controlState: ScanControlState = .idle
    @Published public private(set) var progress: ScanProgress?
    @Published public private(set) var lastResult: ScanResult?

    private var scanTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var activeJob: ScanJobRecord?
    private var activeService: RemoteFileService?

    public init() {}

    public var isActive: Bool {
        controlState == .running || controlState == .paused || controlState == .cancelling
    }

    public func cancel() {
        guard isActive else { return }
        controlState = .cancelling
        scanTask?.cancel()
        resumeIfPaused()
    }

    public func pause() {
        guard controlState == .running else { return }
        controlState = .paused
        activeJob?.phase = .paused
        Task { await MediaProbeQueue.shared.pause() }
    }

    public func resume() {
        guard controlState == .paused else { return }
        controlState = .running
        activeJob?.phase = .scanning
        resumeIfPaused()
        Task { await MediaProbeQueue.shared.resume() }
    }

    public func start(
        connection: SavedConnection,
        service: RemoteFileService,
        scope: ScanScope,
        forceFullScan: Bool,
        modelContainer: ModelContainer,
        context: ModelContext,
        onFinished: ((ScanResult) -> Void)? = nil
    ) {
        cancel()
        controlState = .running
        activeService = service

        let options = RemoteScanOptions.forScope(scope, forceFullScan: forceFullScan, connectionType: connection.type)
        let rootPath = scope.rootPaths.first ?? connection.path ?? "/"
        let job = ScanJobRecord(
            connectionId: connection.id,
            connectionName: connection.name,
            rootPath: rootPath,
            isPartialScan: scope.isPartialScan,
            forceFullScan: forceFullScan
        )
        context.insert(job)
        activeJob = job

        scanTask = Task {
            let scanner = MediaScanner(modelContainer: modelContainer)
            let paths = scope.rootPaths.isEmpty ? [connection.path ?? "/"] : scope.rootPaths
            var aggregate = ScanResult(
                status: .completed,
                insertedItems: [],
                updatedCount: 0,
                unchangedCount: 0,
                prunedCount: 0,
                seenKeys: [],
                issues: []
            )

            do {
                for path in paths {
                    try Task.checkCancellation()
                    await waitIfPaused()

                    let result = try await scanner.scanRemoteDirectory(
                        service: service,
                        path: path,
                        connectionId: connection.id,
                        in: context,
                        options: options,
                        shouldPause: { [weak self] in
                            await self?.waitIfPaused() ?? ()
                        },
                        onProgress: { [weak self] progress in
                            Task { @MainActor in
                                self?.progress = progress
                                self?.update(job: job, with: progress)
                            }
                        }
                    )
                    aggregate = aggregate.merging(with: result)
                }

                job.phase = aggregate.status == .cancelled ? .cancelled : .completed
                job.updatedAt = Date()
                try? context.save()

                if !aggregate.probeCandidates.isEmpty {
                    job.phase = .probing
                    await MediaProbeQueue.shared.enqueue(items: aggregate.probeCandidates, in: context)
                }

                await finish(with: aggregate, onFinished: onFinished)
            } catch is CancellationError {
                job.phase = .cancelled
                job.updatedAt = Date()
                try? context.save()
                let cancelled = ScanResult(
                    status: .cancelled,
                    insertedItems: aggregate.insertedItems,
                    updatedCount: aggregate.updatedCount,
                    unchangedCount: aggregate.unchangedCount,
                    prunedCount: aggregate.prunedCount,
                    seenKeys: aggregate.seenKeys,
                    issues: aggregate.issues + [ScanIssue(kind: .cancelled, path: rootPath, message: "扫描已取消")],
                    stats: aggregate.stats,
                    probeCandidates: aggregate.probeCandidates
                )
                await finish(with: cancelled, onFinished: onFinished)
            } catch {
                job.phase = .failed
                job.lastError = error.localizedDescription
                job.updatedAt = Date()
                try? context.save()
                let failed = ScanResult(
                    status: .failed,
                    insertedItems: aggregate.insertedItems,
                    updatedCount: aggregate.updatedCount,
                    unchangedCount: aggregate.unchangedCount,
                    prunedCount: aggregate.prunedCount,
                    seenKeys: aggregate.seenKeys,
                    issues: aggregate.issues + [ScanIssue(kind: .directoryListFailed, path: rootPath, message: error.localizedDescription)],
                    stats: aggregate.stats,
                    probeCandidates: aggregate.probeCandidates
                )
                await finish(with: failed, onFinished: onFinished)
            }
        }
    }

    public func scanBookmarks(
        connection: SavedConnection,
        bookmarks: [FolderBookmark],
        service: RemoteFileService,
        forceFullScan: Bool,
        modelContainer: ModelContainer,
        context: ModelContext,
        onFinished: ((ScanResult) -> Void)? = nil
    ) {
        let paths = bookmarks
            .filter { $0.connectionId == connection.id && $0.deletedAt == nil }
            .map(\.path)
        start(
            connection: connection,
            service: service,
            scope: .bookmarks(paths: paths),
            forceFullScan: forceFullScan,
            modelContainer: modelContainer,
            context: context,
            onFinished: onFinished
        )
    }

    private func finish(with result: ScanResult, onFinished: ((ScanResult) -> Void)?) async {
        await MainActor.run {
            lastResult = result
            controlState = .idle
            progress = nil
            activeJob = nil
            activeService = nil
            onFinished?(result)
        }
    }

    private func waitIfPaused() async {
        while controlState == .paused {
            await withCheckedContinuation { continuation in
                pauseContinuation = continuation
            }
        }
    }

    private func resumeIfPaused() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    private func update(job: ScanJobRecord, with progress: ScanProgress) {
        job.scannedDirectories = progress.scannedDirectories
        job.discoveredVideos = progress.discoveredVideos
        job.insertedCount = progress.insertedCount
        job.updatedCount = progress.updatedCount
        job.unchangedCount = progress.unchangedCount
        job.currentDirectory = progress.currentDirectory
        job.updatedAt = Date()
    }
}

private extension ScanResult {
    func merging(with other: ScanResult) -> ScanResult {
        let status: ScanCompletionStatus
        if self.status == .cancelled || other.status == .cancelled {
            status = .cancelled
        } else if self.status == .partial || other.status == .partial {
            status = .partial
        } else if self.status == .failed || other.status == .failed {
            status = .failed
        } else {
            status = .completed
        }

        return ScanResult(
            status: status,
            insertedItems: insertedItems + other.insertedItems,
            updatedCount: updatedCount + other.updatedCount,
            unchangedCount: unchangedCount + other.unchangedCount,
            prunedCount: prunedCount + other.prunedCount,
            seenKeys: seenKeys.union(other.seenKeys),
            issues: issues + other.issues,
            stats: stats.merging(with: other.stats),
            probeCandidates: probeCandidates + other.probeCandidates
        )
    }
}
