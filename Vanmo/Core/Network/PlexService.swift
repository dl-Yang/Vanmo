import Foundation
import UIKit

/// Plex Media Server 协议实现。
///
/// 与 Emby/Jellyfin 不同，Plex 的认证流程经过 plex.tv：
/// 1. 用户名（邮箱）+ 密码发到 `https://plex.tv/api/v2/users/signin` 换取 X-Plex-Token；
/// 2. 用 token 直接访问 PMS（`http://<host>:32400`）。
///
/// PMS 默认返回 XML，所有请求都加 `Accept: application/json` 头部强制 JSON 响应。
final class PlexService: MediaServerService {
    let type: ConnectionType = .plex
    private(set) var isConnected = false

    private var config: ConnectionConfig?
    private var token: String?
    private var resolvedBaseURL: URL?
    private let session: URLSession

    private static let plexTVBaseURL = URL(string: "https://plex.tv")!
    private static let clientName = "Vanmo"
    private static let clientVersion = "1.0.0"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteFileService

    func connect(config: ConnectionConfig) async throws {
        self.config = config

        guard let username = config.username, !username.isEmpty,
              let password = config.password, !password.isEmpty else {
            throw NetworkError.authenticationFailed
        }

        let pmsURL = pmsBaseURL(for: config)
        self.resolvedBaseURL = pmsURL

        VanmoLogger.network.info("[Plex] Authenticating to plex.tv as \(username)")

        let authToken = try await authenticatePlexTV(login: username, password: password)
        self.token = authToken

        try await verifyPMS(baseURL: pmsURL, token: authToken)

        isConnected = true
        PlexCredentialStore.save(baseURL: pmsURL.absoluteString, token: authToken)

        VanmoLogger.network.info("[Plex] Connected to PMS at \(pmsURL.absoluteString)")
    }

    func disconnect() async {
        isConnected = false
        token = nil
        config = nil
        resolvedBaseURL = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }

        let endpoint = path == "/" ? "/library/sections" : path

        VanmoLogger.network.info("[Plex] Listing: \(endpoint)")

