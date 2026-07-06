import Foundation

/// pCloud API 客户端。
///
/// pCloud 的 OAuth token 不会过期、也不签发 refresh_token，鉴权固定通过
/// `access_token` 查询参数（而不是 `Authorization` 头）传递给几乎所有接口。
/// 登录时返回的 `hostname`（`api.pcloud.com` 美国节点 / `eapi.pcloud.com` 欧洲节点）
/// 决定后续所有请求应该打到哪个数据中心，保存在 `OAuthCredential.apiHost` 里。
///
/// 路径模型：`RemoteFile.path` 编码为 `/folder/{folderId}` 或 `/file/{fileId}`；
/// 根目录固定为 pCloud 的 `folderid = 0`。
public final class PCloudDriveService: RemoteFileService {
    public let type: ConnectionType = .pCloudDrive
    public private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?
    private var apiHost = "api.pcloud.com"

    private static let defaultHost = "api.pcloud.com"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(config: ConnectionConfig) async throws {
        guard let connectionId = config.connectionId else {
            throw NetworkError.authenticationFailed
        }
        guard let credential = try OAuthCredentialStore.load(connectionId: connectionId) else {
            throw NetworkError.authenticationFailed
        }
        self.connectionId = connectionId
        self.accessToken = credential.accessToken
        self.apiHost = credential.apiHost ?? Self.defaultHost
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        accessToken = nil
        connectionId = nil
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        let folderId = Self.folderId(from: path)

        let response: PCloudListFolderResponse = try await request(
            method: "listfolder",
            queryItems: [
                URLQueryItem(name: "folderid", value: String(folderId)),
                URLQueryItem(name: "noshares", value: "1"),
            ]
        )
        return response.metadata.contents?.compactMap { $0.remoteFile() } ?? []
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard let fileId = Self.fileId(from: file.path) else {
            throw NetworkError.invalidURL
        }
        let response: PCloudFileLinkResponse = try await request(
            method: "getfilelink",
            queryItems: [URLQueryItem(name: "fileid", value: String(fileId))]
        )
        guard let host = response.hosts.first, let path = response.path,
              let url = URL(string: "https://\(host)\(path)") else {
            throw NetworkError.connectionFailed("pCloud 未返回可用下载直链")
        }
        return url
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
            throw NetworkError.transferFailed("pCloud 下载失败 (\(httpResponse.statusCode))")
        }
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Requests

    private func request<ResponseBody: PCloudResponse>(
        method: String,
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        guard let accessToken else { throw NetworkError.notConnected }

        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.path = "/\(method)"
        components.queryItems = queryItems + [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.connectionFailed("pCloud HTTP 请求失败")
        }

        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw NetworkError.transferFailed("pCloud 响应解析失败: \(error.localizedDescription)")
        }

        guard decoded.result == 0 else {
            if Self.isAuthError(decoded.result) {
                throw NetworkError.authenticationFailed
            }
            throw NetworkError.transferFailed("pCloud API 错误 \(decoded.result): \(decoded.error ?? "未知错误")")
        }
        return decoded
    }

    /// pCloud 1xxx/2xxx 段里和登录/鉴权相关的错误码（详见 pCloud API 文档 "Error codes"）。
    private static func isAuthError(_ code: Int) -> Bool {
        [1000, 2000, 2094, 4000].contains(code)
    }

    // MARK: - Path <-> ids

    private static func folderId(from path: String) -> Int64 {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/", !trimmed.isEmpty else { return 0 }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "folder", let id = Int64(components[1]) else { return 0 }
        return id
    }

    private static func fileId(from path: String) -> Int64? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "file" else { return nil }
        return Int64(components[1])
    }
}

// MARK: - API models

private protocol PCloudResponse: Decodable {
    var result: Int { get }
    var error: String? { get }
}

private struct PCloudListFolderResponse: PCloudResponse {
    let result: Int
    let error: String?
    let metadata: PCloudMetadata
}

private struct PCloudMetadata: Decodable {
    let contents: [PCloudEntry]?
}

private struct PCloudEntry: Decodable {
    let name: String
    let isfolder: Bool
    let folderid: Int64?
    let fileid: Int64?
    let size: Int64?
    let modified: String?

    public func remoteFile() -> RemoteFile? {
        if isfolder {
            guard let folderid else { return nil }
            return RemoteFile(
                name: name,
                path: "/folder/\(folderid)",
                size: 0,
                isDirectory: true,
                modifiedDate: modified.flatMap(PCloudDateParser.parse),
                type: .directory
            )
        } else {
            guard let fileid else { return nil }
            return RemoteFile(
                name: name,
                path: "/file/\(fileid)",
                size: size ?? 0,
                isDirectory: false,
                modifiedDate: modified.flatMap(PCloudDateParser.parse),
                type: .from(filename: name)
            )
        }
    }
}

private struct PCloudFileLinkResponse: PCloudResponse {
    let result: Int
    let error: String?
    let hosts: [String]
    let path: String?
}

private enum PCloudDateParser {
    // pCloud 时间格式形如 "Wed, 01 Jul 2026 07:00:00 +0000"（RFC 1123）。
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    public static func parse(_ string: String) -> Date? {
        formatter.date(from: string)
    }
}
