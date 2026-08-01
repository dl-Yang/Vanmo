import Foundation
import SwiftData

public struct ScanConnectionStats: Sendable {
    public let movieCount: Int
    public let tvEpisodeCount: Int
    public let otherCount: Int
    public let lowConfidenceCount: Int
    public let probedCount: Int
    public let pendingProbeCount: Int

    public init(
        movieCount: Int,
        tvEpisodeCount: Int,
        otherCount: Int,
        lowConfidenceCount: Int,
        probedCount: Int,
        pendingProbeCount: Int
    ) {
        self.movieCount = movieCount
        self.tvEpisodeCount = tvEpisodeCount
        self.otherCount = otherCount
        self.lowConfidenceCount = lowConfidenceCount
        self.probedCount = probedCount
        self.pendingProbeCount = pendingProbeCount
    }
}

public enum ScanLibraryQueries {
    public static let defaultLowConfidenceThreshold = 0.65

    public static func lowConfidenceItems(
        connectionId: UUID?,
        threshold: Double = defaultLowConfidenceThreshold
    ) -> FetchDescriptor<MediaItem> {
        let resolvedThreshold = threshold
        if let connectionId {
            return FetchDescriptor<MediaItem>(
                predicate: #Predicate<MediaItem> { item in
                    item.sourceConnectionId == connectionId
                        && item.identificationConfidence != nil
                        && item.identificationConfidence! < resolvedThreshold
                },
                sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
            )
        }
        return FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.identificationConfidence != nil
                    && item.identificationConfidence! < resolvedThreshold
            },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
    }

    @MainActor
    public static func stats(
        for connectionId: UUID,
        in context: ModelContext,
        lowConfidenceThreshold: Double = defaultLowConfidenceThreshold
    ) throws -> ScanConnectionStats {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.sourceConnectionId == connectionId
            }
        )
        let items = try context.fetch(descriptor)
        var movieCount = 0
        var tvEpisodeCount = 0
        var otherCount = 0
        var lowConfidenceCount = 0
        var probedCount = 0
        var pendingProbeCount = 0

        for item in items {
            switch item.mediaType {
            case .movie:
                movieCount += 1
            case .tvEpisode:
                tvEpisodeCount += 1
            default:
                otherCount += 1
            }
            if let confidence = item.identificationConfidence, confidence < lowConfidenceThreshold {
                lowConfidenceCount += 1
            }
            if item.probeStatus == ProbeStatus.success.rawValue {
                probedCount += 1
            } else if item.probeStatus == ProbeStatus.pending.rawValue {
                pendingProbeCount += 1
            }
        }

        return ScanConnectionStats(
            movieCount: movieCount,
            tvEpisodeCount: tvEpisodeCount,
            otherCount: otherCount,
            lowConfidenceCount: lowConfidenceCount,
            probedCount: probedCount,
            pendingProbeCount: pendingProbeCount
        )
    }
}
