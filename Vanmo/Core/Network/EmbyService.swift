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

        #if DEBUG
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Auth URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Auth status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Auth body:\n\(EmbyDebugLog.describe(data: data))")
        #endif

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
            apiPrefix: apiPrefix,
            userId: authResult.user.id
        )

        VanmoLogger.network.info("[\(self.type.displayName)] Authenticated as \(authResult.user.name), userId=\(authResult.user.id)")
    }

    func disconnect() async {
        isConnected = false
        accessToken = nil
        userId = nil
        config = nil
    }

    /// 复用已持久化的会话信息，避免每次都重新 AuthenticateByName。
    /// 调用方应在后续执行 `validateSession()`，无效时回退到完整认证流程。
    func restoreSession(config: ConnectionConfig, token: String, userId: String) {
        self.config = config
        self.accessToken = token
        self.userId = userId
        self.isConnected = true
    }

    /// 校验当前 access token 是否仍然有效。
    func validateSession() async throws {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: token)]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateEmbyResponse(response, body: data, context: "validate stored session")
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

        #if DEBUG
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] List URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] List status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] List body:\n\(EmbyDebugLog.describe(data: data))")
        #endif

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

        #if DEBUG
        let downloadedSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? -1
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Download URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Download status: \((response as? HTTPURLResponse)?.statusCode ?? -1) bytes=\(downloadedSize)")
        #endif

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

        #if DEBUG
        if let since {
            VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Scan mode: INCREMENTAL since \(Self.embyDateFormatter.string(from: since))")
        } else {
            VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Scan mode: FULL (no since filter)")
        }
        #endif

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
                URLQueryItem(name: "Fields", value: "Overview,Genres,People,ProductionYear,ProviderIds,OriginalTitle,RunTimeTicks,MediaSources,ProductionLocations,DateLastSaved,SeriesName,SeriesId,ParentIndexNumber,IndexNumber"),
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

            #if DEBUG
            VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Scan page=\(page) URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
            VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Scan page=\(page) status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Scan page=\(page) body:\n\(EmbyDebugLog.describe(data: data))")
            #endif

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
        EmbyItemMapper.map(item, baseURL: baseURL, apiPrefix: apiPrefix, token: token)
    }

    /// 从 Emby 返回的 Path 中提取文件名，兼容 Unix (`/`) 与 Windows (`\`) 分隔符。
    static func extractFileName(from path: String) -> String? {
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

    // MARK: - Live Library API

    private static let liveItemFields =
        "Overview,Genres,People,ProductionYear,ProviderIds,OriginalTitle,RunTimeTicks,MediaSources,ProductionLocations,DateCreated,SeriesName,SeriesId,ParentIndexNumber,IndexNumber,UserData"

    private static func includeItemTypes(for collectionType: EmbyCollectionType) -> String {
        switch collectionType {
        case .movies:
            return "Movie"
        case .tvshows:
            return "Series"
        case .playlists:
            return "Movie,Series,Video"
        }
    }

    /// 拉取 `/Library/VirtualFolders`，仅保留 movies / tvshows / playlists。
    func fetchVirtualFolders(
        connectionId: UUID,
        connectionName: String
    ) async throws -> [CollectionFolder] {
        guard isConnected, let config, let token = accessToken else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Library/VirtualFolders"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: token)]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] VirtualFolders URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] VirtualFolders status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        #endif

        try validateEmbyResponse(response, body: data, context: "fetch virtual folders")

        let folders = try Self.makeJSONDecoder().decode([EmbyVirtualFolder].self, from: data)
        let baseStr = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = apiPrefix.isEmpty ? "" : apiPrefix

        return folders.compactMap { folder in
            guard let collectionType = EmbyCollectionType(raw: folder.collectionType) else {
                return nil
            }

            let imageItemId = folder.primaryImageItemId ?? folder.id
            let posterURL = URL(
                string: "\(baseStr)/\(prefix)Items/\(imageItemId)/Images/Primary?maxHeight=600&quality=90&api_key=\(token)"
            )

            return CollectionFolder(
                id: folder.id,
                name: folder.name,
                collectionType: collectionType,
                posterURL: posterURL,
                serverConnectionId: connectionId,
                serverConnectionName: connectionName
            )
        }
    }

    /// CollectionFolder 二级列表。
    func fetchCollectionFolderItems(
        parentId: String,
        collectionType: EmbyCollectionType,
        startIndex: Int = 0,
        pageSize: Int = 50
    ) async throws -> ServerItemsPage {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "IncludeItemTypes", value: Self.includeItemTypes(for: collectionType)),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: Self.liveItemFields),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(pageSize)),
            URLQueryItem(name: "api_key", value: token),
        ]

        return try await fetchItemsPage(components: components, baseURL: base, token: token, context: "fetch collection folder items")
    }

    /// 继续观看。
    func fetchResumeItems(limit: Int = 20) async throws -> [ServerMediaItem] {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items/Resume"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            // Emby Resume 端点默认不递归且类型范围窄，需显式带上
            // Recursive + MediaTypes=Video 才能拿到全部正在观看的视频。
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "MediaTypes", value: "Video"),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.liveItemFields),
            URLQueryItem(name: "api_key", value: token),
        ]

        let page = try await fetchItemsPage(components: components, baseURL: base, token: token, context: "fetch resume items")
        return page.items
    }

    /// 最近添加。
    func fetchLatestItems(limit: Int = 20) async throws -> [ServerMediaItem] {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items/Latest"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
            URLQueryItem(name: "Fields", value: Self.liveItemFields),
            URLQueryItem(name: "api_key", value: token),
        ]

        let page = try await fetchItemsPage(components: components, baseURL: base, token: token, context: "fetch latest items")
        return page.items
    }

    /// 收藏。
    func fetchFavoriteItems() async throws -> [ServerMediaItem] {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Filters", value: "IsFavorite"),
            URLQueryItem(name: "Recursive", value: "true"),
            // 收藏可以是 Movie / Series / Episode / 通用 Video，统一放宽。
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Episode,Video"),
            URLQueryItem(name: "Fields", value: Self.liveItemFields),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "api_key", value: token),
        ]

        let page = try await fetchItemsPage(components: components, baseURL: base, token: token, context: "fetch favorite items")
        return page.items
    }

    /// 设置条目的收藏状态。
    func setFavorite(itemId: String, isFavorite: Bool) async throws {
        guard isConnected, let config, let token = accessToken, let userId else {
            throw NetworkError.notConnected
        }

        let base = baseURL(for: config)
        var components = URLComponents(
            url: base.appendingPathComponent("\(apiPrefix)Users/\(userId)/FavoriteItems/\(itemId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "api_key", value: token)]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = isFavorite ? "POST" : "DELETE"
        request.timeoutInterval = 15
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Set favorite URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] Set favorite status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        #endif

        try validateEmbyResponse(response, body: data, context: "set favorite")
    }

    private func fetchItemsPage(
        components: URLComponents,
        baseURL: URL,
        token: String,
        context: String
    ) async throws -> ServerItemsPage {
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        addAuth(to: &request)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] \(context) URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][\(self.type.displayName)] \(context) status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        #endif

        try validateEmbyResponse(response, body: data, context: context)

        // 不同 Emby 端点的响应 shape 不一致：
        //  - `/Users/{id}/Items`、`/Users/{id}/Items/Resume` 返回 `{Items, TotalRecordCount}` 包装。
        //  - `/Users/{id}/Items/Latest` 直接返回 `[BaseItemDto, ...]` 顶层数组。
        // 这里同时兼容两种格式，保持上层 ServerItemsPage 不变。
        let topLevelIsArray: Bool = {
            guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return false
            }
            return obj is [Any]
        }()

        let detailItems: [EmbyMediaDetail]
        let totalCount: Int
        if topLevelIsArray {
            detailItems = try Self.makeJSONDecoder().decode([EmbyMediaDetail].self, from: data)
            totalCount = detailItems.count
        } else {
            let result = try Self.makeJSONDecoder().decode(EmbyMediaResponse.self, from: data)
            detailItems = result.items
            totalCount = result.totalRecordCount
        }

        let mapped = detailItems.compactMap { item in
            EmbyItemMapper.map(item, baseURL: baseURL, apiPrefix: apiPrefix, token: token)
        }

        return ServerItemsPage(items: mapped, totalRecordCount: totalCount)
    }

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Emby 常见输出 `2026-05-23T12:10:31.0000000Z`（7 位 fractional），
            // ISO8601DateFormatter 只支持 3 位，先把多余位截掉再解析。
            let normalized = string.replacingOccurrences(
                of: #"\.(\d{3})\d+"#,
                with: ".$1",
                options: .regularExpression
            )
            if let date = iso8601WithFractional.date(from: normalized) ?? iso8601Basic.date(from: normalized) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

}

