#if DEBUG
import Foundation
import SwiftData

/// Debug-only local fixtures so an empty library can still open media detail
/// and exercise the download hero path. Activated by `VANMO_DEBUG_HERO_WALK`.
public enum DownloadHeroWalkFixtures {
    public static let environmentKey = "VANMO_DEBUG_HERO_WALK"
    public static let autoEnqueueKey = "VANMO_DEBUG_HERO_AUTO"
    /// Caps local-file copy speed so a fixture walk can still-frame Compact / Expanded.
    public static let bytesPerSecondKey = "VANMO_DEBUG_HERO_BPS"
    public static let movieTitle = "Hero Walk Movie"
    public static let showTitle = "Hero Walk Show"

    public enum Kind: String {
        case movie
        case series
    }

    public static var requestedKind: Kind? {
        Kind(rawValue: (ProcessInfo.processInfo.environment[environmentKey] ?? "").lowercased())
    }

    public static var shouldAutoEnqueue: Bool {
        ProcessInfo.processInfo.environment[autoEnqueueKey] == "1"
    }

    public static var copyBytesPerSecond: Int? {
        guard let raw = ProcessInfo.processInfo.environment[bytesPerSecondKey],
              let value = Int(raw), value > 0
        else { return nil }
        return value
    }

    public static let openDetailNotification = Notification.Name("debugHeroWalkOpenDetail")

    public static func makeFixtureFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vanmo-hero-walk", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let minimumBytes = 8_000_000
        let existing = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if existing < minimumBytes {
            try Data(repeating: 0x00, count: minimumBytes).write(to: url)
        }
        return url
    }

    @MainActor
    public static func seedItem(kind: Kind, in context: ModelContext) throws -> MediaItem {
        let title = kind == .movie ? movieTitle : showTitle
        let descriptor = FetchDescriptor<MediaItem>()
        if let existing = try context.fetch(descriptor).first(where: { $0.title == title }) {
            return existing
        }

        let item: MediaItem
        switch kind {
        case .movie:
            let fileURL = try makeFixtureFile(named: "hero-walk-movie.mp4")
            item = MediaItem(
                title: title,
                fileURL: fileURL,
                mediaType: .movie,
                fileSize: 256_000
            )
            item.originalFileName = fileURL.lastPathComponent
        case .series:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("vanmo-hero-walk", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            item = MediaItem(
                title: title,
                fileURL: directory,
                mediaType: .tvShow
            )
            item.showTitle = title
        }
        context.insert(item)
        try context.save()
        return item
    }

    public static func seriesEpisodes() throws -> [EpisodeInfo] {
        let first = try makeFixtureFile(named: "hero-walk-s01e01.mp4")
        let second = try makeFixtureFile(named: "hero-walk-s01e02.mp4")
        return [
            EpisodeInfo(
                id: "hero-walk-e1",
                title: "Episode 1",
                seasonNumber: 1,
                episodeNumber: 1,
                duration: 60,
                overview: nil,
                streamURL: first,
                backdropURL: nil,
                fileSize: 256_000,
                originalFileName: first.lastPathComponent,
                container: "mp4",
                remotePath: first.path
            ),
            EpisodeInfo(
                id: "hero-walk-e2",
                title: "Episode 2",
                seasonNumber: 1,
                episodeNumber: 2,
                duration: 60,
                overview: nil,
                streamURL: second,
                backdropURL: nil,
                fileSize: 256_000,
                originalFileName: second.lastPathComponent,
                container: "mp4",
                remotePath: second.path
            )
        ]
    }
}
#endif
