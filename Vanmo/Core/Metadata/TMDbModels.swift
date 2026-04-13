import Foundation

// MARK: - Search Response

struct TMDbSearchResponse<T: Decodable>: Decodable {
    let page: Int
    let totalResults: Int
    let totalPages: Int
    let results: [T]
}

// MARK: - Movie

struct TMDbMovie: Decodable, Identifiable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    var year: Int? {
        guard let dateStr = releaseDate, dateStr.count >= 4 else { return nil }
        return Int(dateStr.prefix(4))
    }
}

struct TMDbMovieDetail: Decodable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let genres: [TMDbGenre]
    let credits: TMDbCredits?
    let productionCountries: [TMDbCountry]?

    var year: Int? {
        guard let dateStr = releaseDate, dateStr.count >= 4 else { return nil }
        return Int(dateStr.prefix(4))
    }

    var director: String? {
        credits?.crew.first { $0.job == "Director" }?.name
    }

    var topCast: [String] {
        credits?.cast.prefix(10).map(\.name) ?? []
    }
}

// MARK: - TV Show

struct TMDbTVShow: Decodable, Identifiable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?

    var year: Int? {
        guard let dateStr = firstAirDate, dateStr.count >= 4 else { return nil }
        return Int(dateStr.prefix(4))
    }
}

struct TMDbTVDetail: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let genres: [TMDbGenre]
    let credits: TMDbCredits?
    let seasons: [TMDbSeason]?
    let originCountry: [String]?

    var year: Int? {
        guard let dateStr = firstAirDate, dateStr.count >= 4 else { return nil }
        return Int(dateStr.prefix(4))
    }

    var topCast: [String] {
        credits?.cast.prefix(10).map(\.name) ?? []
    }
}

struct TMDbSeason: Decodable, Identifiable {
    let id: Int
    let seasonNumber: Int
    let name: String
    let episodeCount: Int?
    let posterPath: String?
    let overview: String?
}

// MARK: - Shared

struct TMDbGenre: Decodable, Identifiable {
    let id: Int
    let name: String
}

struct TMDbCredits: Decodable {
    let cast: [TMDbCastMember]
    let crew: [TMDbCrewMember]
}

struct TMDbCastMember: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct TMDbCrewMember: Decodable, Identifiable {
    let id: Int
    let name: String
    let job: String
    let department: String?
    let profilePath: String?
}

struct TMDbCountry: Decodable {
    let iso3166_1: String
    let name: String

    private enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case name
    }
}