// MARK: - Item Mapping

fileprivate enum EmbyItemMapper {
    static func map(
        _ item: EmbyMediaDetail,
        baseURL: URL,
        apiPrefix: String,
        token: String
    ) -> ServerMediaItem? {
        let mediaType = MediaType.from(embyType: item.type)
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = apiPrefix.isEmpty ? "" : apiPrefix

        let posterURL: URL? = if item.imageTags?.primary != nil {
            URL(string: "\(base)/\(prefix)Items/\(item.id)/Images/Primary?maxHeight=600&quality=90&api_key=\(token)")
        } else {
            nil
        }

        let backdropURL: URL? = if let backdrops = item.backdropImageTags, !backdrops.isEmpty {
            URL(string: "\(base)/\(prefix)Items/\(item.id)/Images/Backdrop?maxWidth=1920&quality=80&api_key=\(token)")
        } else {
            nil
        }

        let streamURL: URL
        if mediaType == .tvShow {
            streamURL = URL(string: "vanmo://series/\(item.id)")!
        } else if mediaType.isBrowsable {
            streamURL = URL(string: "vanmo://emby-container/\(item.id)")!
        } else if mediaType == .audio {
            streamURL = URL(string: "\(base)/\(prefix)Audio/\(item.id)/stream?api_key=\(token)")!
        } else if mediaType == .photo {
            streamURL = URL(string: "\(base)/\(prefix)Items/\(item.id)/Images/Primary?api_key=\(token)")!
        } else if mediaType == .movie || mediaType == .tvEpisode || mediaType == .other {
            streamURL = URL(string: "\(base)/\(prefix)Videos/\(item.id)/stream?static=true&api_key=\(token)")!
        } else {
            streamURL = URL(string: "vanmo://emby-item/\(item.id)")!
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

        let primarySource = item.mediaSources?.first
        let originalFileName = primarySource?.path.flatMap(EmbyService.extractFileName(from:))
        let container = primarySource?.container.flatMap { $0.isEmpty ? nil : $0 }
        let fileSize = primarySource?.size ?? 0

        let showTitle = item.seriesName
        let seasonNumber = item.parentIndexNumber
        let episodeNumber = item.indexNumber
        let episodeTitle = mediaType == .tvEpisode ? item.name : nil

        let lastPlaybackPosition: TimeInterval = if let ticks = item.userData?.playbackPositionTicks {
            Double(ticks) / 10_000_000.0
        } else {
            0
        }

        // Emby Resume API 返回的项一定有 PlaybackPositionTicks，但 LastPlayedDate
        // 在某些版本/配置下可能缺失。为了让"继续观看"能识别，这种情况用
        // dateCreated 作 fallback，保留 nil 行为仅限于完全没看过的项。
        let resolvedLastPlayedAt: Date? = {
            if let date = item.userData?.lastPlayedDate {
                return date
            }
            if lastPlaybackPosition > 0 {
                return item.dateCreated ?? Date()
            }
            return nil
        }()

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
            originCountry: item.productionLocations ?? [],
            tmdbID: tmdbID,
            streamURL: streamURL,
            fileSize: fileSize,
            duration: durationSeconds,
            originalFileName: originalFileName,
            container: container,
            showTitle: showTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            seriesId: item.seriesId,
            dateCreated: item.dateCreated,
            lastPlayedAt: resolvedLastPlayedAt,
            lastPlaybackPosition: lastPlaybackPosition,
            isFavoriteOnServer: item.userData?.isFavorite ?? false
        )
    }
}

