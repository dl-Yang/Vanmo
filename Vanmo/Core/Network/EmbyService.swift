import Foundation
import UIKit

final class EmbyService: MediaServerService {
    let type: ConnectionType
    private(set) var isConnected = false

    private var config: ConnectionConfig?
    private var accessToken: String?
    private var userId: String?
    private let session: URLSession

    /// API 路径前缀。Emby 默认 `"emby/"`，Jellyfin 默认 `""`（无前缀）。
    /// 必须以 `/` 结尾或为空，便于与后续路径段直接拼接。
    private let apiPrefix: String

    private static let clientName = "Vanmo"
    private static let clientVersion = "1.0.0"
    /// 与现有 `UIDevice.current.identifierForVendor` 同步访问保持一致；
    /// 在 Swift 6 严格并发模式下需要主线程隔离,这里和现有代码一起当作已知 trade-off。
    private static var deviceName: String {
        let model = UIDevice.current.model
        return model.isEmpty ? "iPhone" : model
    }

    init(
        type: ConnectionType = .emby,
        apiPrefix: String = "emby/",
        session: URLSession = .shared
    ) {
        self.type = type
        self.apiPrefix = apiPrefix
        self.session = session
    }

    // MARK: - RemoteFileService

    func connect(config: ConnectionConfig) async throws {
        self.config = config

        guard let username = config.username, !username.isEmpty else {
            throw NetworkError.authenticationFailed
        }

        let base = baseURL(for: config)
        let url = base.appendingPathComponent("\(apiPrefix)Users/AuthenticateByName")

        VanmoLogger.network.info("[\(self.type.displayName)] Authenticating to \(base.absoluteString) as \(username)")

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
            VanmoLogger.network.error("[\(self.type.displayName)] Connection failed: \(error.localizedDescription)")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response")
        }

        VanmoLogger.network.info("[\(self.type.displayName)] Auth response status: \(httpResponse.statusCode)")

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

        EmbyCredentialStore.save(
            baseURL: base.absoluteString,
            token: authResult.accessToken,
            apiPrefix: apiPrefix
        )

