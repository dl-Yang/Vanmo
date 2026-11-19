import Foundation

public enum MetadataSource: String, Codable, Sendable {
    case emby
    case jellyfin
    case plex
}

public struct CachedEpisodeInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let duration: TimeInterval
    public let overview: String?
    public let streamURL: URL
    public let backdropLocalPath: String?
    public let backdropRemoteURL: URL?
    public let fileSize: Int64?
    public let originalFileName: String?
    public let container: String?
    public let remotePath: String?
    public let lastPlaybackPosition: TimeInterval
    public let isWatched: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, seasonNumber, episodeNumber, duration, overview, streamURL
        case backdropLocalPath, backdropRemoteURL, fileSize, originalFileName, container, remotePath
        case lastPlaybackPosition, isWatched
    }

    public init(
        id: String,
        title: String,
        seasonNumber: Int,
        episodeNumber: Int,
        duration: TimeInterval,
        overview: String?,
        streamURL: URL,
        backdropLocalPath: String?,
        backdropRemoteURL: URL?,
        fileSize: Int64? = nil,
        originalFileName: String? = nil,
        container: String? = nil,
        remotePath: String? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        isWatched: Bool = false
    ) {
        self.id = id
        self.title = title
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = duration
        self.overview = overview
        self.streamURL = streamURL
        self.backdropLocalPath = backdropLocalPath
        self.backdropRemoteURL = backdropRemoteURL
        self.fileSize = fileSize
        self.originalFileName = originalFileName
        self.container = container
        self.remotePath = remotePath
        self.lastPlaybackPosition = lastPlaybackPosition
        self.isWatched = isWatched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        seasonNumber = try container.decode(Int.self, forKey: .seasonNumber)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        streamURL = try container.decode(URL.self, forKey: .streamURL)
        backdropLocalPath = try container.decodeIfPresent(String.self, forKey: .backdropLocalPath)
        backdropRemoteURL = try container.decodeIfPresent(URL.self, forKey: .backdropRemoteURL)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        originalFileName = try container.decodeIfPresent(String.self, forKey: .originalFileName)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath)
        lastPlaybackPosition = try container.decodeIfPresent(TimeInterval.self, forKey: .lastPlaybackPosition) ?? 0
        isWatched = try container.decodeIfPresent(Bool.self, forKey: .isWatched) ?? false
    }

    public func makeEpisodeInfo(rootDirectory: URL) -> EpisodeInfo {
        let backdropURL: URL?
        if let path = backdropLocalPath {
            backdropURL = rootDirectory.appendingPathComponent(path)
        } else {
            backdropURL = backdropRemoteURL
        }

        return EpisodeInfo(
            id: id,
            title: title,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            duration: duration,
            overview: overview,
            streamURL: streamURL,
            backdropURL: backdropURL,
            fileSize: fileSize ?? 0,
            originalFileName: originalFileName,
            container: container,
            remotePath: remotePath,
            lastPlaybackPosition: lastPlaybackPosition,
            isWatched: isWatched
        )
    }
}

public struct MetadataCacheRecord: Codable, Sendable {
    public let key: MetadataCacheKey
    public var title: String
    public var originalTitle: String?
    public var year: Int?
    public var overview: String?
    public var rating: Double?
    public var contentRating: String?
    public var genres: [String]
    public var director: String?
    public var cast: [String]
    public var castMembers: [CachedCastMember]
    public var originCountry: [String]
    public var tmdbID: Int?
    public var logoLocalPath: String?
    public var backdropLocalPath: String?
    public var logoRemoteURL: URL?
    public var backdropRemoteURL: URL?
    public var backdropRemoteURLs: [URL]
    public var posterRemoteURL: URL?
    public var videoWidth: Int?
    public var videoHeight: Int?
    public var videoCodec: String?
    public var videoBitDepth: Int?
    public var bitRate: Int?
    public var dynamicRange: String?
    public var audioTracks: [AudioTrackInfo]
    public var episodes: [CachedEpisodeInfo]
    public var fetchedAt: Date
    public var source: MetadataSource

    public func resolvedLogoURL(rootDirectory: URL) -> URL? {
        if let path = logoLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return logoRemoteURL
    }

    public func resolvedBackdropURL(rootDirectory: URL) -> URL? {
        if let path = backdropLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return backdropRemoteURL ?? backdropRemoteURLs.first
    }

    public func resolvedBackdropURLs(rootDirectory: URL) -> [URL] {
        var urls: [URL] = []
        if let first = resolvedBackdropURL(rootDirectory: rootDirectory) {
            urls.append(first)
        }
        for remote in backdropRemoteURLs {
            if urls.isEmpty || (remote != backdropRemoteURL && !urls.contains(remote)) {
                urls.append(remote)
            }
        }
        return urls
    }

    public func makeCastDisplays(rootDirectory: URL) -> [CastMemberDisplay] {
        if !castMembers.isEmpty {
            return castMembers.enumerated().map { index, member in
                CastMemberDisplay(
                    id: "\(index)-\(member.id)",
                    name: member.name,
                    role: member.role,
                    profileURL: member.resolvedProfileURL(rootDirectory: rootDirectory)
                )
            }
        }
        return cast.enumerated().map { index, name in
            CastMemberDisplay(id: "\(index)-\(name)", name: name, role: nil, profileURL: nil)
        }
    }