        let data = try await getJSON(baseURL: baseURL, endpoint: endpoint, token: token)
        return try parseListing(data: data)
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }
        return makePlexURL(baseURL: baseURL, path: file.path, token: token)
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected else { throw NetworkError.notConnected }

        let url = try await streamURL(for: file)
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.authenticationFailed
            }
            guard (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.connectionFailed("download HTTP \(http.statusCode)")
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
                    try await fetchAllSections(pageSize: pageSize, yield: { page in
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

    private func fetchAllSections(
        pageSize: Int,
        yield: ([ServerMediaItem]) -> Void
    ) async throws {
        guard isConnected, let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }

        let sectionsData = try await getJSON(baseURL: baseURL, endpoint: "/library/sections", token: token)
        let sections = try parseSections(data: sectionsData)

        for section in sections {
            try Task.checkCancellation()
            try await fetchSection(
                section,
                baseURL: baseURL,
                token: token,
                pageSize: pageSize,
                yield: yield
            )
        }
    }

    private func fetchSection(
        _ section: PlexSection,
        baseURL: URL,
        token: String,
        pageSize: Int,
        yield: ([ServerMediaItem]) -> Void
    ) async throws {
        var startIndex = 0
        var page = 0

        while true {
            try Task.checkCancellation()

            var components = URLComponents(
                url: baseURL.appendingPathComponent("library/sections/\(section.key)/all"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "X-Plex-Container-Start", value: String(startIndex)),
                URLQueryItem(name: "X-Plex-Container-Size", value: String(pageSize)),
                URLQueryItem(name: "X-Plex-Token", value: token),
            ]

            guard let url = components.url else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            applyHeaders(to: &request)

            let (data, response) = try await session.data(for: request)
            try validatePlexResponse(response, body: data, context: "section \(section.title)")

            let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
            let items = result.mediaContainer.metadata ?? []
            let mapped = items.compactMap { mapPlexMediaItem($0, baseURL: baseURL, token: token) }

            VanmoLogger.network.info(
                "[Plex] section=\(section.title) page=\(page) start=\(startIndex) fetched=\(items.count) total=\(result.mediaContainer.totalSize ?? items.count)"
            )

            if !mapped.isEmpty { yield(mapped) }

            startIndex += items.count
            page += 1

            let total = result.mediaContainer.totalSize ?? items.count
            if items.isEmpty || startIndex >= total {
                break
            }
        }
    }

    // MARK: - Mapping

    private func mapPlexMediaItem(
        _ meta: PlexMetadata,
        baseURL: URL,
        token: String
    ) -> ServerMediaItem? {
        let mediaType: MediaType
        switch meta.type {
        case "movie": mediaType = .movie
        case "show": mediaType = .tvShow
        default: return nil
        }

        guard let ratingKey = meta.ratingKey else { return nil }

        let posterURL: URL? = meta.thumb.flatMap { thumb in
            URL(string: "\(baseURL.absoluteString)\(thumb)?X-Plex-Token=\(token)")
        }
        let backdropURL: URL? = meta.art.flatMap { art in
            URL(string: "\(baseURL.absoluteString)\(art)?X-Plex-Token=\(token)")
        }

        let streamURL: URL
        if mediaType == .tvShow {
            streamURL = URL(string: "vanmo://plex-series/\(ratingKey)")!
        } else {
            guard let part = meta.media?.first?.part?.first,
                  let partKey = part.key,
                  let url = URL(string: "\(baseURL.absoluteString)\(partKey)?X-Plex-Token=\(token)") else {
                return nil
            }
            streamURL = url
        }

        let durationSeconds: TimeInterval = if let ms = meta.duration {
            Double(ms) / 1000.0
        } else {
            0
        }

        let primaryPart = meta.media?.first?.part?.first
        let originalFileName = primaryPart?.file.flatMap(Self.extractFileName(from:))
        let container = primaryPart?.container.flatMap { $0.isEmpty ? nil : $0 }
        let fileSize = primaryPart?.size ?? 0

        let directors = meta.director?.compactMap(\.tag).joined(separator: ", ")
        let normalizedDirector = (directors?.isEmpty ?? true) ? nil : directors

        let cast: [String] = meta.role?.compactMap(\.tag).prefix(10).map { $0 } ?? []
        let genres: [String] = meta.genre?.compactMap(\.tag) ?? []
        let countries: [String] = meta.country?.compactMap(\.tag) ?? []

        let tmdbID = meta.guid.flatMap(Self.extractTMDB)

        return ServerMediaItem(
            serverId: ratingKey,
            title: meta.title,
            originalTitle: meta.originalTitle,
            year: meta.year,
            overview: meta.summary,
            rating: meta.rating,
            mediaType: mediaType,
            posterURL: posterURL,
            backdropURL: backdropURL,
            genres: genres,
            director: normalizedDirector,
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

    /// 从文件路径中提取文件名,兼容 Unix (`/`) 与 Windows (`\`) 分隔符。
    private static func extractFileName(from path: String) -> String? {
        let separators = CharacterSet(charactersIn: "/\\")
        let parts = path.components(separatedBy: separators)
        return parts.last(where: { !$0.isEmpty })
    }

    /// Plex 的 `guid` 字段可能形如：
    /// - `com.plexapp.agents.themoviedb://12345?lang=en`（旧版 agent）
    /// - `plex://movie/<plex internal id>`（新版 metadata，TMDB 在 Guid[] 子节点中）
    /// 这里只解析旧版 agent 格式；新版需要请求 `?includeGuids=1` 才能拿到 TMDB ID，
    /// 当前实现暂不解析。
    private static func extractTMDB(from guid: String) -> Int? {
        guard guid.contains("themoviedb"),
              let range = guid.range(of: "themoviedb://") else { return nil }
        let afterPrefix = guid[range.upperBound...]
        let idStr = afterPrefix.split(separator: "?").first.map(String.init) ?? String(afterPrefix)
        return Int(idStr)
    }

    // MARK: - Parsing

    private func parseListing(data: Data) throws -> [RemoteFile] {
        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let container = result.mediaContainer
        var files: [RemoteFile] = []

        for dir in container.directory ?? [] {
            files.append(RemoteFile(
                name: dir.title,
                path: "/library/sections/\(dir.key)/all",
                size: 0,
                isDirectory: true,
                modifiedDate: nil,
                type: .directory
            ))
        }

        for meta in container.metadata ?? [] {
            switch meta.type {
            case "movie":
                let part = meta.media?.first?.part?.first
                let path = part?.key ?? "/library/metadata/\(meta.ratingKey ?? "")"
                files.append(RemoteFile(
                    name: meta.title,
                    path: path,
                    size: part?.size ?? 0,
                    isDirectory: false,
                    modifiedDate: nil,
                    type: .video
                ))
            case "episode":
                let part = meta.media?.first?.part?.first
                let path = part?.key ?? "/library/metadata/\(meta.ratingKey ?? "")"
                let displayName: String = {
                    if let season = meta.parentIndex, let ep = meta.index {
                        return "S\(String(format: "%02d", season))E\(String(format: "%02d", ep)) - \(meta.title)"
                    }
                    return meta.title
                }()
                files.append(RemoteFile(
                    name: displayName,
                    path: path,
                    size: part?.size ?? 0,
                    isDirectory: false,
                    modifiedDate: nil,
                    type: .video
                ))
            case "show", "season":
                guard let ratingKey = meta.ratingKey else { continue }
                files.append(RemoteFile(
                    name: meta.title,
                    path: "/library/metadata/\(ratingKey)/children",
                    size: 0,
                    isDirectory: true,
                    modifiedDate: nil,
                    type: .directory
                ))
            default:
                break
            }
        }

        return files
    }

    private func parseSections(data: Data) throws -> [PlexSection] {
        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        return (result.mediaContainer.directory ?? []).compactMap { dir -> PlexSection? in
            let kind: PlexSectionKind
            switch dir.type {
            case "movie": kind = .movie
            case "show": kind = .show
            default: return nil
            }
            return PlexSection(key: dir.key, title: dir.title, kind: kind)
        }
    }

    // MARK: - HTTP helpers

    private func authenticatePlexTV(login: String, password: String) async throws -> String {
        let url = Self.plexTVBaseURL.appendingPathComponent("api/v2/users/signin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "login", value: login),
            URLQueryItem(name: "password", value: password),
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            VanmoLogger.network.error("[Plex] plex.tv signin failed: \(error.localizedDescription)")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid plex.tv response")
        }

        VanmoLogger.network.info("[Plex] plex.tv signin status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw NetworkError.authenticationFailed
            }
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            VanmoLogger.network.error("[Plex] plex.tv signin failed body=\(preview)")
            throw NetworkError.connectionFailed("plex.tv signin HTTP \(httpResponse.statusCode): \(preview)")
        }

        let result = try JSONDecoder().decode(PlexAuthResponse.self, from: data)
        return result.authToken
    }

    private func verifyPMS(baseURL: URL, token: String) async throws {
        let data = try await getJSON(baseURL: baseURL, endpoint: "/identity", token: token)
        // /identity 返回 MediaContainer，只要不抛错就视为可达
        _ = data
    }

    private func pmsBaseURL(for config: ConnectionConfig) -> URL {
        let host = config.host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return URL(string: host)!
        }

        let scheme = config.port == 443 ? "https" : "http"
        let portSuffix = (config.port == 80 || config.port == 443) ? "" : ":\(config.port)"
        return URL(string: "\(scheme)://\(host)\(portSuffix)")!
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(Self.clientName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue(UIDevice.current.model, forHTTPHeaderField: "X-Plex-Device")
        request.setValue("Vanmo", forHTTPHeaderField: "X-Plex-Device-Name")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "X-Plex-Platform-Version")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
    }

    private func getJSON(baseURL: URL, endpoint: String, token: String) async throws -> Data {
        let url = makePlexURL(baseURL: baseURL, path: endpoint, token: token)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        applyHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        try validatePlexResponse(response, body: data, context: "GET \(endpoint)")
        return data
    }

    private func makePlexURL(baseURL: URL, path: String, token: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url ?? baseURL
    }
}

// MARK: - Validation

private func validatePlexResponse(_ response: URLResponse, body: Data, context: String) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.connectionFailed("\(context): invalid response type")
    }
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        VanmoLogger.network.error("[Plex] \(context) auth failed: status=\(httpResponse.statusCode)")
        throw NetworkError.authenticationFailed
    }
    guard (200...299).contains(httpResponse.statusCode) else {
        let preview = String(data: body, encoding: .utf8)?.prefix(200) ?? ""
        VanmoLogger.network.error("[Plex] \(context) failed: status=\(httpResponse.statusCode) body=\(preview)")
        throw NetworkError.connectionFailed("\(context) HTTP \(httpResponse.statusCode): \(preview)")
    }
}

