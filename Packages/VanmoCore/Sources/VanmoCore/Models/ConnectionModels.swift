import Foundation
import SwiftData

public enum ConnectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case localFolder
    case smb
    case ftp
    case sftp
    case webdav
    case alist
    case removedOfficialCloudDrive = "aliyunDrive"
    case baiduNetdisk
    case drive115
    case quarkDrive
    case googleDrive
    case oneDrive
    case box
    case pCloudDrive
    case yandexDisk
    case mega
    case iptv
    case fnos
    case nfs
    case dlna
    case plex
    case emby
    case jellyfin

    public var id: String { rawValue }

    public static var availableConnectionTypes: [ConnectionType] {
        allCases.filter { $0 != .removedOfficialCloudDrive }
    }

    public var displayName: String {
        switch self {
        case .localFolder: return "本地文件夹"
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .webdav: return "WebDAV"
        case .alist: return "AList 网盘"
        case .removedOfficialCloudDrive: return "已移除的网盘连接"
        case .baiduNetdisk: return "百度网盘"
        case .drive115: return "115 网盘"
        case .quarkDrive: return "夸克网盘"
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .box: return "Box"
        case .pCloudDrive: return "pCloud"
        case .yandexDisk: return "Yandex.Disk"
        case .mega: return "MEGA"
        case .iptv: return "IPTV"
        case .fnos: return "飞牛 fnOS"
        case .nfs: return "NFS"
        case .dlna: return "DLNA"
        case .plex: return "Plex"
        case .emby: return "Emby"
        case .jellyfin: return "Jellyfin"
        }
    }

    public var icon: String {
        switch self {
        case .localFolder: return "folder"
        case .smb, .nfs: return "externaldrive.connected.to.line.below"
        case .ftp, .sftp: return "arrow.up.arrow.down.circle"
        case .webdav: return "globe"
        case .alist: return "cloud"
        case .removedOfficialCloudDrive:
            return "exclamationmark.triangle"
        case .baiduNetdisk, .drive115, .quarkDrive: return "cloud"
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk, .mega: return "cloud"
        case .iptv: return "tv"
        case .fnos: return "externaldrive.badge.wifi"
        case .dlna: return "tv.and.mediabox"
        case .plex, .emby, .jellyfin: return "server.rack"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .localFolder: return 0
        case .smb: return 445
        case .ftp: return 21
        case .sftp: return 22
        case .webdav: return 80
        case .alist: return 5244
        case .removedOfficialCloudDrive, .baiduNetdisk, .drive115, .quarkDrive: return 443
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk, .mega: return 443
        case .iptv: return 0
        case .fnos: return 5005
        case .nfs: return 2049
        case .dlna: return 0
        case .plex: return 32400
        case .emby: return 8096
        case .jellyfin: return 8096
        }
    }

    public var requiresAuth: Bool {
        switch self {
        case .localFolder, .dlna, .iptv: return false
        default: return true
        }
    }

    public var isMediaServer: Bool {
        switch self {
        case .emby, .jellyfin, .plex: return true
        default: return false
        }
    }

    /// 本地协议无需主机/端口/账户，UI 与连接流程走专门分支。
    public var isLocal: Bool {
        self == .localFolder
    }

    /// 国内官方网盘合规占位入口（暂不可用，等待开放平台权限/官方 SDK 确认）；
    /// MEGA 官方无标准 REST+OAuth 接口，需要官方 C++ SDK 深度集成，暂归入此类占位。
    public var isOfficialCloudDrive: Bool {
        switch self {
        case .removedOfficialCloudDrive, .drive115, .quarkDrive, .mega:
            return true
        default:
            return false
        }
    }

    /// 走标准 OAuth 2.0 授权码 + REST API 的国际网盘，登录后可完整浏览/播放/下载。
    public var isOAuthCloudDrive: Bool {
        switch self {
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk:
            return true
        default:
            return false
        }
    }

    /// 走 OAuth 2.0 简化模式（Implicit Grant）的网盘：授权回调直接返回 access_token，
    /// 不支持 refresh_token，过期后需用户重新登录。
    public var isImplicitOAuthCloudDrive: Bool {
        self == .baiduNetdisk
    }

    /// 是否走 OAuth 登录 UI（授权码或简化模式）。
    public var supportsOAuthLogin: Bool {
        isOAuthCloudDrive || isImplicitOAuthCloudDrive
    }

    /// connect 后仅建立连接与浏览；须用户选定目录后手动触发递归同步入库（Infuse Favorite 模型）。
    /// 媒体服务器（Plex/Emby/Jellyfin）与 IPTV/DLNA 仍保留原有 connect 同步行为。
    public var requiresManualDirectorySync: Bool {
        switch self {
        case .emby, .jellyfin, .plex, .iptv, .dlna:
            return false
        default:
            return true
        }
    }

    /// 是否需要在每个流媒体 Range 请求上都带 `Authorization: Bearer`（即没有可匿名访问的
    /// 预签名直链）。目前只有 Google Drive 需要；OneDrive/Box/pCloud/Yandex.Disk 的
    /// `streamURL(for:)` 都会直接换取到一段时间内可匿名访问的直链，无需在播放期间持续带 token。
    public var requiresBearerStreaming: Bool {
        self == .googleDrive
    }

    /// 播放期间需要 PrefetchProxy 注入自定义请求头（Bearer 或百度要求的 User-Agent）。
    public var requiresStreamingHeaderProvider: Bool {
        switch self {
        case .googleDrive, .baiduNetdisk:
            return true
        default:
            return false
        }
    }

    /// 扫描/入库时不应持久化含 access_token 的直链（如百度 dlink），改用占位 URL，播放前再解析。
    public var usesEphemeralStreamURLs: Bool {
        self == .baiduNetdisk
    }

    /// 媒体库占位播放地址：`vanmo://playback/{type}{serverPath}`，不含任何 OAuth 凭据。
    public func catalogPlaybackURL(serverPath: String) -> URL {
        let normalized = serverPath.hasPrefix("/") ? serverPath : "/\(serverPath)"
        return URL(string: "vanmo://playback/\(rawValue)\(normalized)")!
    }
}

