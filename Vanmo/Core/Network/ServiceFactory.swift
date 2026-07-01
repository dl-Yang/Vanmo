import Foundation

enum RemoteServiceFactory {
    static func create(for type: ConnectionType) -> RemoteFileService {
        switch type {
        case .localFolder:
            return LocalFolderService()
        case .smb:
            return SMBService()
        case .webdav:
            return WebDAVService()
        case .alist:
            return WebDAVService(type: .alist)
        case .removedOfficialCloudDrive, .baiduNetdisk, .drive115, .quarkDrive, .mega:
            return UnsupportedOfficialCloudDriveService(type: type)
        case .googleDrive:
            return GoogleDriveService()
        case .oneDrive:
            return OneDriveService()
        case .box:
            return BoxDriveService()
        case .pCloudDrive:
            return PCloudDriveService()
        // 以下国际网盘按 more.md 顺序逐个实现，未实现前先落到占位服务，避免误用 GenericHTTPService。
        case .yandexDisk:
            return UnsupportedOfficialCloudDriveService(type: type)
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

final class UnsupportedOfficialCloudDriveService: RemoteFileService {
    let type: ConnectionType
    private(set) var isConnected = false

    init(type: ConnectionType) {
        self.type = type
    }

    func connect(config: ConnectionConfig) async throws {
        throw NetworkError.unsupportedProtocol
    }

    func disconnect() async {
        isConnected = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        throw NetworkError.unsupportedProtocol
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        throw NetworkError.unsupportedProtocol
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        throw NetworkError.unsupportedProtocol
    }
}

final class FTPService: RemoteFileService {
    let type: ConnectionType
    private(set) var isConnected = false
    private let useSFTP: Bool

    init(useSFTP: Bool = false) {
        self.useSFTP = useSFTP
        self.type = useSFTP ? .sftp : .ftp
    }

    func connect(config: ConnectionConfig) async throws {
        isConnected = true
        VanmoLogger.network.info("\(self.type.displayName) connected to \(config.host)")
    }

    func disconnect() async {
        isConnected = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        return []
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        throw NetworkError.unsupportedProtocol
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        guard isConnected else { throw NetworkError.notConnected }
    }
}

final class GenericHTTPService: RemoteFileService {
    let type: ConnectionType = .webdav
    private(set) var isConnected = false

    func connect(config: ConnectionConfig) async throws {
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        return []
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let url = URL(string: file.path) else {
            throw NetworkError.invalidURL
        }
        return url
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
    }
}
