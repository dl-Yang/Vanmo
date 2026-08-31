import Foundation

public enum ListingCapability: Sendable {
    case singleShot
    case paginated
}

public enum PlaybackPersistenceStrategy: Sendable {
    case stableDirectURL
    case catalogPlaceholder
    case serverManaged
}

public enum SyncCapability: Sendable {
    case fullRescanOnly
    case serverDelta
}

public struct RemoteServiceCapabilities: Sendable {
    public let listing: ListingCapability
    public let playbackPersistence: PlaybackPersistenceStrategy
    public let sync: SyncCapability
    public let supportsRangeReads: Bool
    public let supportsServerSearch: Bool
    public let maxConcurrentDirectoryReads: Int
    public let requestsPerSecond: Double

    public init(
        listing: ListingCapability,
        playbackPersistence: PlaybackPersistenceStrategy,
        sync: SyncCapability = .fullRescanOnly,
        supportsRangeReads: Bool = false,
        supportsServerSearch: Bool = false,
        maxConcurrentDirectoryReads: Int = 2,
        requestsPerSecond: Double = 4
    ) {
        self.listing = listing
        self.playbackPersistence = playbackPersistence
        self.sync = sync
        self.supportsRangeReads = supportsRangeReads
        self.supportsServerSearch = supportsServerSearch
        self.maxConcurrentDirectoryReads = maxConcurrentDirectoryReads
        self.requestsPerSecond = requestsPerSecond
    }
}

public extension ConnectionType {
    var serviceCapabilities: RemoteServiceCapabilities {
        switch self {
        case .googleDrive:
            return RemoteServiceCapabilities(
                listing: .paginated,
                playbackPersistence: .catalogPlaceholder,
                sync: .serverDelta,
                supportsRangeReads: true,
                supportsServerSearch: true,
                maxConcurrentDirectoryReads: 3,
                requestsPerSecond: 4
            )
        case .oneDrive, .box, .pCloudDrive, .yandexDisk:
            return RemoteServiceCapabilities(
                listing: .paginated,
                playbackPersistence: .catalogPlaceholder,
                sync: .serverDelta,
                supportsRangeReads: true,
                maxConcurrentDirectoryReads: 3,
                requestsPerSecond: 4
            )
        case .baiduNetdisk:
            return RemoteServiceCapabilities(
                listing: .paginated,
                playbackPersistence: .catalogPlaceholder,
                supportsRangeReads: true,
                maxConcurrentDirectoryReads: 2,
                requestsPerSecond: 2
            )
        case .webdav, .alist, .fnos:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                supportsRangeReads: true,
                maxConcurrentDirectoryReads: 4,
                requestsPerSecond: 6
            )
        case .ftp:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                supportsRangeReads: true,
                maxConcurrentDirectoryReads: 2,
                requestsPerSecond: 4
            )
        case .smb, .nfs:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                supportsRangeReads: false,
                maxConcurrentDirectoryReads: 3,
                requestsPerSecond: 8
            )
        case .localFolder:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                supportsRangeReads: true,
                maxConcurrentDirectoryReads: 6,
                requestsPerSecond: 20
            )
        case .emby, .jellyfin, .plex:
            return RemoteServiceCapabilities(
                listing: .paginated,
                playbackPersistence: .serverManaged,
                sync: .serverDelta,
                supportsServerSearch: true,
                maxConcurrentDirectoryReads: 2,
                requestsPerSecond: 6
            )
        case .iptv, .dlna:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                maxConcurrentDirectoryReads: 1,
                requestsPerSecond: 2
            )
        default:
            return RemoteServiceCapabilities(
                listing: .singleShot,
                playbackPersistence: .stableDirectURL,
                maxConcurrentDirectoryReads: 1,
                requestsPerSecond: 2
            )
        }
    }

    /// 扫描/搜索阶段应持久化 catalog 占位 URL，播放或探测前再解析真实地址。
    public var requiresLazyPlaybackURL: Bool {
        switch self {
        case .baiduNetdisk, .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk:
            return true
        default:
            return usesEphemeralStreamURLs
        }
    }
}

public extension RemoteFileService {
    var capabilities: RemoteServiceCapabilities {
        type.serviceCapabilities
    }
}
