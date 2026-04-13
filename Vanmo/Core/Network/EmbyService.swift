import Foundation
import UIKit

final class EmbyService: MediaServerService {
    let type: ConnectionType = .emby
    private(set) var isConnected = false

    private var config: ConnectionConfig?
    private var accessToken: String?
    private var userId: String?
    private let session: URLSession

    private static let clientName = "Vanmo"
    private static let clientVersion = "1.0.0"
    private static let deviceName = "iPhone"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteFileService

    func connect(config: ConnectionConfig) async throws {
        self.config = config

        guard let username = config.username, !username.isEmpty else {
            throw NetworkError.authenticationFailed
        }

        let base = baseURL(for: config)
        let url = base.appendingPathComponent("emby/Users/AuthenticateByName")

        VanmoLogger.network.info("[Emby] Authenticating to \(base.absoluteString) as \(username)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")

        let body: [String: String] = [
            "Username": username,
            "Pw": config.password ?? "",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            VanmoLogger.network.error("[Emby] Connection failed: \(error.localizedDescription)")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response")
        }

        VanmoLogger.network.info("[Emby] Auth response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw NetworkError.authenticationFailed
            }
            throw NetworkError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        let authResult = try JSONDecoder().decode(EmbyAuthResponse.self, from: data)
        self.accessToken = authResult.accessToken
        self.userId = authResult.user.id
        self.isConnected = true

        VanmoLogger.network.info("[Emby] Authenticated as \(authResult.user.name), userId=\(authResult.user.id)")
    }

    func disconnect() async {
        isConnected = false
        accessToken = nil
        userId = nil
        config = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)

        let url: URL
        if path == "/" {
            var components = URLComponents(url: base.appendingPathComponent("emby/Users/\(userId)/Views"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "api_key", value: token)]
            url = components.url!
        } else {
            var components = URLComponents(url: base.appendingPathComponent("emby/Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "ParentId", value: path),
                URLQueryItem(name: "Fields", value: "Path,Size,DateCreated,MediaSources"),
                URLQueryItem(name: "api_key", value: token),
            ]
            url = components.url!
        }

        VanmoLogger.network.info("[Emby] Listing: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.connectionFailed("Failed to list items")
        }

        let result = try JSONDecoder().decode(EmbyItemsResponse.self, from: data)
        VanmoLogger.network.info("[Emby] Found \(result.items.count) items")

        return result.items.map { item in
            let isFolder = item.isFolder ?? (item.type == "Folder" || item.type == "CollectionFolder" || item.type == "UserView")
            let fileType: RemoteFileType = isFolder ? .directory : RemoteFileType.from(filename: item.name)
            return RemoteFile(
                name: item.name,
                path: item.id,
                size: item.size ?? 0,
                isDirectory: isFolder,
                modifiedDate: nil,
                type: fileType
            )
        }
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let config, let token = accessToken else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("emby/Videos/\(file.path)/stream"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token),
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        return url
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected, let config, let token = accessToken else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("emby/Items/\(file.path)/Download"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: token)]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        addAuth(to: &request)

        let (tempURL, _) = try await session.download(for: request)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - MediaServerService

    func fetchAllMediaItems() async throws -> [ServerMediaItem] {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)