// MARK: - JSON Models

private struct PlexAuthResponse: Decodable {
    let authToken: String
}

private struct PlexMediaContainerResponse: Decodable {
    let mediaContainer: PlexMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexMediaContainer: Decodable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let directory: [PlexDirectory]?
    let metadata: [PlexMetadata]?

    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset
        case directory = "Directory"
        case metadata = "Metadata"
    }
}

private struct PlexDirectory: Decodable {
    let key: String
    let title: String
    let type: String?
}

private struct PlexMetadata: Decodable {
    let ratingKey: String?
    let key: String?
    let title: String
    let originalTitle: String?
    let summary: String?
    let year: Int?
    let rating: Double?
    /// 单位毫秒。
    let duration: Int?
    let thumb: String?
    let art: String?
    let type: String
    /// 仅 episode 有意义,代表所属 season 编号。
    let parentIndex: Int?
    /// 仅 episode 有意义,代表本集集数。
    let index: Int?
    let parentTitle: String?
    let guid: String?
    let media: [PlexMedia]?
    let director: [PlexTag]?
    let role: [PlexTag]?
    let genre: [PlexTag]?
    let country: [PlexTag]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, title, originalTitle, summary, year, rating, duration
        case thumb, art, type, parentIndex, index, parentTitle, guid
        case media = "Media"
        case director = "Director"
        case role = "Role"
        case genre = "Genre"
        case country = "Country"
    }
}