// MARK: - Debug Logging Helpers

/// Emby / Jellyfin 网络请求的调试日志工具。
///
/// 仅在 DEBUG 构建中使用，目的是让真机 / 模拟器调试时能在 Xcode Console
/// 看到「请求 URL + 状态码 + 响应体」。所有输出会做两件事：
///
/// 1. 把 URL 里的 `api_key` / `X-Emby-Token` / `AccessToken` 等查询参数脱敏成
///    `=***`，避免在控制台粘贴时把 access token 顺手贴出去。
/// 2. 把响应 JSON 里的 `AccessToken`、`Password`、`Pw` 等字段递归脱敏；非 JSON
///    或解析失败时降级为原始字符串预览。
///
/// 响应体最长截断到 `maxLength` 字符（默认 4000），避免单条日志把 Console
/// 撑爆——扫库分页的响应单页可达数百 KB。
fileprivate enum EmbyDebugLog {
    /// JSON 中需要脱敏的字段名（大小写不敏感）。
    private static let sensitiveJSONKeys: Set<String> = [
        "accesstoken",
        "access_token",
        "token",
        "password",
        "pw",
        "x-emby-token",
        "api_key",
        "apikey",
    ]

    /// URL 查询参数中需要脱敏的 key（大小写不敏感）。
    private static let sensitiveURLKeys: [String] = [
        "api_key",
        "ApiKey",
        "AccessToken",
        "X-Emby-Token",
        "X-MediaBrowser-Token",
        "Pw",
    ]

    /// 返回脱敏后的 URL 字符串：把 `?api_key=xxx` 替换成 `?api_key=***`。
    static func redactURL(_ urlString: String) -> String {
        var result = urlString
        for key in sensitiveURLKeys {
            let pattern = "(?i)(\(NSRegularExpression.escapedPattern(for: key)))=[^&]*"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1=***"
            )
        }
        return result
    }

    /// 把响应 `Data` 描述为可读字符串：优先美化 JSON，必要时截断。
    static func describe(data: Data, maxLength: Int = 4000) -> String {
        if data.isEmpty {
            return "<empty>"
        }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            let sanitized = sanitize(obj)
            if let pretty = try? JSONSerialization.data(
                withJSONObject: sanitized,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            ), let str = String(data: pretty, encoding: .utf8) {
                return truncate(str, max: maxLength, totalBytes: data.count)
            }
        }
        if let str = String(data: data, encoding: .utf8) {
            return truncate(str, max: maxLength, totalBytes: data.count)
        }
        return "<binary \(data.count) bytes>"
    }

    private static func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var copy: [String: Any] = [:]
            copy.reserveCapacity(dict.count)
            for (k, v) in dict {
                if sensitiveJSONKeys.contains(k.lowercased()) {
                    copy[k] = "***"
                } else {
                    copy[k] = sanitize(v)
                }
            }
            return copy
        }
        if let arr = value as? [Any] {
            return arr.map(sanitize)
        }
        return value
    }

    private static func truncate(_ str: String, max: Int, totalBytes: Int) -> String {
        guard str.count > max else { return str }
        return String(str.prefix(max)) + "\n...[truncated, total \(totalBytes) bytes]"
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
    let dateCreated: Date?
    let userData: EmbyUserData?

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
        case dateCreated = "DateCreated"
        case userData = "UserData"
    }
}

