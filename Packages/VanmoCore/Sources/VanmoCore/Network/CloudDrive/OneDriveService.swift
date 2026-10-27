import Foundation

/// Microsoft Graph API 客户端（OneDrive 个人版 / 商业版通用 `/me/drive`）。
///
/// 路径模型：`RemoteFile.path` 编码为 `/item/{itemId}`；根目录对应 `RemoteFile.path == "/"`。
/// 下载直接使用 driveItem 返回的 `@microsoft.graph.downloadUrl`（预签名匿名直链），
/// 播放期间不需要持续携带 Bearer token。
public final class OneDriveService: RemoteFileService {
    public let type: ConnectionType = .oneDrive
    public private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let apiBase = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!
    private static let childrenSelect = "id,name,folder,size,lastModifiedDateTime"

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
        let itemId = Self.itemId(from: path)

        var files: [RemoteFile] = []
        var nextURL: URL? = try Self.childrenURL(for: itemId)

        while let url = nextURL {
            let response: OneDriveChildrenResponse = try await request(url: url, endpoint: "children")
            files.append(contentsOf: response.value.compactMap { $0.remoteFile() })
            nextURL = response.nextLink.flatMap(URL.init(string:))
        }

        return files
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        let itemId = Self.itemId(from: file.path)
        let url = Self.itemURL(for: itemId)
        let item: OneDriveItem = try await request(url: url, endpoint: "item")
        guard let downloadURLString = item.downloadURL, let downloadURL = URL(string: downloadURLString) else {
            throw NetworkError.connectionFailed("OneDrive 未返回可用下载直链")
        }
        return downloadURL
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
            throw NetworkError.transferFailed("OneDrive 下载失败 (\(httpResponse.statusCode))")
        }
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - URLs

    private static func childrenURL(for itemId: String) throws -> URL {
        let base = itemId == "root"
            ? apiBase.appendingPathComponent("root/children")
            : apiBase.appendingPathComponent("items/\(itemId)/children")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "$select", value: childrenSelect),
            URLQueryItem(name: "$top", value: "999"),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }
        return url
    }

    /// 单文件元数据请求。刻意不加 `$select`：Graph 在 `$select` 中会忽略
    /// `@microsoft.graph.downloadUrl` 这类 instance annotation，真机 2026-10-27 已复现
    /// 「item 返回 200 但没有直链」，导致缩略图、播放和下载都拿不到 URL。
    /// 整项返回的体积很小，直接取完整 driveItem。`OneDriveOAuthTests` 固定了该行为。
    static func itemURL(for itemId: String) -> URL {
        itemId == "root"
            ? apiBase.appendingPathComponent("root")
            : apiBase.appendingPathComponent("items/\(itemId)")
    }

    // MARK: - Requests

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

        #if DEBUG
        let statusCode = httpResponse.statusCode
        VanmoLogger.network.info("[Debug][OneDrive] request endpoint=\(endpoint, privacy: .public) status=\(statusCode, privacy: .public)")
#endif

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.oneDrive.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("OneDrive 响应解析失败: \(error.localizedDescription)")
            }
        case 401:
            throw NetworkError.authenticationFailed
        default:
            throw NetworkError.transferFailed(Self.errorMessage(statusCode: httpResponse.statusCode, data: data))
        }
    }

    static func errorMessage(statusCode: Int, data: Data) -> String {
        switch statusCode {
        case 403:
            let detail = graphErrorMessage(from: data) ?? "请重新登录并确认已授权 Files.Read.All。"
            return "OneDrive 权限不足：\(detail)"
        case 404:
            return "OneDrive 文件或目录不存在，可能已被移动或删除。"
        case 429:
            return "OneDrive 请求过于频繁，请稍后重试。"
        default:
            if let detail = graphErrorMessage(from: data) {
                return "OneDrive API \(statusCode): \(detail)"
            }
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            return "OneDrive API \(statusCode): \(raw)"
        }
    }

    private static func graphErrorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(GraphErrorResponse.self, from: data) else { return nil }
        let message = body.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? body.error.code : message
    }

    // MARK: - Path <-> item id

    private static func itemId(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/", !trimmed.isEmpty else { return "root" }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "item" else { return "root" }
        return String(components[1])
    }
}

// MARK: - API models

private struct OneDriveChildrenResponse: Decodable {
    let value: [OneDriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct OneDriveItem: Decodable {
    let id: String
    let name: String
    let folder: OneDriveFolderFacet?
    let size: Int64?
    let lastModifiedDateTime: Date?
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, folder, size, lastModifiedDateTime
        case downloadURL = "@microsoft.graph.downloadUrl"
    }

    public func remoteFile() -> RemoteFile? {
        let isDirectory = folder != nil
        return RemoteFile(
            name: name,
            path: "/item/\(id)",
            size: size ?? 0,
            isDirectory: isDirectory,
            modifiedDate: lastModifiedDateTime,
            type: isDirectory ? .directory : .from(filename: name)
        )
    }
}

private struct OneDriveFolderFacet: Decodable {
    let childCount: Int?
}

private struct GraphErrorResponse: Decodable {
    struct GraphError: Decodable {
        let code: String
        let message: String
    }

    let error: GraphError
}

private extension JSONDecoder {
    public static var oneDrive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
