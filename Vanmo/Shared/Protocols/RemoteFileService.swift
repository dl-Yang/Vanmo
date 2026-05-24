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

  /// Live API 条目可选元数据（继续观看 / 最近添加 / 收藏）。
    let dateCreated: Date?
    let lastPlayedAt: Date?
    let lastPlaybackPosition: TimeInterval
    let isFavoriteOnServer: Bool

    init(
        serverId: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        rating: Double? = nil,
        mediaType: MediaType,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        genres: [String] = [],
        director: String? = nil,
        cast: [String] = [],
        originCountry: [String] = [],
        tmdbID: Int? = nil,
        streamURL: URL,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0,
        originalFileName: String? = nil,
        container: String? = nil,
        showTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        seriesId: String? = nil,
        dateCreated: Date? = nil,
        lastPlayedAt: Date? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        isFavoriteOnServer: Bool = false
    ) {
        self.serverId = serverId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.rating = rating
        self.mediaType = mediaType
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.genres = genres
        self.director = director
        self.cast = cast
        self.originCountry = originCountry
        self.tmdbID = tmdbID
        self.streamURL = streamURL
        self.fileSize = fileSize
        self.duration = duration
        self.originalFileName = originalFileName
        self.container = container
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.seriesId = seriesId
        self.dateCreated = dateCreated
        self.lastPlayedAt = lastPlayedAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.isFavoriteOnServer = isFavoriteOnServer
    }
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