private struct PlexMedia: Decodable {
    let id: Int?
    let duration: Int?
    let container: String?
    let part: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case id, duration, container
        case part = "Part"
    }
}

private struct PlexPart: Decodable {
    let id: Int?
    let key: String?
    let size: Int64?
    let container: String?
    let file: String?
}

private struct PlexTag: Decodable {
    let tag: String?
}

private struct PlexSection {
    let key: String
    let title: String
    let kind: PlexSectionKind
}

private enum PlexSectionKind {
    case movie
    case show
}

// MARK: - Credential Store

/// 跨调用点共享的 Plex 会话凭据。
///
/// - `baseURL` 与 `clientIdentifier` 不是 secret,走 UserDefaults。
/// - `token` 是 X-Plex-Token,必须存在 Keychain（SKILL 红线）。
///
/// `clientIdentifier` 在首次访问时生成并持久化,Plex 服务器用它识别本设备,
/// 跨 App 重启需保持稳定。
enum PlexCredentialStore {
    private static let baseURLKey = "plex.baseURL"
    private static let clientIdentifierKey = "plex.clientIdentifier"
    private static let tokenKeychainAccount = "plex.token"

    static var clientIdentifier: String {
        if let id = UserDefaults.standard.string(forKey: clientIdentifierKey) {
            return id
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: clientIdentifierKey)
        return new
    }

    static var baseURL: String? {
        UserDefaults.standard.string(forKey: baseURLKey)
    }

    static var token: String? {
        try? KeychainManager.shared.loadString(for: tokenKeychainAccount)
    }

    static func save(baseURL: String, token: String) {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        do {
            try KeychainManager.shared.save(token, for: tokenKeychainAccount)
        } catch {
            VanmoLogger.network.error("[Plex] Failed to persist X-Plex-Token to Keychain: \(error.localizedDescription)")
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        try? KeychainManager.shared.delete(for: tokenKeychainAccount)
    }
}

// MARK: - Episode Fetcher

/// 提供给 PlayerViewModel / MediaDetailView 在剧集播放时调用,按 series ratingKey
/// 拉取 Plex 服务器上的剧集列表。
enum PlexEpisodeFetcher {
    static func fetchEpisodes(seriesRatingKey: String) async throws -> [EpisodeInfo] {
        guard let baseURLStr = PlexCredentialStore.baseURL,
              let token = PlexCredentialStore.token,
              let baseURL = URL(string: baseURLStr) else {
            throw NetworkError.notConnected
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/metadata/\(seriesRatingKey)/grandchildren"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]

        guard let url = components.url else { throw NetworkError.invalidURL }

        VanmoLogger.network.info("[Plex] Fetching episodes for series \(seriesRatingKey)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch episodes")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let episodes = (result.mediaContainer.metadata ?? []).compactMap { meta -> EpisodeInfo? in
            guard meta.type == "episode",
                  let key = meta.ratingKey,
                  let season = meta.parentIndex,
                  let ep = meta.index,
                  let part = meta.media?.first?.part?.first,
                  let partKey = part.key else { return nil }

            let duration: TimeInterval = if let ms = meta.duration {
                Double(ms) / 1000.0
            } else {
                0
            }

            let stream = URL(string: "\(baseURLStr)\(partKey)?X-Plex-Token=\(token)")!

            return EpisodeInfo(
                id: key,
                title: meta.title,
                seasonNumber: season,
                episodeNumber: ep,
                duration: duration,
                overview: meta.summary,
                streamURL: stream
            )
        }

        VanmoLogger.network.info("[Plex] Fetched \(episodes.count) episodes for series \(seriesRatingKey)")
        return episodes
    }
}