private struct EmbyUserData: Decodable {
    let playbackPositionTicks: Int64?
    let isFavorite: Bool?
    let lastPlayedDate: Date?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case isFavorite = "IsFavorite"
        case lastPlayedDate = "LastPlayedDate"
    }
}

private struct EmbyVirtualFolder: Decodable {
    let name: String
    let id: String
    let collectionType: String?
    let primaryImageItemId: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case collectionType = "CollectionType"
        case primaryImageItemId = "PrimaryImageItemId"
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

// MARK: - Connection Helper

enum EmbyConnectionHelper {
    static func connect(_ connection: SavedConnection) async throws -> EmbyService {
        guard connection.type == .emby || connection.type == .jellyfin else {
            throw NetworkError.unsupportedProtocol
        }

        let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        let config = ConnectionConfig(from: connection, password: password)
        let service = EmbyService(
            type: connection.type,
            apiPrefix: connection.type == .jellyfin ? "" : "emby/"
        )

        if shouldTryStoredSession(connection: connection, config: config),
           let token = EmbyCredentialStore.token,
           let userId = EmbyCredentialStore.userId {
            service.restoreSession(config: config, token: token, userId: userId)
            do {
                try await service.validateSession()
                VanmoLogger.network.info("[\(connection.type.displayName)] Reused stored session for \(connection.name)")
                return service
            } catch let error as NetworkError {
                await service.disconnect()
                if case .authenticationFailed = error {
                    VanmoLogger.network.info("[\(connection.type.displayName)] Stored session expired for \(connection.name), fallback to re-auth")
                } else {
                    throw error
                }
            } catch {
                await service.disconnect()
                throw error
            }
        }

        try await service.connect(config: config)
        return service
    }

    private static func shouldTryStoredSession(
        connection: SavedConnection,
        config: ConnectionConfig
    ) -> Bool {
        guard let storedBaseURL = EmbyCredentialStore.baseURL else {
            return false
        }

        let expectedPrefix = connection.type == .jellyfin ? "" : "emby/"
        guard EmbyCredentialStore.apiPrefix == expectedPrefix else {
            return false
        }

        return normalizedBaseURLString(for: config) == normalizeBaseURLString(storedBaseURL)
    }

