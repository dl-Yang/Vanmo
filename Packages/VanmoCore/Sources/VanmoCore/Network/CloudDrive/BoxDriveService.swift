import Foundation

/// Box API v2.0 客户端。
///
/// 路径模型：`RemoteFile.path` 编码为 `/item/{fileOrFolderId}`；根目录 id 固定为 `"0"`。
/// `/2.0/files/{id}/content` 需要 Bearer 鉴权发起请求，但响应是 302 到 boxcloud 匿名签名直链；
/// 这里手动拦截重定向、只取 `Location`，播放和下载期间无需再持续携带 token。
///
/// 认证说明：Box 不支持 PKCE，`OAuthCoordinator` 走带 Client Secret 的授权码流程；
/// `OAuthProviderConfiguration` 只保留空占位，真实 Secret 由构建者在本机填入，不进入仓库。
public final class BoxDriveService: RemoteFileService {
    public let type: ConnectionType = .box
    public private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let apiBase = URL(string: "https://api.box.com/2.0")!
    static let rootFolderId = "0"
    private static let itemFields = "id,name,type,size,modified_at"
    private static let pageSize = 1000

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(config: ConnectionConfig) async throws {
        guard let connectionId = config.connectionId else {
            throw NetworkError.authenticationFailed
        }
        self.connectionId = connectionId
        self.accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId)
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        accessToken = nil
        connectionId = nil
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        let folderId = Self.itemId(from: path)

        var files: [RemoteFile] = []
        var offset = 0

        while true {
            let url = try Self.itemsURL(folderId: folderId, offset: offset)
            let response: BoxItemsResponse = try await request(url: url, endpoint: "folderItems")
            files.append(contentsOf: response.entries.compactMap { $0.remoteFile() })

            offset += response.entries.count
            // `entries` 为空时即使 total_count 仍大于 offset 也必须停止，避免 Box 返回不一致计数时死循环。
            if response.entries.isEmpty || offset >= response.totalCount {
                break
            }
        }

