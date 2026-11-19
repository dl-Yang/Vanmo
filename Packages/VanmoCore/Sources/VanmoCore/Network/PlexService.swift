import Foundation

/// Plex Media Server 协议实现。
///
/// 与 Emby/Jellyfin 不同，Plex 的认证流程经过 plex.tv：
/// 1. 用户名（邮箱）+ 密码发到 `https://plex.tv/api/v2/users/signin` 换取 X-Plex-Token；
/// 2. 用 token 直接访问 PMS（`http://<host>:32400`）。
///
/// PMS 默认返回 XML，所有请求都加 `Accept: application/json` 头部强制 JSON 响应。
public final class PlexService: MediaServerService, MediaSearchProviding {
    public let type: ConnectionType = .plex
    public private(set) var isConnected = false

    private var config: ConnectionConfig?
    private var token: String?
    private var resolvedBaseURL: URL?
    private let session: URLSession
    private let tokenResolver: @Sendable (UUID) -> String?
    private let tokenSaver: @Sendable (UUID, String) throws -> Void
    private let mirrorSaver: @Sendable (String, String) -> Void

    private static let plexTVBaseURL = URL(string: "https://plex.tv")!
    private static let clientName = "Vanmo"
    private static let clientVersion = "1.0.0"

    public convenience init(session: URLSession = .shared) {
        self.init(
            session: session,
            tokenResolver: { PlexCredentialStore.token(forConnectionId: $0) },
            tokenSaver: { connectionId, token in
                try PlexCredentialStore.saveToken(token, forConnectionId: connectionId)
            },
            mirrorSaver: { baseURL, token in
                PlexCredentialStore.save(baseURL: baseURL, token: token)
            }
        )
    }

    /// 内部测试注入点：`swift test` 的未签名进程无法访问 Data Protection Keychain，
    /// 因此凭据读写通过闭包注入。生产代码只使用 public init。
    init(
        session: URLSession,
        tokenResolver: @escaping @Sendable (UUID) -> String?,
        tokenSaver: @escaping @Sendable (UUID, String) throws -> Void,
        mirrorSaver: @escaping @Sendable (String, String) -> Void
    ) {
        self.session = session
        self.tokenResolver = tokenResolver
        self.tokenSaver = tokenSaver
        self.mirrorSaver = mirrorSaver
    }

    // MARK: - RemoteFileService

    public func connect(config: ConnectionConfig) async throws {
        self.config = config

        let pmsURL = try pmsBaseURL(for: config)
        self.resolvedBaseURL = pmsURL

        let authToken: String
        let authSource: String
        if let connectionId = config.connectionId,
           let stored = tokenResolver(connectionId)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            authToken = stored
            authSource = "connection"
        } else if let username = config.username?
            .trimmingCharacters(in: .whitespacesAndNewlines),
                  !username.isEmpty,
                  let password = config.password,
                  !password.isEmpty {
            authToken = try await authenticatePlexTV(login: username, password: password)
            authSource = "legacy-signin"
        } else {
            throw NetworkError.authenticationFailed
        }

        self.token = authToken

        try await verifyPMS(baseURL: pmsURL, token: authToken)

        isConnected = true

        // PIN 流程已经按连接存好 token；legacy 密码路径在这里补写，
        // 让下一次连接直接走 token-first。写入失败不影响本次已建立的连接。
        if authSource != "connection", let connectionId = config.connectionId {
            do {
                try tokenSaver(connectionId, authToken)
            } catch {
                VanmoLogger.network.error(
                    "[Plex] Failed to persist per-connection token: \(error.localizedDescription)"
                )
            }
        }
        mirrorSaver(pmsURL.absoluteString, authToken)