        VanmoLogger.network.info("[\(self.type.displayName)] Authenticated as \(authResult.user.name), userId=\(authResult.user.id)")
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
            var components = URLComponents(url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Views"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "api_key", value: token)]
            url = components.url!
        } else {
            var components = URLComponents(url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "ParentId", value: path),
                URLQueryItem(name: "Fields", value: "Path,Size,DateCreated,MediaSources"),
                URLQueryItem(name: "api_key", value: token),
            ]
            url = components.url!
        }

        VanmoLogger.network.info("[\(self.type.displayName)] Listing: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateEmbyResponse(response, body: data, context: "list items")

        let result = try JSONDecoder().decode(EmbyItemsResponse.self, from: data)
        VanmoLogger.network.info("[\(self.type.displayName)] Found \(result.items.count) items")

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
            url: base.appendingPathComponent("\(apiPrefix)Videos/\(file.path)/stream"),
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
            url: base.appendingPathComponent("\(apiPrefix)Items/\(file.path)/Download"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: token)]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        addAuth(to: &request)

        let (tempURL, response) = try await session.download(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.authenticationFailed
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.connectionFailed("download HTTP \(httpResponse.statusCode)")
            }
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - MediaServerService

    func streamMediaItems(
        since: Date?,
        pageSize: Int
    ) -> AsyncThrowingStream<[ServerMediaItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await fetchPages(since: since, pageSize: pageSize, yield: { page in
                        continuation.yield(page)
                    })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func fetchPages(
        since: Date?,
        pageSize: Int,
        yield: ([ServerMediaItem]) -> Void
    ) async throws {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)

        var startIndex = 0
        var page = 0
        while true {
            try Task.checkCancellation()

            var components = URLComponents(
                url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items"),
                resolvingAgainstBaseURL: false
            )!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
                URLQueryItem(name: "Fields", value: "Overview,Genres,People,ProductionYear,ProviderIds,OriginalTitle,RunTimeTicks,MediaSources,ProductionLocations,DateLastSaved"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(pageSize)),
                URLQueryItem(name: "api_key", value: token),
            ]
            if let since {
                queryItems.append(URLQueryItem(name: "MinDateLastSaved", value: Self.embyDateFormatter.string(from: since)))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            addAuth(to: &request)

            let (data, response) = try await session.data(for: request)
            try validateEmbyResponse(response, body: data, context: "fetch media items")

            let result = try JSONDecoder().decode(EmbyMediaResponse.self, from: data)
            let mapped = result.items.compactMap { item in
                mapEmbyMediaItem(item, baseURL: base, token: token)
            }

            VanmoLogger.network.info("[\(self.type.displayName)] page=\(page) start=\(startIndex) fetched=\(result.items.count) total=\(result.totalRecordCount)")

            if !mapped.isEmpty {
                yield(mapped)
            }

            startIndex += result.items.count
            page += 1

            if result.items.isEmpty || startIndex >= result.totalRecordCount {
                break
            }
        }
    }

    private static let embyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func mapEmbyMediaItem(_ item: EmbyMediaDetail, baseURL: URL, token: String) -> ServerMediaItem? {
        let mediaType: MediaType
        switch item.type {
        case "Movie": mediaType = .movie
        case "Series": mediaType = .tvShow
        default: return nil
        }

        let posterURL: URL? = if item.imageTags?.primary != nil {
            URL(string: "\(baseURL.absoluteString)/\(apiPrefix)Items/\(item.id)/Images/Primary?maxHeight=600&quality=90&api_key=\(token)")
        } else {
            nil
        }

        let backdropURL: URL? = if let backdrops = item.backdropImageTags, !backdrops.isEmpty {
            URL(string: "\(baseURL.absoluteString)/\(apiPrefix)Items/\(item.id)/Images/Backdrop?maxWidth=1920&quality=80&api_key=\(token)")
        } else {
            nil
        }

        let streamURL: URL
        if mediaType == .tvShow {
            streamURL = URL(string: "vanmo://series/\(item.id)")!
        } else {
            streamURL = URL(string: "\(baseURL.absoluteString)/\(apiPrefix)Videos/\(item.id)/stream?static=true&api_key=\(token)")!
        }

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

        let primarySource = item.mediaSources?.first
        let originalFileName = primarySource?.path.flatMap(Self.extractFileName(from:))
        let container = primarySource?.container.flatMap { $0.isEmpty ? nil : $0 }
        let fileSize = primarySource?.size ?? 0

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
            fileSize: fileSize,
            duration: durationSeconds,
            originalFileName: originalFileName,
            container: container,
            showTitle: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            episodeTitle: nil,
            seriesId: nil
        )
    }

    /// 从 Emby 返回的 Path 中提取文件名，兼容 Unix (`/`) 与 Windows (`\`) 分隔符。
    private static func extractFileName(from path: String) -> String? {
        let separators = CharacterSet(charactersIn: "/\\")
        let parts = path.components(separatedBy: separators)
        return parts.last(where: { !$0.isEmpty })
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

// MARK: - Shared Response Validation

/// 统一处理 Emby 接口非 2xx 响应：
/// - 401 / 403 → `NetworkError.authenticationFailed`
/// - 其它 → 带状态码与 body 前 200 字符的 `connectionFailed`
private func validateEmbyResponse(_ response: URLResponse, body: Data, context: String) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.connectionFailed("\(context): invalid response type")
    }
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        VanmoLogger.network.error("[MediaServer] \(context) auth failed: status=\(httpResponse.statusCode)")
        throw NetworkError.authenticationFailed
    }
    guard (200...299).contains(httpResponse.statusCode) else {
        let preview = String(data: body, encoding: .utf8)?.prefix(200) ?? ""
        VanmoLogger.network.error("[MediaServer] \(context) failed: status=\(httpResponse.statusCode) body=\(preview)")
        throw NetworkError.connectionFailed("\(context) HTTP \(httpResponse.statusCode): \(preview)")
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

    let seriesName: String?
    let seriesId: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let seriesPrimaryImageTag: String?
    let mediaSources: [EmbyMediaSource]?

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
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case mediaSources = "MediaSources"
    }
}

