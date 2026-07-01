import Foundation

/// Box API v2.0 客户端。
///
/// 路径模型：`RemoteFile.path` 编码为 `/item/{fileOrFolderId}`；根目录 id 固定为 `"0"`。
/// `/2.0/files/{id}/content` 需要 Bearer 鉴权发起请求，但响应是 302 到 boxcloud 匿名签名直链；
/// 这里手动拦截重定向、只取 `Location`，播放期间无需再持续携带 token。
final class BoxDriveService: RemoteFileService {
    let type: ConnectionType = .box
    private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let apiBase = URL(string: "https://api.box.com/2.0")!
    private static let rootFolderId = "0"
    private static let itemFields = "id,name,type,size,modified_at"
    private static let pageSize = 1000

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(config: ConnectionConfig) async throws {
        guard let connectionId = config.connectionId else {
            throw NetworkError.authenticationFailed
        }
        self.connectionId = connectionId
        self.accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId)
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
        accessToken = nil
        connectionId = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        let folderId = Self.itemId(from: path)

        var files: [RemoteFile] = []
        var offset = 0

        while true {
            let url = try Self.itemsURL(folderId: folderId, offset: offset)
            let response: BoxItemsResponse = try await request(url: url)
            files.append(contentsOf: response.entries.compactMap { $0.remoteFile() })

            offset += response.entries.count
            if response.entries.isEmpty || offset >= response.totalCount {
                break
            }
        }

        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        let fileId = Self.itemId(from: file.path)
        return try await resolveDownloadRedirect(fileId: fileId)
    }

    func download(
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
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        if let redirectLocation = delegate.redirectLocation {
            return redirectLocation
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }
        if httpResponse.statusCode == 401 {
            throw NetworkError.authenticationFailed
        }
        throw NetworkError.connectionFailed("Box 未返回下载直链 (\(httpResponse.statusCode))")
    }

    // MARK: - Requests

    private static func itemsURL(folderId: String, offset: Int) throws -> URL {
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

    private func request<ResponseBody: Decodable>(url: URL) async throws -> ResponseBody {
        do {
            return try await performRequest(url: url)
        } catch NetworkError.authenticationFailed {
            guard let connectionId else { throw NetworkError.authenticationFailed }
            accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId, forceRefresh: true)
            return try await performRequest(url: url)
        }
    }

    private func performRequest<ResponseBody: Decodable>(url: URL) async throws -> ResponseBody {
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

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.box.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("Box 响应解析失败: \(error.localizedDescription)")
            }
        case 401:
            throw NetworkError.authenticationFailed
        case 429:
            throw NetworkError.transferFailed("Box 请求过于频繁，请稍后重试")
        default:
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("Box API \(httpResponse.statusCode): \(message)")
        }
    }

    // MARK: - Path <-> item id

    private static func itemId(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/", !trimmed.isEmpty else { return rootFolderId }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "item" else { return rootFolderId }
        return String(components[1])
    }
}

/// 拦截 302，只取 `Location`，避免 URLSession 自动带着 Authorization 头跟到 boxcloud 签名直链上。
private final class NoRedirectTaskDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var redirectLocation: URL?

    func urlSession(
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

private extension JSONDecoder {
    static var box: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