        VanmoLogger.network.info("[Plex] Connected to PMS auth=\(authSource, privacy: .public)")
    }

    public func disconnect() async {
        isConnected = false
        token = nil
        config = nil
        resolvedBaseURL = nil
    }

    public func makeSessionContext() throws -> PlexSessionContext {
        guard isConnected, let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }
        return PlexSessionContext(baseURL: baseURL, token: token)
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }

        let endpoint = path == "/" ? "/library/sections" : path

        VanmoLogger.network.info("[Plex] Listing: \(endpoint)")

        let data = try await getJSON(baseURL: baseURL, endpoint: endpoint, token: token)
        return try parseListing(data: data)
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }
        return makePlexURL(baseURL: baseURL, path: file.path, token: token)
    }

    public func download(
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

    public func streamMediaItems(
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

    public func searchMedia(query: String, limit: Int = 30) async throws -> [ServerMediaItem] {
        guard isConnected, let baseURL = resolvedBaseURL, let token else {
            throw NetworkError.notConnected
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        applyHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validatePlexResponse(response, body: data, context: "search media")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let mapped = (result.mediaContainer.metadata ?? []).compactMap { meta in
            mapPlexMediaItem(meta, baseURL: baseURL, token: token)
        }
        return Array(mapped.prefix(limit))
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
        mapPlexMetadataToServerItem(meta, baseURL: baseURL, token: token)
    }

    /// 从文件路径中提取文件名,兼容 Unix (`/`) 与 Windows (`\`) 分隔符。
    fileprivate static func extractFileName(from path: String) -> String? {
        let separators = CharacterSet(charactersIn: "/\\")
        let parts = path.components(separatedBy: separators)
        return parts.last(where: { !$0.isEmpty })
    }

    /// Plex 的 `guid` 字段可能形如：
    /// - `com.plexapp.agents.themoviedb://12345?lang=en`（旧版 agent）
    /// - `plex://movie/<plex internal id>`（新版 metadata，TMDB 在 Guid[] 子节点中）
    /// 这里只解析旧版 agent 格式；新版需要请求 `?includeGuids=1` 才能拿到 TMDB ID，
    /// 当前实现暂不解析。
    fileprivate static func extractTMDB(from guid: String) -> Int? {
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
            VanmoLogger.network.error("[Plex] plex.tv signin network error")
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
            VanmoLogger.network.error("[Plex] plex.tv signin failed status=\(httpResponse.statusCode)")
            throw NetworkError.connectionFailed("plex.tv signin HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(PlexAuthResponse.self, from: data)
        return result.authToken
    }

    private func verifyPMS(baseURL: URL, token: String) async throws {
        let data = try await getJSON(baseURL: baseURL, endpoint: "/identity", token: token)
        // /identity 返回 MediaContainer，只要不抛错就视为可达
        _ = data
    }

    private func pmsBaseURL(for config: ConnectionConfig) throws -> URL {
        let trimmed = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidURL }

        // 完整 endpoint URI（含 scheme）保留自身的 host 与 port，不能丢掉端口。
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           let urlHost = components.host,
           !urlHost.isEmpty {
            var normalized = components
            normalized.scheme = scheme
            if let url = normalized.url {
                return url
            }
        }

        // 裸 host：由端口推导 scheme，并补上配置端口；host 已带端口时不再拼接。
        let hostAndPort = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !hostAndPort.isEmpty else { throw NetworkError.invalidURL }

        let scheme = config.port == 443 ? "https" : "http"
        let shouldAppendPort = !Self.bareHostHasExplicitPort(hostAndPort)
            && config.port != 80
            && config.port != 443
        let portSuffix = shouldAppendPort ? ":\(config.port)" : ""
        guard let url = URL(string: "\(scheme)://\(hostAndPort)\(portSuffix)") else {
            throw NetworkError.invalidURL
        }
        return url
    }

    /// 裸 host 是否已经自带端口（含 IPv6 方括号形式），避免重复拼接。
    private static func bareHostHasExplicitPort(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            guard let closing = host.firstIndex(of: "]") else { return false }
            let suffix = host[host.index(after: closing)...]
            guard suffix.hasPrefix(":") else { return false }
            return Int(suffix.dropFirst()) != nil
        }
        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let port = Int(parts[1]),
              (1...65535).contains(port) else {
            return false
        }
        return true
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(Self.clientName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue(PlatformDeviceInfo.model, forHTTPHeaderField: "X-Plex-Device")
        request.setValue("Vanmo", forHTTPHeaderField: "X-Plex-Device-Name")
        #if os(iOS)
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        #elseif os(macOS)
        request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
        #else
        request.setValue("Unknown", forHTTPHeaderField: "X-Plex-Platform")
        #endif
        request.setValue(PlatformDeviceInfo.systemVersion, forHTTPHeaderField: "X-Plex-Platform-Version")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
    }

    private func getJSON(baseURL: URL, endpoint: String, token: String) async throws -> Data {
        let url = makePlexURL(baseURL: baseURL, path: endpoint, token: token)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        applyHeaders(to: &request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }
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

public struct PlexSessionContext: Sendable {
    public let baseURL: URL
    public let token: String
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
    let photo: [PlexPhoto]?

    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset
        case directory = "Directory"
        case metadata = "Metadata"
        case photo = "Photo"
    }
}

private struct PlexPhoto: Decodable {
    let key: String?
    let ratingKey: String?
    let selected: Bool?
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
    let viewOffset: Int?
    let viewCount: Int?
    let thumb: String?
    let art: String?
    let type: String
    /// 仅 episode 有意义,代表所属 season 编号。
    let parentIndex: Int?
    /// 仅 episode 有意义,代表本集集数。
    let index: Int?
    let parentTitle: String?
    let guid: String?
    let contentRating: String?
    let media: [PlexMedia]?
    let director: [PlexTag]?
    let role: [PlexRoleTag]?
    let genre: [PlexTag]?
    let country: [PlexTag]?
    let image: [PlexImage]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, title, originalTitle, summary, year, rating, duration
        case viewOffset, viewCount
        case thumb, art, type, parentIndex, index, parentTitle, guid, contentRating
        case media = "Media"
        case director = "Director"
        case role = "Role"
        case genre = "Genre"
        case country = "Country"
        case image = "Image"
    }
}

private struct PlexImage: Decodable {
    let type: String?
    let url: String?
}

private struct PlexMedia: Decodable {
    let id: Int?
    let duration: Int?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let videoCodec: String?
    let audioCodec: String?
    let audioChannels: Int?
    let videoResolution: String?
    let videoProfile: String?
    let container: String?
    let part: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, width, height
        case videoCodec, audioCodec, audioChannels
        case videoResolution, videoProfile, container
        case part = "Part"
    }
}

private struct PlexPart: Decodable {
    let id: Int?
    let key: String?
    let size: Int64?
    let container: String?
    let file: String?
    let stream: [PlexStream]?

    enum CodingKeys: String, CodingKey {
        case id, key, size, container, file
        case stream = "Stream"
    }
}

private struct PlexStream: Decodable {
    let streamType: Int?
    let codec: String?
    let bitDepth: Int?
    let bitrate: Int?
    let channels: Int?
    let language: String?
    let displayTitle: String?
    let colorTrc: String?
    let doviPresent: Bool?

    enum CodingKeys: String, CodingKey {
        case streamType, codec, bitDepth, bitrate, channels, language, displayTitle, colorTrc
        case doviPresent = "DOVIPresent"
    }
}

private struct PlexTag: Decodable {
    let tag: String?
}

private struct PlexRoleTag: Decodable {
    let id: Int?
    let tag: String?
    let role: String?
    let thumb: String?
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
public enum PlexCredentialStore {
    private static let baseURLKey = "plex.baseURL"
    private static let clientIdentifierKey = "plex.clientIdentifier"
    private static let tokenKeychainAccount = "plex.token"

    public static var clientIdentifier: String {
        if let id = UserDefaults.standard.string(forKey: clientIdentifierKey) {
            return id
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: clientIdentifierKey)
        return new
    }

    public static var baseURL: String? {
        UserDefaults.standard.string(forKey: baseURLKey)
    }

    public static var token: String? {
        try? KeychainManager.shared.loadString(for: tokenKeychainAccount)
    }

    public static func save(baseURL: String, token: String) {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        do {
            try KeychainManager.shared.save(token, for: tokenKeychainAccount)
        } catch {
            VanmoLogger.network.error("[Plex] Failed to persist X-Plex-Token to Keychain: \(error.localizedDescription)")
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        try? KeychainManager.shared.delete(for: tokenKeychainAccount)
    }
}

public extension PlexCredentialStore {
    /// 按连接保存 X-Plex-Token，Keychain 账号为 `conn_<uuid>_plex`。
    static func saveToken(_ token: String, forConnectionId connectionId: UUID) throws {
        try KeychainManager.shared.save(token, for: connectionTokenAccount(for: connectionId))
    }

    /// 读取某个连接自己的 X-Plex-Token；读取失败时记录一行不含 token 的日志。
    static func token(forConnectionId connectionId: UUID) -> String? {
        do {
            return try KeychainManager.shared.loadString(for: connectionTokenAccount(for: connectionId))
        } catch {
            VanmoLogger.network.error(
                "[Plex] Failed to read per-connection token from Keychain: \(error.localizedDescription)"
            )
            return nil
        }
    }

    static func deleteToken(forConnectionId connectionId: UUID) throws {
        try KeychainManager.shared.delete(for: connectionTokenAccount(for: connectionId))
    }
}

extension PlexCredentialStore {
    /// 单个 Plex 连接的 Keychain account 名；与 `conn_<uuid>`（密码槽）分开。
    static func connectionTokenAccount(for connectionId: UUID) -> String {
        "conn_\(connectionId.uuidString)_plex"
    }
}

// MARK: - Item Detail Fetcher

public enum PlexItemDetailFetcher {
    public static func fetchDetail(ratingKey: String, connection: MediaServerConnectionSnapshot) async throws -> ServerMediaItem {
        let service = PlexService()
        try await service.connect(config: connection.config)
        defer { Task { await service.disconnect() } }
        return try await fetchDetail(ratingKey: ratingKey, context: service.makeSessionContext())
    }

    public static func fetchDetail(ratingKey: String) async throws -> ServerMediaItem {
        guard let baseURLStr = PlexCredentialStore.baseURL,
              let token = PlexCredentialStore.token,
              let baseURL = URL(string: baseURLStr) else {
            throw NetworkError.notConnected
        }

        return try await fetchDetail(
            ratingKey: ratingKey,
            context: PlexSessionContext(baseURL: baseURL, token: token)
        )
    }

    private static func fetchDetail(ratingKey: String, context: PlexSessionContext) async throws -> ServerMediaItem {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(ratingKey)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: context.token)]

        guard let url = components.url else { throw NetworkError.invalidURL }

        VanmoLogger.network.info("[Plex] Fetching item detail for \(ratingKey)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch item detail")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        guard let meta = result.mediaContainer.metadata?.first else {
            throw NetworkError.transferFailed("无法解析媒体详情")
        }

        let extraBackdropURLs = (try? await fetchArtworkURLs(ratingKey: ratingKey, context: context)) ?? []
        guard let mapped = mapPlexMetadataToServerItem(
            meta,
            baseURL: context.baseURL,
            token: context.token,
            extraBackdropURLs: extraBackdropURLs
        ) else {
            throw NetworkError.transferFailed("无法解析媒体详情")
        }

        return mapped
    }

    private static func fetchArtworkURLs(
        ratingKey: String,
        context: PlexSessionContext
    ) async throws -> [URL] {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(ratingKey)/arts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: context.token)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        let container = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let photos = container.mediaContainer.photo ?? []
        let sorted = photos.sorted { ($0.selected == true ? 0 : 1) < ($1.selected == true ? 0 : 1) }
        return sorted.compactMap { photo in
            guard let key = photo.key else { return nil }
            return makePlexResourceURL(key, baseURL: context.baseURL, token: context.token)
        }
    }
}