    enum CodingKeys: String, CodingKey {
        case key, title, originalTitle, year, overview, rating, contentRating, genres, director, cast, castMembers
        case originCountry, tmdbID, logoLocalPath, backdropLocalPath, logoRemoteURL, backdropRemoteURL, backdropRemoteURLs
        case posterRemoteURL, videoWidth, videoHeight, videoCodec, videoBitDepth, bitRate, dynamicRange, audioTracks
        case episodes, fetchedAt, source
    }

    public init(
        key: MetadataCacheKey,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        rating: Double? = nil,
        contentRating: String? = nil,
        genres: [String] = [],
        director: String? = nil,
        cast: [String] = [],
        castMembers: [CachedCastMember] = [],
        originCountry: [String] = [],
        tmdbID: Int? = nil,
        logoLocalPath: String? = nil,
        backdropLocalPath: String? = nil,
        logoRemoteURL: URL? = nil,
        backdropRemoteURL: URL? = nil,
        backdropRemoteURLs: [URL] = [],
        posterRemoteURL: URL? = nil,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        videoCodec: String? = nil,
        videoBitDepth: Int? = nil,
        bitRate: Int? = nil,
        dynamicRange: String? = nil,
        audioTracks: [AudioTrackInfo] = [],
        episodes: [CachedEpisodeInfo] = [],
        fetchedAt: Date = Date(),
        source: MetadataSource
    ) {
        let resolvedBackdrops: [URL]
        if !backdropRemoteURLs.isEmpty {
            resolvedBackdrops = backdropRemoteURLs
        } else if let backdropRemoteURL {
            resolvedBackdrops = [backdropRemoteURL]
        } else {
            resolvedBackdrops = []
        }

        self.key = key
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.rating = rating
        self.contentRating = contentRating
        self.genres = genres
        self.director = director
        self.cast = cast
        self.castMembers = castMembers
        self.originCountry = originCountry
        self.tmdbID = tmdbID
        self.logoLocalPath = logoLocalPath
        self.backdropLocalPath = backdropLocalPath
        self.logoRemoteURL = logoRemoteURL
        self.backdropRemoteURL = backdropRemoteURL ?? resolvedBackdrops.first
        self.backdropRemoteURLs = resolvedBackdrops
        self.posterRemoteURL = posterRemoteURL
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.videoCodec = videoCodec
        self.videoBitDepth = videoBitDepth
        self.bitRate = bitRate
        self.dynamicRange = dynamicRange
        self.audioTracks = audioTracks
        self.episodes = episodes
        self.fetchedAt = fetchedAt
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(MetadataCacheKey.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating)
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        director = try container.decodeIfPresent(String.self, forKey: .director)
        cast = try container.decodeIfPresent([String].self, forKey: .cast) ?? []
        castMembers = try container.decodeIfPresent([CachedCastMember].self, forKey: .castMembers) ?? []
        originCountry = try container.decodeIfPresent([String].self, forKey: .originCountry) ?? []
        tmdbID = try container.decodeIfPresent(Int.self, forKey: .tmdbID)
        logoLocalPath = try container.decodeIfPresent(String.self, forKey: .logoLocalPath)
        backdropLocalPath = try container.decodeIfPresent(String.self, forKey: .backdropLocalPath)
        logoRemoteURL = try container.decodeIfPresent(URL.self, forKey: .logoRemoteURL)
        backdropRemoteURL = try container.decodeIfPresent(URL.self, forKey: .backdropRemoteURL)
        let decodedBackdrops = try container.decodeIfPresent([URL].self, forKey: .backdropRemoteURLs) ?? []
        if !decodedBackdrops.isEmpty {
            backdropRemoteURLs = decodedBackdrops
        } else if let backdropRemoteURL {
            backdropRemoteURLs = [backdropRemoteURL]
        } else {
            backdropRemoteURLs = []
        }
        posterRemoteURL = try container.decodeIfPresent(URL.self, forKey: .posterRemoteURL)
        videoWidth = try container.decodeIfPresent(Int.self, forKey: .videoWidth)
        videoHeight = try container.decodeIfPresent(Int.self, forKey: .videoHeight)
        videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
        videoBitDepth = try container.decodeIfPresent(Int.self, forKey: .videoBitDepth)
        bitRate = try container.decodeIfPresent(Int.self, forKey: .bitRate)
        dynamicRange = try container.decodeIfPresent(String.self, forKey: .dynamicRange)
        audioTracks = try container.decodeIfPresent([AudioTrackInfo].self, forKey: .audioTracks) ?? []
        episodes = try container.decodeIfPresent([CachedEpisodeInfo].self, forKey: .episodes) ?? []
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
        source = try container.decode(MetadataSource.self, forKey: .source)
    }
}

public struct MetadataCacheIndex: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var records: [String: MetadataCacheRecord]

    public init(schemaVersion: Int = Self.currentSchemaVersion, records: [String: MetadataCacheRecord] = [:]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}
