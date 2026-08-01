import Foundation

public enum ScanControlState: Sendable {
    case idle
    case running
    case paused
    case cancelling
}

public enum ScanIssueKind: String, Sendable {
    case directoryListFailed
    case streamURLFailed
    case probeFailed
    case cancelled
}

public struct ScanIssue: Sendable, Equatable {
    public let kind: ScanIssueKind
    public let path: String
    public let message: String

    public init(kind: ScanIssueKind, path: String, message: String) {
        self.kind = kind
        self.path = path
        self.message = message
    }
}

public struct ScanProgressStats: Sendable {
    public let movieCount: Int
    public let tvEpisodeCount: Int
    public let otherCount: Int
    public let lowConfidenceCount: Int
    public let probedCount: Int
    public let probeFailedCount: Int

    public init(
        movieCount: Int = 0,
        tvEpisodeCount: Int = 0,
        otherCount: Int = 0,
        lowConfidenceCount: Int = 0,
        probedCount: Int = 0,
        probeFailedCount: Int = 0
    ) {
        self.movieCount = movieCount
        self.tvEpisodeCount = tvEpisodeCount
        self.otherCount = otherCount
        self.lowConfidenceCount = lowConfidenceCount
        self.probedCount = probedCount
        self.probeFailedCount = probeFailedCount
    }

    public static let empty = ScanProgressStats()

    public func merging(with other: ScanProgressStats) -> ScanProgressStats {
        ScanProgressStats(
            movieCount: movieCount + other.movieCount,
            tvEpisodeCount: tvEpisodeCount + other.tvEpisodeCount,
            otherCount: otherCount + other.otherCount,
            lowConfidenceCount: lowConfidenceCount + other.lowConfidenceCount,
            probedCount: probedCount + other.probedCount,
            probeFailedCount: probeFailedCount + other.probeFailedCount
        )
    }
}

public struct ScanProgress: Sendable {
    public let scannedDirectories: Int
    public let discoveredVideos: Int
    public let insertedCount: Int
    public let updatedCount: Int
    public let unchangedCount: Int
    public let prunedCount: Int
    public let currentDirectory: String
    public let stats: ScanProgressStats

    public init(
        scannedDirectories: Int,
        discoveredVideos: Int,
        insertedCount: Int,
        updatedCount: Int,
        unchangedCount: Int,
        prunedCount: Int = 0,
        currentDirectory: String,
        stats: ScanProgressStats = .empty
    ) {
        self.scannedDirectories = scannedDirectories
        self.discoveredVideos = discoveredVideos
        self.insertedCount = insertedCount
        self.updatedCount = updatedCount
        self.unchangedCount = unchangedCount
        self.prunedCount = prunedCount
        self.currentDirectory = currentDirectory
        self.stats = stats
    }

    public var summaryMessage: String {
        let current = (currentDirectory as NSString).lastPathComponent
        let location = current.isEmpty ? currentDirectory : current
        if insertedCount > 0 || updatedCount > 0 {
            return "已扫描 \(scannedDirectories) 个目录，新增 \(insertedCount) / 更新 \(updatedCount) · \(location)"
        }
        return "已扫描 \(scannedDirectories) 个目录，发现 \(discoveredVideos) 个视频 · \(location)"
    }

    public var completionSummary: String {
        switch (insertedCount, updatedCount, prunedCount, stats.lowConfidenceCount) {
        case (0, 0, 0, 0):
            return "同步完成，未发现新变化"
        default:
            var parts: [String] = []
            if insertedCount > 0 { parts.append("新增 \(insertedCount)") }
            if updatedCount > 0 { parts.append("更新 \(updatedCount)") }
            if prunedCount > 0 { parts.append("移除 \(prunedCount)") }
            if stats.lowConfidenceCount > 0 { parts.append("待确认 \(stats.lowConfidenceCount)") }
            return "同步完成：" + parts.joined(separator: " · ")
        }
    }
}

public enum ScanCompletionStatus: String, Sendable {
    case completed
    case partial
    case cancelled
    case failed
}

public struct ScanResult {
    public let status: ScanCompletionStatus
    public let insertedItems: [MediaItem]
    public let updatedCount: Int
    public let unchangedCount: Int
    public let prunedCount: Int
    public let seenKeys: Set<String>
    public let issues: [ScanIssue]
    public let stats: ScanProgressStats
    public let probeCandidates: [MediaItem]

    public init(
        status: ScanCompletionStatus,
        insertedItems: [MediaItem],
        updatedCount: Int,
        unchangedCount: Int,
        prunedCount: Int,
        seenKeys: Set<String>,
        issues: [ScanIssue],
        stats: ScanProgressStats = .empty,
        probeCandidates: [MediaItem] = []
    ) {
        self.status = status
        self.insertedItems = insertedItems
        self.updatedCount = updatedCount
        self.unchangedCount = unchangedCount
        self.prunedCount = prunedCount
        self.seenKeys = seenKeys
        self.issues = issues
        self.stats = stats
        self.probeCandidates = probeCandidates
    }

    public var hasLibraryChanges: Bool {
        !insertedItems.isEmpty || updatedCount > 0 || prunedCount > 0
    }

    public var allowsPrune: Bool {
        status == .completed && issues.isEmpty
    }
}

public struct RemoteScanOptions: Sendable {
    public let maxDepth: Int
    public let batchSize: Int
    public let forceFullScan: Bool
    public let pruneMissing: Bool
    public let isPartialScan: Bool
    public let maxConcurrentDirectories: Int

    public init(
        maxDepth: Int = 8,
        batchSize: Int = 200,
        forceFullScan: Bool = false,
        pruneMissing: Bool = false,
        isPartialScan: Bool = false,
        maxConcurrentDirectories: Int = 2
    ) {
        self.maxDepth = maxDepth
        self.batchSize = batchSize
        self.forceFullScan = forceFullScan
        self.pruneMissing = pruneMissing
        self.isPartialScan = isPartialScan
        self.maxConcurrentDirectories = max(1, maxConcurrentDirectories)
    }

    public static func forConnectionRoot(forceFullScan: Bool, connectionType: ConnectionType? = nil) -> RemoteScanOptions {
        RemoteScanOptions(
            forceFullScan: forceFullScan,
            pruneMissing: true,
            isPartialScan: false,
            maxConcurrentDirectories: connectionType?.serviceCapabilities.maxConcurrentDirectoryReads ?? 2
        )
    }

    public static func forPartialDirectory(
        forceFullScan: Bool = false,
        connectionType: ConnectionType? = nil
    ) -> RemoteScanOptions {
        RemoteScanOptions(
            forceFullScan: forceFullScan,
            pruneMissing: false,
            isPartialScan: true,
            maxConcurrentDirectories: connectionType?.serviceCapabilities.maxConcurrentDirectoryReads ?? 2
        )
    }
}
