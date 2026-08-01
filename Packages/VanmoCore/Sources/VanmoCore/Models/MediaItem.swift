import Foundation
import SwiftData

@Model
public final class MediaItem {
    public var id: UUID
    public var title: String
    public var originalTitle: String?
    public var year: Int?
    public var overview: String?
    public var posterURL: URL?
    public var backdropURL: URL?
    public var logoURL: URL?
    public var rating: Double?
    public var mediaType: MediaType
    public var fileURL: URL
    public var fileSize: Int64
    public var duration: TimeInterval
    public var originalFileName: String?
    public var container: String?
    public var lastPlayedAt: Date?
    public var lastPlaybackPosition: TimeInterval
    public var isWatched: Bool
    public var isFavorite: Bool
    public var addedAt: Date

    public var tmdbID: Int?
    public var genres: [String]
    public var director: String?
    public var cast: [String]

    public var originCountry: [String]

    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var showTitle: String?
    public var episodeTitle: String?

    public var serverId: String?
    public var seriesId: String?
    public var sourceConnectionId: UUID?

    /// 远端文件最后修改时间，用于增量扫描跳过未变化条目。
    public var remoteModifiedAt: Date?
    /// 离线识别置信度（0~1），文件名/目录/NFO 合并结果。
    public var identificationConfidence: Double?

    /// 远端内容版本或 etag，用于增量变更检测。
    public var remoteContentVersion: String?
    /// 最近一次技术探测完成时间。
    public var probedAt: Date?
    /// 技术探测状态（`ProbeStatus.rawValue`）。
    public var probeStatus: String?
    /// 技术探测缓存指纹，文件变化后失效。
    public var probeFingerprint: String?
    public var videoWidth: Int?
    public var videoHeight: Int?
    public var videoCodec: String?

    /// 是否允许通过 CloudKit 同步播放进度（Emby/Plex/Jellyfin 以服务端为准）。
    public var isProgressCloudSynced: Bool
    /// 是否允许通过 CloudKit 同步收藏状态（媒体服务器条目以服务端为准）。
    public var isFavoriteCloudSynced: Bool

    public var audioTracks: [AudioTrackInfo]
    public var subtitleTracks: [SubtitleTrackInfo]

    /// 用户在播放器中为本条目选择的字幕轨偏好，跨会话恢复。
    /// 取值：`nil` 未设置；`"off"` 显式关闭；`"embedded:<index>"` 内嵌轨；`"external:<fileName>"` 外挂轨。
    public var subtitlePreference: String?

    /// 视频动态范围（`DynamicRange.rawValue`），首播时读取真实元数据后写入。`nil` 表示尚未探测。
    public var dynamicRange: String?

    /// 是否为直播流（IPTV 频道）。运行时标志，不持久化：直播无固定时长/进度，
    /// 播放器据此隐藏进度条与续播、显示 LIVE 标识、断流后自动重连。
    @Transient public var isLiveStream: Bool = false

    public init(
        title: String,
        fileURL: URL,
        mediaType: MediaType = .movie,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.title = title
        self.fileURL = fileURL
        self.mediaType = mediaType
        self.fileSize = fileSize
        self.duration = duration
        self.lastPlaybackPosition = 0
        self.isWatched = false
        self.isFavorite = false
        self.isProgressCloudSynced = true
        self.isFavoriteCloudSynced = true
        self.addedAt = Date()
        self.genres = []
        self.cast = []
        self.originCountry = []
        self.audioTracks = []
        self.subtitleTracks = []
    }

    public var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return lastPlaybackPosition / duration
    }

    public var isRecentlyPlayed: Bool {
        guard let lastPlayed = lastPlayedAt else { return false }
        return Date().timeIntervalSince(lastPlayed) < 7 * 24 * 3600
    }

    public var displayTitle: String {
        if mediaType == .tvEpisode,
           let showTitle,
           let season = seasonNumber,
           let episode = episodeNumber {
            return "\(showTitle) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
        }
        return title
    }

    /// 已探测的真实动态范围；未探测时回退到文件名启发式。
    public var resolvedDynamicRange: DynamicRange {
        if let dynamicRange, let range = DynamicRange(rawValue: dynamicRange) {
            return range
        }
        return PlayerCapabilityProbe.isHDRCandidate(url: fileURL) ? .hdr : .sdr
    }
}

public enum MediaType: String, Codable, CaseIterable, Sendable {
    case movie
    case tvShow
    case tvEpisode
    case season
    case folder
    case collectionFolder
    case boxSet
    case audio
    case musicAlbum
    case photo
    case other

    public var displayName: String {
        switch self {
        case .movie: return "电影"
        case .tvShow: return "电视剧"
        case .tvEpisode: return "单集"
        case .season: return "季"
        case .folder: return "文件夹"
        case .collectionFolder: return "媒体库"
        case .boxSet: return "合集"
        case .audio: return "音频"
        case .musicAlbum: return "专辑"
        case .photo: return "照片"
        case .other: return "其他"
        }
    }

    public var icon: String {
        switch self {
        case .movie: return "film"
        case .tvShow: return "tv"
        case .tvEpisode: return "play.rectangle"
        case .season: return "square.stack"
        case .folder: return "folder"
        case .collectionFolder: return "rectangle.stack"
        case .boxSet: return "rectangle.stack.fill"
        case .audio: return "music.note"
        case .musicAlbum: return "opticaldisc"
        case .photo: return "photo"
        case .other: return "doc.richtext"
        }
    }

    /// 可进入子级列表（Folder / 媒体库 / 季）。电视剧仍走详情页分集列表。
    public var isBrowsable: Bool {
        switch self {
        case .folder, .collectionFolder, .season, .boxSet:
            return true
        default:
            return false
        }
    }

    /// 是否适合出现在「最近添加 / 继续观看」等精选区。
    public var showsInHighlights: Bool {
        switch self {
        case .tvEpisode, .season, .folder:
            return false
        default:
            return true
        }
    }

    /// 从 Emby/Jellyfin `Type` 字段映射到本地类型（白名单）。
    public static func from(embyType: String) -> MediaType {
        switch embyType {
        case "Movie", "Video": return .movie
        case "Series": return .tvShow
        case "Episode": return .tvEpisode
        case "Season": return .season
        case "CollectionFolder": return .collectionFolder
        case "BoxSet": return .boxSet
        default: return .other
        }
    }
}


public struct AudioTrackInfo: Codable, Identifiable, Hashable {
    public var id: Int
    public init(id: Int, language: String? = nil, title: String? = nil, codec: String? = nil, channels: Int? = nil) {
        self.id = id; self.language = language; self.title = title; self.codec = codec; self.channels = channels
    }
    public var language: String?
    public var title: String?
    public var codec: String?
    public var channels: Int?

    public var channelLayoutName: String? {
        guard let channels else { return nil }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }

    public var displayName: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let language { parts.append(language) }
        if let codec { parts.append(codec) }
        if let layout = channelLayoutName { parts.append(layout) }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}

public struct SubtitleTrackInfo: Codable, Identifiable, Hashable {
    public var id: Int
    public init(id: Int, language: String? = nil, title: String? = nil, isEmbedded: Bool = true, fileURL: URL? = nil) {
        self.id = id; self.language = language; self.title = title; self.isEmbedded = isEmbedded; self.fileURL = fileURL
    }
    public var language: String?
    public var title: String?
    public var isEmbedded: Bool
    public var fileURL: URL?

    public var displayName: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let language { parts.append(language) }
        parts.append(isEmbedded ? "内嵌" : "外挂")
        return parts.isEmpty ? "Subtitle \(id)" : parts.joined(separator: " · ")
    }
}