fileprivate func makePlexResourceURL(_ pathOrURL: String, baseURL: URL, token: String) -> URL? {
    let trimmed = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return URL(string: trimmed)
    }
    let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
        return nil
    }
    if let queryIndex = normalized.firstIndex(of: "?") {
        let pathPart = String(normalized[..<queryIndex])
        let queryPart = String(normalized[normalized.index(after: queryIndex)...])
        components.path = pathPart
        components.percentEncodedQuery = queryPart
    } else {
        components.path = normalized
    }
    var items = components.queryItems ?? []
    if !items.contains(where: { $0.name == "X-Plex-Token" }) {
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
    }
    components.queryItems = items
    return components.url
}

public enum PlexIntroMarkerFetcher {
    public static func fetchWindow(
        ratingKey: String,
        connection: MediaServerConnectionSnapshot
    ) async throws -> IntroSkipWindow? {
        let service = PlexService()
        try await service.connect(config: connection.config)
        defer { Task { await service.disconnect() } }
        return try await fetchWindow(ratingKey: ratingKey, context: try service.makeSessionContext())
    }

    private static func fetchWindow(
        ratingKey: String,
        context: PlexSessionContext
    ) async throws -> IntroSkipWindow? {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(ratingKey)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "includeMarkers", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: context.token),
        ]
        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch intro markers")
        return try IntroMarkerParser.plexWindow(from: data)
    }
}