    private static func normalizedBaseURLString(for config: ConnectionConfig) -> String {
        let host = config.host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let raw: String
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            raw = host
        } else {
            let scheme = config.port == 443 ? "https" : "http"
            let portSuffix = (config.port == 80 || config.port == 443) ? "" : ":\(config.port)"
            raw = "\(scheme)://\(host)\(portSuffix)"
        }
        return normalizeBaseURLString(raw)
    }

    private static func normalizeBaseURLString(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
    }
}

enum EmbyFavoriteUpdater {
    @MainActor
    static func setFavorite(_ item: MediaItem, isFavorite: Bool) async throws {
        guard let itemId = item.serverId else { return }
        guard let baseURLString = EmbyCredentialStore.baseURL,
              let token = EmbyCredentialStore.token,
              let userId = EmbyCredentialStore.userId,
              let baseURL = URL(string: baseURLString) else {
            throw NetworkError.notConnected
        }

        let service = EmbyService(
            type: EmbyCredentialStore.apiPrefix.isEmpty ? .jellyfin : .emby,
            apiPrefix: EmbyCredentialStore.apiPrefix
        )
        let config = ConnectionConfig(
            type: service.type,
            host: baseURL.absoluteString,
            username: nil,
            password: nil
        )
        service.restoreSession(config: config, token: token, userId: userId)
        try await service.setFavorite(itemId: itemId, isFavorite: isFavorite)
    }
}

// MARK: - Collection Folder Items Fetcher

enum CollectionFolderItemsFetcher {
    static func fetchPage(
        connection: SavedConnection,
        parentId: String,
        collectionType: EmbyCollectionType,
        startIndex: Int,
        pageSize: Int
    ) async throws -> ServerItemsPage {
        let service = try await EmbyConnectionHelper.connect(connection)
        defer { Task { await service.disconnect() } }
        return try await service.fetchCollectionFolderItems(
            parentId: parentId,
            collectionType: collectionType,
            startIndex: startIndex,
            pageSize: pageSize
        )
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
    private static let userIdKey = "emby.userId"
    private static let legacyTokenKey = "emby.accessToken"
    private static let tokenKeychainAccount = "emby.accessToken"

    static func save(baseURL: String, token: String, apiPrefix: String, userId: String) {
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        UserDefaults.standard.set(apiPrefix, forKey: apiPrefixKey)
        UserDefaults.standard.set(userId, forKey: userIdKey)
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

    static var userId: String? {
        UserDefaults.standard.string(forKey: userIdKey)
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
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        try? KeychainManager.shared.delete(for: tokenKeychainAccount)
    }
}

// MARK: - Child Items (Folder / Season navigation)

enum EmbyChildItemsFetcher {
    static func fetchChildren(parentId: String) async throws -> [ServerMediaItem] {
        guard let baseURLStr = EmbyCredentialStore.baseURL,
              let token = EmbyCredentialStore.token,
              let userId = EmbyCredentialStore.userId,
              let baseURL = URL(string: baseURLStr) else {
            throw NetworkError.notConnected
        }
        let apiPrefix = EmbyCredentialStore.apiPrefix

        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(apiPrefix)Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "Fields", value: "Overview,Genres,People,ProductionYear,ProviderIds,OriginalTitle,RunTimeTicks,MediaSources,ProductionLocations,SeriesName,SeriesId,ParentIndexNumber,IndexNumber"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "api_key", value: token),
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        VanmoLogger.network.info("[MediaServer] Fetching children for parent \(parentId)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")

        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        VanmoLogger.network.debug("[Debug][MediaServer] Children URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][MediaServer] Children status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        VanmoLogger.network.debug("[Debug][MediaServer] Children body:\n\(EmbyDebugLog.describe(data: data))")
        #endif

        try validateEmbyResponse(response, body: data, context: "fetch child items")

        let result = try JSONDecoder().decode(EmbyMediaResponse.self, from: data)
        let mapped = result.items.compactMap { item in
            EmbyItemMapper.map(item, baseURL: baseURL, apiPrefix: apiPrefix, token: token)
        }
        VanmoLogger.network.info("[MediaServer] Fetched \(mapped.count) children for parent \(parentId)")
        return mapped
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

        #if DEBUG
        VanmoLogger.network.debug("[Debug][MediaServer] Episodes URL: \(EmbyDebugLog.redactURL(url.absoluteString))")
        VanmoLogger.network.debug("[Debug][MediaServer] Episodes status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        VanmoLogger.network.debug("[Debug][MediaServer] Episodes body:\n\(EmbyDebugLog.describe(data: data))")
        #endif

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
