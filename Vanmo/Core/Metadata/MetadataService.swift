import Foundation

actor MetadataService {
    static let shared = MetadataService()

    private let tmdb = TMDbService.shared

    func fetchMetadata(for item: MediaItem) async throws -> MetadataResult {
        let parsed = FileNameParser.parse(item.fileURL.lastPathComponent)
        VanmoLogger.metadata.info("Parsed filename: \(parsed.title), year: \(parsed.year ?? 0), isTV: \(parsed.isTV)")

        if parsed.isTV {
            return try await fetchTVMetadata(parsed: parsed)
        } else {
            return try await fetchMovieMetadata(parsed: parsed)
        }
    }

    func applyMetadata(_ result: MetadataResult, to item: MediaItem) {
        item.title = result.title
        item.originalTitle = result.originalTitle
        item.year = result.year
        item.overview = result.overview
        item.posterURL = result.posterURL
        item.backdropURL = result.backdropURL
        item.rating = result.rating
        item.genres = result.genres
        item.director = result.director
        item.cast = result.cast
        item.tmdbID = result.tmdbID

        if let season = result.seasonNumber {
            item.seasonNumber = season
            item.episodeNumber = result.episodeNumber
            item.showTitle = result.showTitle
            item.mediaType = .tvEpisode
        } else {
            item.mediaType = .movie
        }
    }

    // MARK: - Private

    private func fetchMovieMetadata(parsed: ParsedFileName) async throws -> MetadataResult {
        let movies = try await tmdb.searchMovie(query: parsed.searchQuery, year: parsed.year)
        guard let first = movies.first else { throw TMDbError.noResults }

        let detail = try await tmdb.movieDetail(id: first.id)

        return MetadataResult(
            tmdbID: detail.id,
            title: detail.title,
            originalTitle: detail.originalTitle,
            year: detail.year,
            overview: detail.overview,
            posterURL: tmdb.posterURL(detail.posterPath),
            backdropURL: tmdb.backdropURL(detail.backdropPath),
            rating: detail.voteAverage,
            genres: detail.genres.map(\.name),
            director: detail.director,
            cast: detail.topCast,
            seasonNumber: nil,
            episodeNumber: nil,
            showTitle: nil
        )
    }

    private func fetchTVMetadata(parsed: ParsedFileName) async throws -> MetadataResult {
        let shows = try await tmdb.searchTV(query: parsed.searchQuery, year: parsed.year)
        guard let first = shows.first else { throw TMDbError.noResults }

        let detail = try await tmdb.tvDetail(id: first.id)

        return MetadataResult(
            tmdbID: detail.id,
            title: detail.name,
            originalTitle: detail.originalName,
            year: detail.year,
            overview: detail.overview,
            posterURL: tmdb.posterURL(detail.posterPath),
            backdropURL: tmdb.backdropURL(detail.backdropPath),
            rating: detail.voteAverage,
            genres: detail.genres.map(\.name),
            director: nil,
            cast: detail.topCast,
            seasonNumber: parsed.season,
            episodeNumber: parsed.episode,
            showTitle: detail.name
        )
    }
}

struct MetadataResult {
    let tmdbID: Int
    let title: String
    let originalTitle: String?
    let year: Int?
    let overview: String?
    let posterURL: URL?
    let backdropURL: URL?
    let rating: Double?
    let genres: [String]
    let director: String?
    let cast: [String]
    let seasonNumber: Int?
    let episodeNumber: Int?
    let showTitle: String?
}
