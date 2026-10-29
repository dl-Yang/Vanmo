import Foundation
import SwiftData

/// Files 浏览条目在本地媒体库中的对应状态（刮削海报 / 背景图、观看进度）。
public struct FileLibraryState: Equatable, Sendable {
    public var posterURL: URL?
    public var backdropURL: URL?
    public var playbackPosition: TimeInterval
    public var duration: TimeInterval
    public var isWatched: Bool

    public init(
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        playbackPosition: TimeInterval = 0,
        duration: TimeInterval = 0,
        isWatched: Bool = false
    ) {
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.playbackPosition = playbackPosition
        self.duration = duration
        self.isWatched = isWatched
    }

    public init(item: MediaItem) {
        self.init(
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            playbackPosition: item.lastPlaybackPosition,
            duration: item.duration,
            isWatched: item.isWatched
        )
    }
}

/// 视频卡片上的观看进度。`fraction` 为 0...1。
public struct FileWatchProgress: Equatable, Sendable {
    public let fraction: Double
    public let isWatched: Bool

    public init(fraction: Double, isWatched: Bool) {
        self.fraction = fraction
        self.isWatched = isWatched
    }
}

/// Files 卡片封面与进度的取值规则：海报 → 背景图 → 抽帧 → 默认图标。
public enum FileCoverResolver {
    /// 返回按优先级排列、去重后的远端 / 本地图片地址。为空时调用方再走抽帧，最后回落到默认图标。
    public static func artworkCandidates(for file: RemoteFile, library: FileLibraryState?) -> [URL] {
        let ordered = [library?.posterURL, file.posterURL, library?.backdropURL, file.backdropURL]
        var seen = Set<URL>()
        return ordered.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// 本地媒体库有进度时优先使用（播放器实时写回），否则回落到媒体服务器的 UserData。
    public static func progress(for file: RemoteFile, library: FileLibraryState?) -> FileWatchProgress? {
        if let library, library.isWatched || library.playbackPosition > 0 {
            let duration = library.duration > 0 ? library.duration : (file.runtime ?? 0)
            return make(position: library.playbackPosition, duration: duration, isWatched: library.isWatched)
        }
        return make(position: file.playbackPosition ?? 0, duration: file.runtime ?? 0, isWatched: file.isPlayed)
    }

    private static func make(position: TimeInterval, duration: TimeInterval, isWatched: Bool) -> FileWatchProgress? {
        if isWatched { return FileWatchProgress(fraction: 1, isWatched: true) }
        guard duration > 0, position > 0 else { return nil }
        return FileWatchProgress(fraction: min(max(position / duration, 0), 1), isWatched: false)
    }
}

/// Files 浏览页与本地媒体库之间的条目匹配：键为 `(sourceConnectionId, serverId == RemoteFile.path)`。
/// 扫描器同样把原始 `RemoteFile.path` 存进 `serverId`，之后的扫描会更新同一条目而不是重复插入。
public enum FileBrowserLibrary {
    @MainActor
    public static func states(
        connectionId: UUID,
        paths: Set<String>,
        in context: ModelContext
    ) -> [String: FileLibraryState] {
        guard !paths.isEmpty else { return [:] }
        var states: [String: FileLibraryState] = [:]
        for (path, item) in latestItems(connectionId: connectionId, in: context) where paths.contains(path) {
            states[path] = FileLibraryState(item: item)
        }
        return states
    }

    @MainActor
    public static func existingItem(connectionId: UUID, path: String, in context: ModelContext) -> MediaItem? {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.sourceConnectionId == connectionId && item.serverId == path
            }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.max(by: isOlder)
    }

    /// 复用媒体库条目；不存在时插入 `candidate`，让播放器写回的进度得以持久化。
    /// 文件类连接只落库 `vanmo://playback` 占位地址（解析出的地址可能含凭据或会过期），播放器按占位重新解析；
    /// 媒体服务器沿用扫描器做法保存服务端串流地址，且以服务端进度为准，不参与 CloudKit 进度 / 收藏同步。
    @MainActor
    public static func persistentItem(
        for file: RemoteFile,
        candidate: MediaItem,
        connectionId: UUID,
        connectionType: ConnectionType,
        in context: ModelContext
    ) -> MediaItem {
        let isMediaServer = connectionType.isMediaServer
        if let existing = existingItem(connectionId: connectionId, path: file.path, in: context) {
            if isMediaServer { existing.fileURL = candidate.fileURL }
            if file.size > 0 { existing.fileSize = file.size }
            if existing.originalFileName == nil { existing.originalFileName = file.name }
            if existing.container == nil { existing.container = candidate.container }
            try? context.save()
            return existing
        }
        if isMediaServer {
            candidate.isProgressCloudSynced = false
            candidate.isFavoriteCloudSynced = false
        } else {
            candidate.fileURL = connectionType.catalogPlaybackURL(serverPath: file.path)
        }
        context.insert(candidate)
        try? context.save()
        return candidate
    }

    @MainActor
    private static func latestItems(connectionId: UUID, in context: ModelContext) -> [String: MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.sourceConnectionId == connectionId
            }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        var latest: [String: MediaItem] = [:]
        for item in items {
            guard let path = item.serverId else { continue }
            if let current = latest[path], !isOlder(current, item) { continue }
            latest[path] = item
        }
        return latest
    }

    private static func isOlder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        (lhs.lastPlayedAt ?? .distantPast) < (rhs.lastPlayedAt ?? .distantPast)
    }
}
