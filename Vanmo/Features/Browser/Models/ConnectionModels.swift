import Foundation
import SwiftData

enum ConnectionType: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var id: String { rawValue }

    static var availableConnectionTypes: [ConnectionType] {
        allCases.filter { $0 != .removedOfficialCloudDrive }
    }

    var displayName: String {
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

    var icon: String {
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

    var defaultPort: Int {
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

    var requiresAuth: Bool {
        switch self {
        case .localFolder, .dlna, .iptv: return false
        default: return true
        }
    }

    var isMediaServer: Bool {
        switch self {
        case .emby, .jellyfin, .plex: return true
        default: return false
        }
    }

    /// 本地协议无需主机/端口/账户，UI 与连接流程走专门分支。
    var isLocal: Bool {
        self == .localFolder
    }

    /// 国内官方网盘合规占位入口（暂不可用，等待开放平台权限/官方 SDK 确认）；
    /// MEGA 官方无标准 REST+OAuth 接口，需要官方 C++ SDK 深度集成，暂归入此类占位。
    var isOfficialCloudDrive: Bool {
        switch self {
        case .removedOfficialCloudDrive, .baiduNetdisk, .drive115, .quarkDrive, .mega:
            return true
        default:
            return false
        }
    }

    /// 走标准 OAuth 2.0 + REST API 的国际网盘，登录后可完整浏览/播放/下载。
    var isOAuthCloudDrive: Bool {
        switch self {
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk:
            return true
        default:
            return false
        }
    }

    /// 是否需要在每个流媒体 Range 请求上都带 `Authorization: Bearer`（即没有可匿名访问的
    /// 预签名直链）。目前只有 Google Drive 需要；OneDrive/Box/pCloud/Yandex.Disk 的
    /// `streamURL(for:)` 都会直接换取到一段时间内可匿名访问的直链，无需在播放期间持续带 token。
    var requiresBearerStreaming: Bool {
        self == .googleDrive
    }
}

struct MediaServerConnectionSnapshot: Sendable {
    let id: UUID
    let name: String
    let type: ConnectionType
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let path: String?

    var config: ConnectionConfig {
        ConnectionConfig(
            type: type,
            host: host,
            port: port,
            username: username,
            password: password,
            path: path
        )
    }

    init(connection: SavedConnection, password: String?) {
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

enum MediaServerConnectionResolver {
    static func snapshot(
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
final class SavedConnection {
    var id: UUID
    var name: String
    var type: ConnectionType
    var host: String
    var port: Int
    var username: String?
    var path: String?
    /// 仅 localFolder 使用：security-scoped bookmark，跨 App 重启恢复访问权限。
    var bookmarkData: Data?
    var isFavorite: Bool
    var lastConnectedAt: Date?
    var lastSyncedAt: Date?
    var addedAt: Date

    init(
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
    }
}

struct RemoteFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modifiedDate: Date?
    let type: RemoteFileType

    /// IPTV 频道分组（来自 EXTINF 的 group-title），仅 IPTV 来源填充。
    var groupTitle: String? = nil
    /// IPTV 台标地址（来自 EXTINF 的 tvg-logo），仅 IPTV 来源填充。
    var logoURL: URL? = nil
    /// IPTV EPG 关联 ID（来自 EXTINF 的 tvg-id），仅 IPTV 来源填充。
    var tvgId: String? = nil

    var isVideo: Bool { type == .video }
}

enum RemoteFileType: Sendable {
    case video
    case subtitle
    case audio
    case image
    case directory
    case other

    static func from(filename: String) -> RemoteFileType {
        let url = URL(fileURLWithPath: filename)
        if MediaFormatProbe.isVideo(url) { return .video }
        if MediaFormatProbe.isSubtitle(url) { return .subtitle }
        if MediaFormatProbe.isAudio(url) { return .audio }
        if MediaFormatProbe.isImage(url) { return .image }
        return .other
    }
}