        var components = URLComponents(
            url: base.appendingPathComponent("emby/Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,People,ProductionYear,ProviderIds,OriginalTitle,RunTimeTicks,MediaSources,ProductionLocations"),
            URLQueryItem(name: "SortBy", value: "DateCreated"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Limit", value: "500"),
            URLQueryItem(name: "api_key", value: token),
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        VanmoLogger.network.info("[Emby] Fetching all media items: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.connectionFailed("Failed to fetch media items")
        }

        let result = try JSONDecoder().decode(EmbyMediaResponse.self, from: data)
        VanmoLogger.network.info("[Emby] Fetched \(result.items.count) media items")

        return result.items.compactMap { item in
            mapEmbyMediaItem(item, baseURL: base, token: token)
        }
    }

    private func mapEmbyMediaItem(_ item: EmbyMediaDetail, baseURL: URL, token: String) -> ServerMediaItem? {
        let mediaType: MediaType = item.type == "Movie" ? .movie : .tvShow

        let posterURL: URL? = if item.imageTags?.primary != nil {
            URL(string: "\(baseURL.absoluteString)/emby/Items/\(item.id)/Images/Primary?maxHeight=600&quality=90&api_key=\(token)")
        } else {
            nil
        }

        let backdropURL: URL? = if let backdrops = item.backdropImageTags, !backdrops.isEmpty {
            URL(string: "\(baseURL.absoluteString)/emby/Items/\(item.id)/Images/Backdrop?maxWidth=1920&quality=80&api_key=\(token)")
        } else {
            nil
        }

        let streamURL = URL(string: "\(baseURL.absoluteString)/emby/Videos/\(item.id)/stream?static=true&api_key=\(token)")!

        let director = item.people?.first(where: { $0.type == "Director" })?.name
        let cast = item.people?.filter { $0.type == "Actor" }.prefix(10).map(\.name) ?? []

        let durationSeconds: TimeInterval = if let ticks = item.runTimeTicks {
            Double(ticks) / 10_000_000.0
        } else {
            0
        }

        let tmdbID: Int? = if let tmdbStr = item.providerIds?["Tmdb"] {
            Int(tmdbStr)
        } else {
            nil
        }

        let countries = item.productionLocations ?? []

        return ServerMediaItem(
            serverId: item.id,
            title: item.name,
            originalTitle: item.originalTitle,
            year: item.productionYear,
            overview: item.overview,
            rating: item.communityRating,
            mediaType: mediaType,
            posterURL: posterURL,
            backdropURL: backdropURL,
            genres: item.genres ?? [],
            director: director,
            cast: cast,
            originCountry: countries,
            tmdbID: tmdbID,
            streamURL: streamURL,
            fileSize: 0,
            duration: durationSeconds
        )
    }

    // MARK: - Private

    private func baseURL(for config: ConnectionConfig) -> URL {
        let host = config.host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return URL(string: host)!
        }

        let scheme = config.port == 443 ? "https" : "http"
        let portSuffix = (config.port == 80 || config.port == 443) ? "" : ":\(config.port)"
        return URL(string: "\(scheme)://\(host)\(portSuffix)")!
    }

    private var authorizationHeader: String {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return "MediaBrowser Client=\"\(Self.clientName)\", Device=\"\(Self.deviceName)\", DeviceId=\"\(deviceId)\", Version=\"\(Self.clientVersion)\""
    }

    private func addAuth(to request: inout URLRequest) {
        if let token = accessToken {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
    }
}

// MARK: - Emby API Models

private struct EmbyAuthResponse: Decodable {
    let accessToken: String
    let user: EmbyUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

private struct EmbyUser: Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

private struct EmbyItemsResponse: Decodable {
    let items: [EmbyItem]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

private struct EmbyItem: Decodable {
    let id: String
    let name: String
    let type: String
    let isFolder: Bool?
    let path: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case isFolder = "IsFolder"
        case path = "Path"
        case size = "Size"
    }
}

// MARK: - Emby Media Detail Models

private struct EmbyMediaResponse: Decodable {
    let items: [EmbyMediaDetail]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

private struct EmbyMediaDetail: Decodable {
    let id: String
    let name: String
    let type: String
    let originalTitle: String?
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let genres: [String]?
    let people: [EmbyPerson]?
    let providerIds: [String: String]?
    let imageTags: EmbyImageTags?
    let backdropImageTags: [String]?
    let productionLocations: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case originalTitle = "OriginalTitle"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case people = "People"
        case providerIds = "ProviderIds"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case productionLocations = "ProductionLocations"
    }
}

private struct EmbyPerson: Decodable {
    let name: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case type = "Type"
    }
}

private struct EmbyImageTags: Decodable {
    let primary: String?

    enum CodingKeys: String, CodingKey {
        case primary = "Primary"
    }
}
