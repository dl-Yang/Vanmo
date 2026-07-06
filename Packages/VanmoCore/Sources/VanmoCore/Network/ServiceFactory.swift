import Foundation

public enum RemoteServiceFactory {
    public static func create(for type: ConnectionType) -> RemoteFileService {
        switch type {
        case .localFolder:
            return LocalFolderService()
        case .smb:
            return SMBService()
        case .webdav:
            return WebDAVService()
        case .alist:
            return WebDAVService(type: .alist)
        case .removedOfficialCloudDrive, .drive115, .quarkDrive, .mega:
            return UnsupportedOfficialCloudDriveService(type: type)
        case .baiduNetdisk:
            return BaiduNetdiskService()
        case .googleDrive:
            return GoogleDriveService()
        case .oneDrive:
            return OneDriveService()
        case .box:
            return BoxDriveService()
        case .pCloudDrive:
            return PCloudDriveService()
        case .yandexDisk:
            return YandexDiskService()
        case .iptv:
            return IPTVService()
        case .fnos:
            return WebDAVService(type: .fnos)
        case .ftp, .sftp:
            return FTPService(useSFTP: type == .sftp)
        case .emby:
            return EmbyService()
        case .jellyfin:
            return JellyfinService()
        case .plex:
            return PlexService()
        default:
            return GenericHTTPService()
        }
    }
}

public final class UnsupportedOfficialCloudDriveService: RemoteFileService {
    public let type: ConnectionType
    public private(set) var isConnected = false

    public init(type: ConnectionType) {
        self.type = type
    }

    public func connect(config: ConnectionConfig) async throws {
        throw NetworkError.unsupportedProtocol
    }

    public func disconnect() async {
        isConnected = false
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        throw NetworkError.unsupportedProtocol
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        throw NetworkError.unsupportedProtocol
    }

    public func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        throw NetworkError.unsupportedProtocol
    }
}

public final class FTPService: RemoteFileService {
    public let type: ConnectionType
    public private(set) var isConnected = false
    private let useSFTP: Bool

    public init(useSFTP: Bool = false) {
        self.useSFTP = useSFTP
        self.type = useSFTP ? .sftp : .ftp
    }

    public func connect(config: ConnectionConfig) async throws {
        isConnected = true
        VanmoLogger.network.info("\(self.type.displayName) connected to \(config.host)")
    }

    public func disconnect() async {
        isConnected = false
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        return []
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        throw NetworkError.unsupportedProtocol
    }

    public func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard isConnected else { throw NetworkError.notConnected }
    }
}

public final class GenericHTTPService: RemoteFileService {
    public let type: ConnectionType = .webdav
    public private(set) var isConnected = false

    public func connect(config: ConnectionConfig) async throws {
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        return []
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard let url = URL(string: file.path) else {
            throw NetworkError.invalidURL
        }
        return url
    }

    public func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
    }
}
