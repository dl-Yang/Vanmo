import Foundation

enum RemoteServiceFactory {
    static func create(for type: ConnectionType) -> RemoteFileService {
        switch type {
        case .smb:
            return SMBService()
        case .webdav:
            return WebDAVService()
        case .ftp, .sftp:
            return FTPService(useSFTP: type == .sftp)
        default:
            return GenericHTTPService()
        }
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
