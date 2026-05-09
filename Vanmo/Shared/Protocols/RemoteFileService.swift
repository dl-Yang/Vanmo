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

protocol MediaServerService: RemoteFileService {
    func streamMediaItems(
        since: Date?,
        pageSize: Int
    ) -> AsyncThrowingStream<[ServerMediaItem], Error>
}

struct ServerMediaItem {
    let serverId: String
    let title: String
    let originalTitle: String?
    let year: Int?
    let overview: String?
    let rating: Double?
    let mediaType: MediaType
    let posterURL: URL?
    let backdropURL: URL?
    let genres: [String]
    let director: String?
    let cast: [String]
    let originCountry: [String]
    let tmdbID: Int?
    let streamURL: URL
    let fileSize: Int64
    let duration: TimeInterval
    let originalFileName: String?
    let container: String?

    let showTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let seriesId: String?
}

struct ConnectionConfig {
    let type: ConnectionType
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let path: String?
    /// localFolder 协议下用于解析 security-scoped bookmark；其他协议为 nil。
    let bookmarkData: Data?

    init(from saved: SavedConnection, password: String? = nil) {
        self.type = saved.type
        self.host = saved.host
        self.port = saved.port
        self.username = saved.username
        self.password = password
        self.path = saved.path
        self.bookmarkData = saved.bookmarkData
    }

    init(
        type: ConnectionType,
        host: String,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        path: String? = nil,
        bookmarkData: Data? = nil
    ) {
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.password = password
        self.path = path
        self.bookmarkData = bookmarkData
    }
}