        return files
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        let fileId = Self.itemId(from: file.path)
        return try await resolveDownloadRedirect(fileId: fileId)
    }

    public func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        let url = try await streamURL(for: file)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.transferFailed("Box 下载失败 (\(httpResponse.statusCode))")
        }
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Redirect resolution

    private func resolveDownloadRedirect(fileId: String) async throws -> URL {
        do {
            return try await performResolveDownloadRedirect(fileId: fileId)
        } catch NetworkError.authenticationFailed {
            guard let connectionId else { throw NetworkError.authenticationFailed }
            accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId, forceRefresh: true)
            return try await performResolveDownloadRedirect(fileId: fileId)
        }
    }

    private func performResolveDownloadRedirect(fileId: String) async throws -> URL {
        guard let accessToken else { throw NetworkError.notConnected }
        let url = Self.apiBase.appendingPathComponent("files/\(fileId)/content")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let delegate = NoRedirectTaskDelegate()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }
        // 302（重定向到 boxcloud 直链）也记录状态码，便于联调时确认取流路径。
        log(statusCode: httpResponse.statusCode, endpoint: "content")

        if let redirectLocation = delegate.redirectLocation {
            return redirectLocation
        }

        switch httpResponse.statusCode {
        case 401:
            throw NetworkError.authenticationFailed
        case 202:
            // 文件刚上传完成时 Box 会先返回 202 + Retry-After，稍后重试即可。
            throw NetworkError.transferFailed("Box 文件尚未准备好下载，请稍后重试。")
        default:
            throw NetworkError.transferFailed(Self.errorMessage(statusCode: httpResponse.statusCode, data: data))
        }
    }

    // MARK: - Requests

    static func itemsURL(folderId: String, offset: Int) throws -> URL {
        var components = URLComponents(
            url: apiBase.appendingPathComponent("folders/\(folderId)/items"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "fields", value: itemFields),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }
        return url
    }

    private func request<ResponseBody: Decodable>(url: URL, endpoint: String) async throws -> ResponseBody {
        do {
            return try await performRequest(url: url, endpoint: endpoint)
        } catch NetworkError.authenticationFailed {
            guard let connectionId else { throw NetworkError.authenticationFailed }
            accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId, forceRefresh: true)
            return try await performRequest(url: url, endpoint: endpoint)
        }
    }

    private func performRequest<ResponseBody: Decodable>(url: URL, endpoint: String) async throws -> ResponseBody {
        guard let accessToken else { throw NetworkError.notConnected }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }
        log(statusCode: httpResponse.statusCode, endpoint: endpoint)

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.box.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("Box 响应解析失败: \(error.localizedDescription)")
            }
        case 401:
            throw NetworkError.authenticationFailed
        default:
            throw NetworkError.transferFailed(Self.errorMessage(statusCode: httpResponse.statusCode, data: data))
        }
    }

    /// Box 可读错误文案；只使用状态码与 Box 返回的简短 `message`，不包含 token、直链或文件内容。
    static func errorMessage(statusCode: Int, data: Data) -> String {
        switch statusCode {
        case 403:
            let detail = boxErrorMessage(from: data) ?? "请确认 Box 应用已启用 Read all files and folders 权限。"
            return "Box 权限不足：\(detail)"
        case 404:
            return "Box 文件或目录不存在，可能已被移动或删除。"
        case 429:
            return "Box 请求过于频繁，请稍后重试。"
        default:
            if let detail = boxErrorMessage(from: data) {
                return "Box API \(statusCode): \(detail)"
            }
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            return "Box API \(statusCode): \(raw)"
        }
    }

    private static func boxErrorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(BoxErrorResponse.self, from: data) else { return nil }
        let message = body.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !message.isEmpty else { return body.code }
        return message
    }

    private func log(statusCode: Int, endpoint: String) {
        #if DEBUG
        VanmoLogger.network.info(
            "[Debug][Box] request endpoint=\(endpoint, privacy: .public) status=\(statusCode, privacy: .public)"
        )
        #endif
    }

    // MARK: - Path <-> item id

    /// 测试用：解码文件夹列表响应，并映射为可浏览条目（跳过 `web_link`）。
    static func remoteFiles(fromItemsData data: Data) throws -> (totalCount: Int, files: [RemoteFile]) {
        let response = try JSONDecoder.box.decode(BoxItemsResponse.self, from: data)
        return (response.totalCount, response.entries.compactMap { $0.remoteFile() })
    }

    static func itemId(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/", !trimmed.isEmpty else { return rootFolderId }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "item" else { return rootFolderId }
        return String(components[1])
    }
}

/// 拦截 302，只取 `Location`，避免 URLSession 自动带着 Authorization 头跟到 boxcloud 签名直链上。
private final class NoRedirectTaskDelegate: NSObject, URLSessionTaskDelegate {
    public private(set) var redirectLocation: URL?

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectLocation = request.url
        completionHandler(nil)
    }
}

// MARK: - API models

private struct BoxItemsResponse: Decodable {
    let totalCount: Int
    let entries: [BoxItem]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case entries
    }
}

private struct BoxItem: Decodable {
    let id: String
    let name: String
    let type: String
    let size: Int64?
    let modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, size
        case modifiedAt = "modified_at"
    }

    func remoteFile() -> RemoteFile? {
        let isDirectory = type == "folder"
        // web_link 等非文件/目录条目没有可浏览的播放路径，直接跳过。
        guard isDirectory || type == "file" else { return nil }
        return RemoteFile(
            name: name,
            path: "/item/\(id)",
            size: size ?? 0,
            isDirectory: isDirectory,
            modifiedDate: modifiedAt,
            type: isDirectory ? .directory : .from(filename: name)
        )
    }
}

private struct BoxErrorResponse: Decodable {
    let code: String
    let message: String?
}

private extension JSONDecoder {
    static var box: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