fileprivate func mapPlexMetadataToServerItem(
    _ meta: PlexMetadata,
    baseURL: URL,
    token: String,
    extraBackdropURLs: [URL] = []
) -> ServerMediaItem? {
    let mediaType: MediaType
    switch meta.type {
    case "movie": mediaType = .movie
    case "show": mediaType = .tvShow
    default: return nil
    }

    guard let ratingKey = meta.ratingKey else { return nil }

    let posterURL: URL? = meta.thumb.flatMap { thumb in
        makePlexResourceURL(thumb, baseURL: baseURL, token: token)
    }
    var backdropCandidates: [URL] = []
    if let primaryArt = meta.art.flatMap({ makePlexResourceURL($0, baseURL: baseURL, token: token) }) {
        backdropCandidates.append(primaryArt)
    }
    if let images = meta.image {
        for image in images where image.type?.lowercased() == "background" {
            if let path = image.url,
               let url = makePlexResourceURL(path, baseURL: baseURL, token: token),
               !backdropCandidates.contains(url) {
                backdropCandidates.append(url)
            }
        }
    }
    for url in extraBackdropURLs where !backdropCandidates.contains(url) {
        backdropCandidates.append(url)
    }
    let backdropURL: URL? = backdropCandidates.first

    let logoURL: URL? = meta.image?
        .first(where: { $0.type?.lowercased() == "clearlogo" })?
        .url
        .flatMap { path in
            makePlexResourceURL(path, baseURL: baseURL, token: token)
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
    let originalFileName = primaryPart?.file.flatMap { PlexService.extractFileName(from: $0) }
    let container = primaryPart?.container.flatMap { $0.isEmpty ? nil : $0 }
    let fileSize = primaryPart?.size ?? 0
    let primaryMedia = meta.media?.first
    let fallbackSize = VideoResolutionLabel.dimensions(fromResolutionToken: primaryMedia?.videoResolution)
    let videoWidth = primaryMedia?.width ?? fallbackSize?.width
    let videoHeight = primaryMedia?.height ?? fallbackSize?.height

    let videoStream = primaryPart?.stream?.first(where: { $0.streamType == 1 })
    let videoCodec = MediaCapabilityTags.normalizedVideoCodec(videoStream?.codec ?? primaryMedia?.videoCodec)
    let videoBitDepth = videoStream?.bitDepth
    let bitRate: Int? = {
        if let mediaBitrate = primaryMedia?.bitrate, mediaBitrate > 0 {
            return mediaBitrate * 1000
        }
        if let streamBitrate = videoStream?.bitrate, streamBitrate > 0 {
            return streamBitrate * 1000
        }
        return nil
    }()

    let dynamicRange: String? = {
        if videoStream?.doviPresent == true || MediaCapabilityTags.isDolbyVisionRange(primaryMedia?.videoProfile) {
            return DynamicRange.dolbyVision.rawValue
        }
        if let detected = MediaCapabilityTags.detectDynamicRangeValue(
            videoRange: primaryMedia?.videoProfile,
            colorTransfer: videoStream?.colorTrc
        ), detected != .sdr {
            return detected.rawValue
        }
        return nil
    }()

    let audioTracks: [AudioTrackInfo] = {
        let streams = (primaryPart?.stream ?? []).filter { $0.streamType == 2 }
        if !streams.isEmpty {
            return streams.enumerated().map { index, stream in
                AudioTrackInfo(
                    id: index,
                    language: stream.language,
                    title: stream.displayTitle,
                    codec: stream.codec,
                    channels: stream.channels
                )
            }
        }
        if let audioCodec = primaryMedia?.audioCodec {
            return [AudioTrackInfo(id: 0, codec: audioCodec, channels: primaryMedia?.audioChannels)]
        }
        return []
    }()

    let directors = meta.director?.compactMap(\.tag).joined(separator: ", ")
    let normalizedDirector = (directors?.isEmpty ?? true) ? nil : directors

    let roleEntries = Array((meta.role ?? []).prefix(10))
    let castMembers: [CastMemberInfo] = roleEntries.compactMap { entry in
        guard let name = entry.tag?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let roleName = entry.role?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileURL: URL? = entry.thumb.flatMap { thumb in
            if thumb.hasPrefix("http://") || thumb.hasPrefix("https://") {
                return URL(string: thumb)
            }
            let normalized = thumb.hasPrefix("/") ? thumb : "/\(thumb)"
            return URL(string: "\(baseURL.absoluteString)\(normalized)?X-Plex-Token=\(token)")
        }
        return CastMemberInfo(
            id: entry.id.map(String.init) ?? name,
            name: name,
            role: (roleName?.isEmpty == false) ? roleName : nil,
            profileRemoteURL: profileURL
        )
    }
    let cast: [String] = castMembers.map(\.name)
    let genres: [String] = meta.genre?.compactMap(\.tag) ?? []
    let countries: [String] = meta.country?.compactMap(\.tag) ?? []

    let tmdbID = meta.guid.flatMap { PlexService.extractTMDB(from: $0) }

    return ServerMediaItem(
        serverId: ratingKey,
        title: meta.title,
        originalTitle: meta.originalTitle,
        year: meta.year,
        overview: meta.summary,
        rating: meta.rating,
        contentRating: meta.contentRating,
        mediaType: mediaType,
        posterURL: posterURL,
        backdropURL: backdropURL,
        backdropURLs: backdropCandidates,
        logoURL: logoURL,
        genres: genres,
        director: normalizedDirector,
        cast: cast,
        castMembers: castMembers,
        originCountry: countries,
        tmdbID: tmdbID,
        streamURL: streamURL,
        fileSize: fileSize,
        duration: durationSeconds,
        originalFileName: originalFileName,
        container: container,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        videoCodec: videoCodec,
        videoBitDepth: videoBitDepth,
        bitRate: bitRate,
        dynamicRange: dynamicRange,
        audioTracks: audioTracks,
        showTitle: nil,
        seasonNumber: nil,
        episodeNumber: nil,
        episodeTitle: nil,
        seriesId: nil
    )
}

// MARK: - Episode Fetcher

/// 提供给 PlayerViewModel / MediaDetailView 在剧集播放时调用,按 series ratingKey
/// 拉取 Plex 服务器上的剧集列表。
public enum PlexEpisodeFetcher {
    public static func fetchEpisodes(
        seriesRatingKey: String,
        connection: MediaServerConnectionSnapshot
    ) async throws -> [EpisodeInfo] {
        let service = PlexService()
        try await service.connect(config: connection.config)
        defer { Task { await service.disconnect() } }
        return try await fetchEpisodes(seriesRatingKey: seriesRatingKey, context: service.makeSessionContext())
    }

    public static func fetchEpisodes(seriesRatingKey: String) async throws -> [EpisodeInfo] {
        try await fetchEpisodes(seriesRatingKey: seriesRatingKey, context: try credentialContext())
    }

    public static func fetchSeasons(
        seriesRatingKey: String,
        connection: MediaServerConnectionSnapshot
    ) async throws -> [SeasonInfo] {
        let service = PlexService()
        try await service.connect(config: connection.config)
        defer { Task { await service.disconnect() } }
        return try await fetchSeasons(seriesRatingKey: seriesRatingKey, context: service.makeSessionContext())
    }

    public static func fetchSeasons(seriesRatingKey: String) async throws -> [SeasonInfo] {
        try await fetchSeasons(seriesRatingKey: seriesRatingKey, context: try credentialContext())
    }

    public static func fetchEpisodesPage(
        seasonRatingKey: String,
        seasonNumber: Int,
        startIndex: Int,
        pageSize: Int,
        connection: MediaServerConnectionSnapshot
    ) async throws -> EpisodePage {
        let service = PlexService()
        try await service.connect(config: connection.config)
        defer { Task { await service.disconnect() } }
        return try await fetchEpisodesPage(
            seasonRatingKey: seasonRatingKey,
            seasonNumber: seasonNumber,
            startIndex: startIndex,
            pageSize: pageSize,
            context: service.makeSessionContext()
        )
    }

    public static func fetchEpisodesPage(
        seasonRatingKey: String,
        seasonNumber: Int,
        startIndex: Int,
        pageSize: Int
    ) async throws -> EpisodePage {
        try await fetchEpisodesPage(
            seasonRatingKey: seasonRatingKey,
            seasonNumber: seasonNumber,
            startIndex: startIndex,
            pageSize: pageSize,
            context: try credentialContext()
        )
    }

    private static func credentialContext() throws -> PlexSessionContext {
        guard let baseURLStr = PlexCredentialStore.baseURL,
              let token = PlexCredentialStore.token,
              let baseURL = URL(string: baseURLStr) else {
            throw NetworkError.notConnected
        }
        return PlexSessionContext(baseURL: baseURL, token: token)
    }

    private static func fetchEpisodes(
        seriesRatingKey: String,
        context: PlexSessionContext
    ) async throws -> [EpisodeInfo] {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(seriesRatingKey)/grandchildren"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: context.token)]

        guard let url = components.url else { throw NetworkError.invalidURL }

        VanmoLogger.network.info("[Plex] Fetching episodes for series \(seriesRatingKey)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch episodes")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let episodes = (result.mediaContainer.metadata ?? []).compactMap { meta in
            mapEpisode(meta, seasonNumberOverride: nil, context: context)
        }

        VanmoLogger.network.info("[Plex] Fetched \(episodes.count) episodes for series \(seriesRatingKey)")
        return episodes
    }

    private static func fetchSeasons(
        seriesRatingKey: String,
        context: PlexSessionContext
    ) async throws -> [SeasonInfo] {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(seriesRatingKey)/children"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: context.token)]

        guard let url = components.url else { throw NetworkError.invalidURL }

        VanmoLogger.network.info("[Plex] Fetching seasons for series \(seriesRatingKey)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch seasons")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let seasons = (result.mediaContainer.metadata ?? []).compactMap { meta -> SeasonInfo? in
            guard meta.type == "season",
                  let key = meta.ratingKey,
                  let number = meta.index else { return nil }
            return SeasonInfo(seasonNumber: number, serverId: key)
        }
        .sorted { $0.seasonNumber < $1.seasonNumber }

        VanmoLogger.network.info("[Plex] Fetched \(seasons.count) seasons for series \(seriesRatingKey)")
        return seasons
    }

    private static func fetchEpisodesPage(
        seasonRatingKey: String,
        seasonNumber: Int,
        startIndex: Int,
        pageSize: Int,
        context: PlexSessionContext
    ) async throws -> EpisodePage {
        var components = URLComponents(
            url: context.baseURL.appendingPathComponent("library/metadata/\(seasonRatingKey)/children"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: String(startIndex)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(pageSize)),
            URLQueryItem(name: "X-Plex-Token", value: context.token),
        ]

        guard let url = components.url else { throw NetworkError.invalidURL }

        VanmoLogger.network.info(
            "[Plex] Fetching episodes seasonKey=\(seasonRatingKey) season=\(seasonNumber) start=\(startIndex) limit=\(pageSize)"
        )

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlexCredentialStore.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validatePlexResponse(response, body: data, context: "fetch season episodes")

        let result = try JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        let items = (result.mediaContainer.metadata ?? []).compactMap { meta in
            mapEpisode(meta, seasonNumberOverride: seasonNumber, context: context)
        }
        let total: Int
        if let totalSize = result.mediaContainer.totalSize {
            total = totalSize
        } else if items.count >= pageSize {
            // totalSize 缺失时用「再多一页」哨兵，避免满页却被当成最后一页
            total = startIndex + items.count + 1
        } else {
            total = startIndex + items.count
        }

        VanmoLogger.network.info(
            "[Plex] Fetched \(items.count) episodes (total=\(total)) seasonKey=\(seasonRatingKey)"
        )

        return EpisodePage(items: items, totalRecordCount: total)
    }

    private static func mapEpisode(
        _ meta: PlexMetadata,
        seasonNumberOverride: Int?,
        context: PlexSessionContext
    ) -> EpisodeInfo? {
        guard meta.type == "episode",
              let key = meta.ratingKey,
              let ep = meta.index,
              let part = meta.media?.first?.part?.first,
              let partKey = part.key else { return nil }

        let season = seasonNumberOverride ?? meta.parentIndex
        guard let season else { return nil }

        let duration: TimeInterval = if let ms = meta.duration {
            Double(ms) / 1000.0
        } else {
            0
        }

        let baseURLStr = context.baseURL.absoluteString
        let stream = URL(string: "\(baseURLStr)\(partKey)?X-Plex-Token=\(context.token)")!

        let backdropURL: URL? = (meta.art ?? meta.thumb).flatMap { path in
            URL(string: "\(baseURLStr)\(path)?X-Plex-Token=\(context.token)")
        }

        let primaryMedia = meta.media?.first
        let fallbackSize = VideoResolutionLabel.dimensions(fromResolutionToken: primaryMedia?.videoResolution)
        let videoStream = part.stream?.first(where: { $0.streamType == 1 })
        let audioTracks: [AudioTrackInfo] = {
            let streams = (part.stream ?? []).filter { $0.streamType == 2 }
            if !streams.isEmpty {
                return streams.enumerated().map { index, stream in
                    AudioTrackInfo(
                        id: index,
                        language: stream.language,
                        title: stream.displayTitle,
                        codec: stream.codec,
                        channels: stream.channels
                    )
                }
            }
            if let audioCodec = primaryMedia?.audioCodec {
                return [AudioTrackInfo(id: 0, codec: audioCodec, channels: primaryMedia?.audioChannels)]
            }
            return []
        }()
        let bitRate: Int? = {
            if let mediaBitrate = primaryMedia?.bitrate, mediaBitrate > 0 { return mediaBitrate * 1000 }
            if let streamBitrate = videoStream?.bitrate, streamBitrate > 0 { return streamBitrate * 1000 }
            return nil
        }()
        let playbackPosition = meta.viewOffset.map { Double($0) / 1000.0 } ?? 0
        let isWatched = (meta.viewCount ?? 0) > 0
        let dynamicRange: String? = {
            if videoStream?.doviPresent == true || MediaCapabilityTags.isDolbyVisionRange(primaryMedia?.videoProfile) {
                return DynamicRange.dolbyVision.rawValue
            }
            if let detected = MediaCapabilityTags.detectDynamicRangeValue(
                videoRange: primaryMedia?.videoProfile,
                colorTransfer: videoStream?.colorTrc
            ), detected != .sdr {
                return detected.rawValue
            }
            return nil
        }()
        return EpisodeInfo(
            id: key,
            title: meta.title,
            seasonNumber: season,
            episodeNumber: ep,
            duration: duration,
            overview: meta.summary,
            streamURL: stream,
            backdropURL: backdropURL,
            fileSize: part.size ?? 0,
            originalFileName: part.file.flatMap(PlexService.extractFileName(from:)),
            container: part.container,
            remotePath: partKey,
            videoWidth: primaryMedia?.width ?? fallbackSize?.width,
            videoHeight: primaryMedia?.height ?? fallbackSize?.height,
            videoCodec: MediaCapabilityTags.normalizedVideoCodec(videoStream?.codec ?? primaryMedia?.videoCodec),
            videoBitDepth: videoStream?.bitDepth,
            bitRate: bitRate,
            dynamicRange: dynamicRange,
            audioTracks: audioTracks,
            lastPlaybackPosition: playbackPosition,
            isWatched: isWatched
        )
    }
}
