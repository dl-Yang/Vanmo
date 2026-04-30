import Foundation
import SwiftData

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case smb
    case ftp
    case sftp
    case webdav
    case nfs
    case dlna
    case plex
    case emby
    case jellyfin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .webdav: return "WebDAV"
        case .nfs: return "NFS"
        case .dlna: return "DLNA"
        case .plex: return "Plex"
        case .emby: return "Emby"
        case .jellyfin: return "Jellyfin"
        }
    }

    var icon: String {
        switch self {
        case .smb, .nfs: return "externaldrive.connected.to.line.below"
        case .ftp, .sftp: return "arrow.up.arrow.down.circle"
        case .webdav: return "globe"
        case .dlna: return "tv.and.mediabox"
        case .plex, .emby, .jellyfin: return "server.rack"
        }
    }

    var defaultPort: Int {
        switch self {
        case .smb: return 445
        case .ftp: return 21
        case .sftp: return 22
        case .webdav: return 80
        case .nfs: return 2049
        case .dlna: return 0
        case .plex: return 32400
        case .emby: return 8096
        case .jellyfin: return 8096
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .dlna: return false
        default: return true
        }
    }

    var isMediaServer: Bool {
        switch self {
        case .emby, .jellyfin, .plex: return true
        default: return false
        }
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
        path: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.path = path
        self.isFavorite = false
        self.addedAt = Date()
    }
}

struct RemoteFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modifiedDate: Date?
    let type: RemoteFileType

    var isVideo: Bool { type == .video }
}

enum RemoteFileType {
    case video
    case subtitle
    case audio
    case image
    case directory
    case other

    static func from(filename: String) -> RemoteFileType {
        let url = URL(fileURLWithPath: filename)
        if url.isVideoFile { return .video }
        if url.isSubtitleFile { return .subtitle }
        let ext = url.pathExtension.lowercased()
        if ["mp3", "flac", "aac", "wav", "ogg", "m4a"].contains(ext) { return .audio }
        if ["jpg", "jpeg", "png", "gif", "bmp", "webp"].contains(ext) { return .image }
        return .other
    }
}
