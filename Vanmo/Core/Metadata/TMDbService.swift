import Foundation

final class TMDbService {
    static let shared = TMDbService()

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let imageBaseURL = "https://image.tmdb.org/t/p"
    private let session: URLSession
    private let decoder: JSONDecoder

    let apiKey = "d62dcf21c42fe368d62b967f5790c805"

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr) ?? Date()
        }
    }

    // MARK: - Search

    func searchMovie(query: String, year: Int? = nil) async throws -> [TMDbMovie] {
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: "zh-CN"),
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "year", value: "\(year)"))
        }

        let response: TMDbSearchResponse<TMDbMovie> = try await request(
            path: "/search/movie",
            queryItems: queryItems
        )
        return response.results
    }

    func searchTV(query: String, year: Int? = nil) async throws -> [TMDbTVShow] {
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: "zh-CN"),
        ]
        if let year {
            queryItems.append(URLQueryItem(name: "first_air_date_year", value: "\(year)"))
        }

        let response: TMDbSearchResponse<TMDbTVShow> = try await request(
            path: "/search/tv",
            queryItems: queryItems
        )
        return response.results
    }

    // MARK: - Details

    func movieDetail(id: Int) async throws -> TMDbMovieDetail {
        try await request(
            path: "/movie/\(id)",
            queryItems: [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "language", value: "zh-CN"),
                URLQueryItem(name: "append_to_response", value: "credits"),
            ]
        )
    }

    func tvDetail(id: Int) async throws -> TMDbTVDetail {
        try await request(
            path: "/tv/\(id)",
            queryItems: [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "language", value: "zh-CN"),
                URLQueryItem(name: "append_to_response", value: "credits"),
            ]
        )
    }

    // MARK: - Image URLs

    func posterURL(_ path: String?, size: PosterSize = .w342) -> URL? {
        guard let path else { return nil }
        return URL(string: "\(imageBaseURL)/\(size.rawValue)\(path)")
    }

    func backdropURL(_ path: String?, size: BackdropSize = .w780) -> URL? {
        guard let path else { return nil }
        return URL(string: "\(imageBaseURL)/\(size.rawValue)\(path)")
    }

    // MARK: - Private

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        components.queryItems = queryItems

        guard let url = components.url else { throw TMDbError.invalidURL }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw TMDbError.invalidAPIKey
            }
            throw TMDbError.httpError(httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Image Size Enums

enum PosterSize: String {
    case w92, w154, w185, w342, w500, w780, original
}

enum BackdropSize: String {
    case w300, w780, w1280, original
}

// MARK: - Errors

enum TMDbError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case httpError(Int)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "无效的服务器响应"
        case .invalidAPIKey: return "无效的 TMDb API Key"
        case .httpError(let code): return "HTTP 错误 (\(code))"
        case .noResults: return "未找到匹配结果"
        }
    }
}
