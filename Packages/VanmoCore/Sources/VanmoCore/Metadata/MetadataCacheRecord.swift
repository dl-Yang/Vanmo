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
        remotePath: String? = nil
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
            remotePath: remotePath
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
    public var posterRemoteURL: URL?
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
        return backdropRemoteURL
    }

    public func makeCastDisplays(rootDirectory: URL) -> [CastMemberDisplay] {
        if !castMembers.isEmpty {
            return castMembers.map { member in
                CastMemberDisplay(
                    id: member.id,
                    name: member.name,
                    role: member.role,
                    profileURL: member.resolvedProfileURL(rootDirectory: rootDirectory)
                )
            }
        }
        return cast.map { name in
            CastMemberDisplay(id: name, name: name, role: nil, profileURL: nil)
        }
    }

    enum CodingKeys: String, CodingKey {
        case key, title, originalTitle, year, overview, rating, genres, director, cast, castMembers
        case originCountry, tmdbID, logoLocalPath, backdropLocalPath, logoRemoteURL, backdropRemoteURL
        case posterRemoteURL, episodes, fetchedAt, source
    }

    public init(
        key: MetadataCacheKey,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        rating: Double? = nil,
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
        posterRemoteURL: URL? = nil,
        episodes: [CachedEpisodeInfo] = [],
        fetchedAt: Date = Date(),
        source: MetadataSource
    ) {
        self.key = key
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.rating = rating
        self.genres = genres
        self.director = director
        self.cast = cast
        self.castMembers = castMembers
        self.originCountry = originCountry
        self.tmdbID = tmdbID
        self.logoLocalPath = logoLocalPath
        self.backdropLocalPath = backdropLocalPath
        self.logoRemoteURL = logoRemoteURL
        self.backdropRemoteURL = backdropRemoteURL
        self.posterRemoteURL = posterRemoteURL
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
        posterRemoteURL = try container.decodeIfPresent(URL.self, forKey: .posterRemoteURL)
        episodes = try container.decodeIfPresent([CachedEpisodeInfo].self, forKey: .episodes) ?? []
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
        source = try container.decode(MetadataSource.self, forKey: .source)
    }
}

public struct MetadataCacheIndex: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var records: [String: MetadataCacheRecord]

    public init(schemaVersion: Int = Self.currentSchemaVersion, records: [String: MetadataCacheRecord] = [:]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}
