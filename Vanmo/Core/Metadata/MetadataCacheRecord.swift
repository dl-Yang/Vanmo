import Foundation

enum MetadataSource: String, Codable, Sendable {
    case emby
    case jellyfin
    case plex
}

struct CachedEpisodeInfo: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let seasonNumber: Int
    let episodeNumber: Int
    let duration: TimeInterval
    let overview: String?
    let streamURL: URL
    let backdropLocalPath: String?
    let backdropRemoteURL: URL?

    func makeEpisodeInfo(rootDirectory: URL) -> EpisodeInfo {
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
            backdropURL: backdropURL
        )
    }
}

struct MetadataCacheRecord: Codable, Sendable {
    let key: MetadataCacheKey
    var title: String
    var originalTitle: String?
    var year: Int?
    var overview: String?
    var rating: Double?
    var genres: [String]
    var director: String?
    var cast: [String]
    var castMembers: [CachedCastMember]
    var originCountry: [String]
    var tmdbID: Int?
    var logoLocalPath: String?
    var backdropLocalPath: String?
    var logoRemoteURL: URL?
    var backdropRemoteURL: URL?
    var posterRemoteURL: URL?
    var episodes: [CachedEpisodeInfo]
    var fetchedAt: Date
    var source: MetadataSource

    func resolvedLogoURL(rootDirectory: URL) -> URL? {
        if let path = logoLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return logoRemoteURL
    }

    func resolvedBackdropURL(rootDirectory: URL) -> URL? {
        if let path = backdropLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return backdropRemoteURL
    }

    func makeCastDisplays(rootDirectory: URL) -> [CastMemberDisplay] {
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

    init(
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

    init(from decoder: Decoder) throws {
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

struct MetadataCacheIndex: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var records: [String: MetadataCacheRecord]

    init(schemaVersion: Int = Self.currentSchemaVersion, records: [String: MetadataCacheRecord] = [:]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}
