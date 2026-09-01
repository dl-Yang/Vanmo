import Foundation

public protocol RemoteFileService: AnyObject {
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

extension RemoteFileService {
    public func search(query: String, path: String = "/") async throws -> [RemoteFile] {
        try await search(query: query, path: path, maxDepth: 0, limit: 50)
    }

    public func search(
        query: String,
        path: String = "/",
        maxDepth: Int,
        limit: Int
    ) async throws -> [RemoteFile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        var results: [RemoteFile] = []
        var queue: [(path: String, depth: Int)] = [(path, 0)]
        var visited: Set<String> = []

        while !queue.isEmpty, results.count < limit {
            try Task.checkCancellation()
            let current = queue.removeFirst()
            guard visited.insert(current.path).inserted else { continue }

            let files = try await listDirectory(path: current.path)
            for file in files {
                if file.name.lowercased().contains(normalizedQuery) {
                    results.append(file)
                    if results.count >= limit { break }
                }

                if file.isDirectory, current.depth < maxDepth {
                    queue.append((file.path, current.depth + 1))
                }
            }
        }

        return results
    }
}

public protocol MediaServerService: RemoteFileService {
    func streamMediaItems(
        since: Date?,
        pageSize: Int
    ) -> AsyncThrowingStream<[ServerMediaItem], Error>
}

public protocol MediaSearchProviding: AnyObject {
    func searchMedia(query: String, limit: Int) async throws -> [ServerMediaItem]
}

public struct ServerMediaItem: Sendable {
    public let serverId: String
    public let title: String
    public let originalTitle: String?
    public let year: Int?
    public let overview: String?
    public let rating: Double?
    public let contentRating: String?
    public let mediaType: MediaType
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?
    public let genres: [String]
    public let director: String?
    public let cast: [String]
    public let castMembers: [CastMemberInfo]
    public let originCountry: [String]
    public let tmdbID: Int?
    public let streamURL: URL
    public let fileSize: Int64
    public let duration: TimeInterval
    public let originalFileName: String?
    public let container: String?
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let dynamicRange: String?

    public let showTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let seriesId: String?

  /// Live API 条目可选元数据（继续观看 / 最近添加 / 收藏）。
    public let dateCreated: Date?
    public let lastPlayedAt: Date?
    public let lastPlaybackPosition: TimeInterval
    public let isFavoriteOnServer: Bool

    public init(
        serverId: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        rating: Double? = nil,
        contentRating: String? = nil,
        mediaType: MediaType,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        genres: [String] = [],
        director: String? = nil,
        cast: [String] = [],
        castMembers: [CastMemberInfo] = [],
        originCountry: [String] = [],
        tmdbID: Int? = nil,
        streamURL: URL,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0,
        originalFileName: String? = nil,
        container: String? = nil,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        dynamicRange: String? = nil,
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
        self.contentRating = contentRating
        self.mediaType = mediaType
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.genres = genres
        self.director = director
        self.cast = cast
        self.castMembers = castMembers
        self.originCountry = originCountry
        self.tmdbID = tmdbID
        self.streamURL = streamURL
        self.fileSize = fileSize
        self.duration = duration
        self.originalFileName = originalFileName
        self.container = container
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.dynamicRange = dynamicRange
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

public struct ConnectionConfig {
    let connectionId: UUID?
    let type: ConnectionType
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let path: String?
    /// localFolder 协议下用于解析 security-scoped bookmark；其他协议为 nil。
    let bookmarkData: Data?

    public init(from saved: SavedConnection, password: String? = nil) {
        self.connectionId = saved.id
        self.type = saved.type
        self.host = saved.host
        self.port = saved.port
        self.username = saved.username
        self.password = password
        self.path = saved.path
        self.bookmarkData = saved.bookmarkData
    }

    public init(
        connectionId: UUID? = nil,
        type: ConnectionType,
        host: String,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        path: String? = nil,
        bookmarkData: Data? = nil
    ) {
        self.connectionId = connectionId
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.password = password
        self.path = path
        self.bookmarkData = bookmarkData
    }
}