private struct EmbyMediaSource: Decodable {
    let path: String?
    let container: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case path = "Path"
        case container = "Container"
        case size = "Size"
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

// MARK: - Credential Store & On-Demand Episode Fetching

/// 跨调用点共享的 Emby/Jellyfin 会话凭据。
///
/// - `baseURL` 与 `apiPrefix` 不是 secret，走 UserDefaults。
/// - `token` 是 access token，必须存在 Keychain（SKILL 红线）。
///
/// 同一时刻只保存最近一次连接成功的服务器凭据；如果用户同时连接 Emby 和
/// Jellyfin，后连接者会覆盖前者，这是已知 trade-off（与 `EmbyEpisodeFetcher`
/// 这种全局静态调用的设计绑定）。
///
/// 为兼容老安装，第一次读 token 时会把残留在 UserDefaults 里的值迁移到
/// Keychain，并清掉 UserDefaults 副本。
enum EmbyCredentialStore {
    private static let baseURLKey = "emby.baseURL"
    private static let apiPrefixKey = "emby.apiPrefix"
    private static let legacyTokenKey = "emby.accessToken"
    private static let tokenKeychainAccount = "emby.accessToken"

    static func save(baseURL: String, token: String, apiPrefix: String) {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        UserDefaults.standard.set(apiPrefix, forKey: apiPrefixKey)
        do {
            try KeychainManager.shared.save(token, for: tokenKeychainAccount)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        } catch {
            VanmoLogger.network.error("[MediaServer] Failed to persist access token to Keychain: \(error.localizedDescription)")
        }
    }

    static var baseURL: String? {
        UserDefaults.standard.string(forKey: baseURLKey)
    }

    /// 当前活跃服务器的 API 前缀。老安装无该字段，回退到 `"emby/"`。
    static var apiPrefix: String {
        UserDefaults.standard.string(forKey: apiPrefixKey) ?? "emby/"
    }

    static var token: String? {
        if let stored = try? KeychainManager.shared.loadString(for: tokenKeychainAccount) {
            return stored
        }
        // 从老版本 UserDefaults 迁移过来。
        if let legacy = UserDefaults.standard.string(forKey: legacyTokenKey) {
            try? KeychainManager.shared.save(legacy, for: tokenKeychainAccount)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            return legacy
        }
        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: apiPrefixKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        try? KeychainManager.shared.delete(for: tokenKeychainAccount)
    }
}

struct EpisodeInfo: Identifiable {
    let id: String
    let title: String
    let seasonNumber: Int
    let episodeNumber: Int
    let duration: TimeInterval
    let overview: String?
    let streamURL: URL
}

enum EmbyEpisodeFetcher {
    static func fetchEpisodes(seriesId: String) async throws -> [EpisodeInfo] {
        guard let baseURLStr = EmbyCredentialStore.baseURL,
              let token = EmbyCredentialStore.token,
              let baseURL = URL(string: baseURLStr) else {
            throw NetworkError.notConnected
        }
        let apiPrefix = EmbyCredentialStore.apiPrefix

        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(apiPrefix)Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Fields", value: "Overview,RunTimeTicks"),
            URLQueryItem(name: "api_key", value: token),
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        VanmoLogger.network.info("[MediaServer] Fetching episodes for series \(seriesId)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateEmbyResponse(response, body: data, context: "fetch episodes")

        let result = try JSONDecoder().decode(EmbyMediaResponse.self, from: data)
        VanmoLogger.network.info("[MediaServer] Fetched \(result.items.count) episodes for series \(seriesId)")

        return result.items.compactMap { item -> EpisodeInfo? in
            guard let season = item.parentIndexNumber,
                  let episode = item.indexNumber else { return nil }

            let duration: TimeInterval = if let ticks = item.runTimeTicks {
                Double(ticks) / 10_000_000.0
            } else {
                0
            }

            let streamURL = URL(string: "\(baseURLStr)/\(apiPrefix)Videos/\(item.id)/stream?static=true&api_key=\(token)")!

            return EpisodeInfo(
                id: item.id,
                title: item.name,
                seasonNumber: season,
                episodeNumber: episode,
                duration: duration,
                overview: item.overview,
                streamURL: streamURL
            )
        }
    }
}
