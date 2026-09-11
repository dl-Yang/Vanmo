import Foundation

public struct ScannedShowGroupKey: Hashable, Sendable {
    public let connectionId: UUID?
    public let parentDirectory: String
    public let showTitle: String

    public init(connectionId: UUID?, parentDirectory: String, showTitle: String) {
        self.connectionId = connectionId
        self.parentDirectory = parentDirectory
        self.showTitle = showTitle
    }

    public var id: String {
        "\(connectionId?.uuidString ?? "")|\(parentDirectory)|\(showTitle)"
    }
}

public struct ScannedShowSummary: Identifiable, Sendable, Equatable {
    public let connectionId: UUID?
    public let parentDirectory: String
    public let title: String
    public let episodeCount: Int
    public let posterURL: URL?
    public let rating: Double?
    public let representativeServerId: String?

    public var id: String {
        "\(connectionId?.uuidString ?? "")|\(parentDirectory)|\(title)"
    }

    public var groupKey: ScannedShowGroupKey {
        ScannedShowGroupKey(
            connectionId: connectionId,
            parentDirectory: parentDirectory,
            showTitle: title
        )
    }

    public init(
        connectionId: UUID?,
        parentDirectory: String,
        title: String,
        episodeCount: Int,
        posterURL: URL?,
        rating: Double?,
        representativeServerId: String?
    ) {
        self.connectionId = connectionId
        self.parentDirectory = parentDirectory
        self.title = title
        self.episodeCount = episodeCount
        self.posterURL = posterURL
        self.rating = rating
        self.representativeServerId = representativeServerId
    }
}

public enum ScannedShowGrouping {
    public static func normalizedShowTitle(for item: MediaItem) -> String {
        let rawTitle = item.showTitle ?? item.title
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? item.displayTitle : trimmed
    }

    public static func parentDirectory(for item: MediaItem) -> String {
        MediaItemFactory.parentDirectoryPath(for: item.serverId ?? "")
    }

    public static func groupKey(for item: MediaItem) -> ScannedShowGroupKey {
        ScannedShowGroupKey(
            connectionId: item.sourceConnectionId,
            parentDirectory: parentDirectory(for: item),
            showTitle: normalizedShowTitle(for: item)
        )
    }

    public static func episodeSortPredicate(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let lhsSeason = lhs.seasonNumber ?? Int.max
        let rhsSeason = rhs.seasonNumber ?? Int.max
        if lhsSeason != rhsSeason {
            return lhsSeason < rhsSeason
        }

        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode {
            return lhsEpisode < rhsEpisode
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    public static func episodeItems(from items: [MediaItem]) -> [MediaItem] {
        items.filter { $0.mediaType == .tvEpisode || $0.mediaType == .tvShow }
    }

    public static func groupedEpisodes(from items: [MediaItem]) -> [ScannedShowGroupKey: [MediaItem]] {
        Dictionary(grouping: episodeItems(from: items), by: groupKey(for:))
    }

    public static func summaries(from items: [MediaItem]) -> [ScannedShowSummary] {
        groupedEpisodes(from: items).compactMap { key, episodes in
            guard let representative = episodes.sorted(by: episodeSortPredicate).first else {
                return nil
            }
            return ScannedShowSummary(
                connectionId: key.connectionId,
                parentDirectory: key.parentDirectory,
                title: key.showTitle,
                episodeCount: episodes.count,
                posterURL: representative.posterURL,
                rating: representative.rating,
                representativeServerId: representative.serverId
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public static func previewItems(from items: [MediaItem]) -> [MediaItem] {
        groupedEpisodes(from: items).compactMap { key, episodes in
            guard let representative = episodes.sorted(by: episodeSortPredicate).first else {
                return nil
            }
            let latestAddedAt = episodes.map(\.addedAt).max() ?? representative.addedAt
            let item = MediaItem(
                title: key.showTitle,
                fileURL: representative.fileURL,
                mediaType: .tvShow,
                fileSize: representative.fileSize,
                duration: representative.duration
            )
            item.posterURL = representative.posterURL
            item.backdropURL = representative.backdropURL
            item.year = representative.year
            item.rating = representative.rating
            item.showTitle = key.showTitle
            item.sourceConnectionId = representative.sourceConnectionId
            item.serverId = representative.serverId
            item.addedAt = latestAddedAt
            return item
        }
    }

    public static func episodes(
        from items: [MediaItem],
        connectionId: UUID,
        showTitle: String,
        parentDirectory: String
    ) -> [MediaItem] {
        let key = ScannedShowGroupKey(
            connectionId: connectionId,
            parentDirectory: parentDirectory,
            showTitle: showTitle
        )
        return episodeItems(from: items)
            .filter { groupKey(for: $0) == key }
            .sorted(by: episodeSortPredicate)
    }
}
