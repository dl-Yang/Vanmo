import Foundation

protocol RemoteFileService: AnyObject {
    var type: ConnectionType { get }
    var isConnected: Bool { get }

    func connect(config: ConnectionConfig) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [RemoteFile]
    func streamURL(for file: RemoteFile) async throws -> URL
    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws
}

struct ConnectionConfig {
    let type: ConnectionType
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let path: String?

    init(from saved: SavedConnection, password: String? = nil) {
        self.type = saved.type
        self.host = saved.host
        self.port = saved.port
        self.username = saved.username
        self.password = password
        self.path = saved.path
    }

    init(
        type: ConnectionType,
        host: String,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        path: String? = nil
    ) {
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.password = password
        self.path = path
    }
}