public struct MediaServerConnectionSnapshot: Sendable {
    public let id: UUID
    public let name: String
    public let type: ConnectionType
    public let host: String
    public let port: Int
    public let username: String?
    public let password: String?
    public let path: String?

    public var config: ConnectionConfig {
        ConnectionConfig(
            type: type,
            host: host,
            port: port,
            username: username,
            password: password,
            path: path
        )
    }

    public init(connection: SavedConnection, password: String?) {
        self.id = connection.id
        self.name = connection.name
        self.type = connection.type
        self.host = connection.host
        self.port = connection.port
        self.username = connection.username
        self.password = password
        self.path = connection.path
    }
}

public enum MediaServerConnectionResolver {
    public static func snapshot(
        for item: MediaItem,
        in context: ModelContext?
    ) throws -> MediaServerConnectionSnapshot? {
        guard let context,
              let connectionId = item.sourceConnectionId else {
            return nil
        }

        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try context.fetch(descriptor).first,
              connection.type.isMediaServer else {
            return nil
        }

        let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        return MediaServerConnectionSnapshot(connection: connection, password: password)
    }
}

@Model
public final class SavedConnection {
    public var id: UUID
    public var name: String
    public var type: ConnectionType
    public var host: String
    public var port: Int
    public var username: String?
    public var path: String?
    /// 仅 localFolder 使用：security-scoped bookmark，跨 App 重启恢复访问权限。
    /// 跨设备 CloudKit 同步后通常无法直接复用，新设备需重新授权。
    public var bookmarkData: Data?
    public var isFavorite: Bool
    public var lastConnectedAt: Date?
    public var lastSyncedAt: Date?
    public var addedAt: Date
    /// 连接配置最后修改时间，用于 CloudKit 冲突合并。
    public var updatedAt: Date
    /// 软删除墓碑；CloudKit 同步到其他设备后再物理删除。
    public var deletedAt: Date?
    /// 最后修改设备标识，辅助调试与 LWW。
    public var lastModifiedDeviceId: String?

    public init(
        name: String,
        type: ConnectionType,
        host: String,
        port: Int? = nil,
        username: String? = nil,
        path: String? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.path = path
        self.bookmarkData = bookmarkData
        self.isFavorite = false
        self.addedAt = Date()
        self.updatedAt = Date()
        self.lastModifiedDeviceId = CloudSyncDevice.id
    }
}

public struct RemoteFile: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let modifiedDate: Date?
    public let type: RemoteFileType

    /// IPTV 频道分组（来自 EXTINF 的 group-title），仅 IPTV 来源填充。
    public var groupTitle: String? = nil
    /// IPTV 台标地址（来自 EXTINF 的 tvg-logo），仅 IPTV 来源填充。
    public var logoURL: URL? = nil
    /// IPTV EPG 关联 ID（来自 EXTINF 的 tvg-id），仅 IPTV 来源填充。
    public var tvgId: String? = nil
    /// 协议提供的稳定文件 ID（如云盘 fileId）。
    public var stableId: String? = nil
    /// WebDAV/云盘 etag 或版本号。
    public var contentVersion: String? = nil
    /// 远端 MIME 类型（若协议提供）。
    public var mimeType: String? = nil

    public init(
        name: String,
        path: String,
        size: Int64,
        isDirectory: Bool,
        modifiedDate: Date?,
        type: RemoteFileType,
        groupTitle: String? = nil,
        logoURL: URL? = nil,
        tvgId: String? = nil,
        stableId: String? = nil,
        contentVersion: String? = nil,
        mimeType: String? = nil
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.modifiedDate = modifiedDate
        self.type = type
        self.groupTitle = groupTitle
        self.logoURL = logoURL
        self.tvgId = tvgId
        self.stableId = stableId
        self.contentVersion = contentVersion
        self.mimeType = mimeType
    }

    public var isVideo: Bool { type == .video }
}

public enum RemoteFileType: Sendable {
    case video
    case subtitle
    case audio
    case image
    case directory
    case other

    public static func from(filename: String) -> RemoteFileType {
        let url = URL(fileURLWithPath: filename)
        if MediaFormatProbe.isVideo(url) { return .video }
        if MediaFormatProbe.isSubtitle(url) { return .subtitle }
        if MediaFormatProbe.isAudio(url) { return .audio }
        if MediaFormatProbe.isImage(url) { return .image }
        return .other
    }
}
