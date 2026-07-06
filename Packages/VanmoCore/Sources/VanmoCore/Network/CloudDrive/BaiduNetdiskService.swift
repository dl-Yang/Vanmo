import Foundation

/// 百度网盘开放平台 REST 客户端（简化模式 OAuth，无 refresh_token）。
///
/// 路径模型：
/// - 目录：`RemoteFile.path` 为百度绝对路径（如 `/Movies`），根目录为 `/`
/// - 文件：`RemoteFile.path` 编码为 `/file/{fs_id}`，供 `filemetas` 换取 dlink
///
/// 所有 API 请求须携带 `User-Agent: pan.baidu.com`。
public final class BaiduNetdiskService: RemoteFileService {
    public static let requiredUserAgent = "pan.baidu.com"

    public let type: ConnectionType = .baiduNetdisk
    public private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let fileListBase = URL(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
    private static let multimediaBase = URL(string: "https://pan.baidu.com/rest/2.0/xpan/multimedia")!
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
        let dir = Self.directoryPath(from: path)

        var files: [RemoteFile] = []
        var page = 1

        while true {
            let response: BaiduFileListResponse = try await requestFileList(
                queryItems: [
                    URLQueryItem(name: "method", value: "list"),
                    URLQueryItem(name: "dir", value: dir),
                    URLQueryItem(name: "limit", value: String(Self.pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "order", value: "name"),
                    URLQueryItem(name: "desc", value: "0"),
                ]
            )
            files.append(contentsOf: response.list.compactMap { $0.remoteFile() })

            if response.list.count < Self.pageSize {
                break
            }
            page += 1
        }

        return files
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        let fsId = try Self.fsId(from: file.path)
        let meta: BaiduFileMetaResponse = try await requestMultimedia(
            queryItems: [
                URLQueryItem(name: "method", value: "filemetas"),
                URLQueryItem(name: "fsids", value: "[\(fsId)]"),
                URLQueryItem(name: "dlink", value: "1"),
            ]
        )
        guard let item = meta.list.first,
              let dlink = item.dlink,
              !dlink.isEmpty,
              let accessToken else {
            throw NetworkError.connectionFailed("百度网盘未返回可用下载直链")
        }

        let separator = dlink.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(dlink)\(separator)access_token=\(accessToken)") else {
            throw NetworkError.invalidURL
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
        request.setValue(Self.requiredUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.authenticationFailed
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NetworkError.transferFailed("百度网盘下载失败 (\(httpResponse.statusCode))")
            }
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Requests

    private func requestFileList(queryItems: [URLQueryItem]) async throws -> BaiduFileListResponse {
        try await performRequest(base: Self.fileListBase, queryItems: queryItems)
    }

    private func requestMultimedia<ResponseBody: Decodable>(queryItems: [URLQueryItem]) async throws -> ResponseBody {
        try await performRequest(base: Self.multimediaBase, queryItems: queryItems)
    }

    private func performRequest<ResponseBody: Decodable>(
        base: URL,
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        do {
            return try await sendRequest(base: base, queryItems: queryItems)
        } catch NetworkError.authenticationFailed {
            guard let connectionId else { throw NetworkError.authenticationFailed }
            accessToken = try await OAuthCoordinator.shared.validAccessToken(
                for: type,
                connectionId: connectionId,
                forceRefresh: false
            )
            return try await sendRequest(base: base, queryItems: queryItems)
        }
    }

    private func sendRequest<ResponseBody: Decodable>(
        base: URL,
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        guard let accessToken else { throw NetworkError.notConnected }

        var items = queryItems
        items.append(URLQueryItem(name: "access_token", value: accessToken))

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(Self.requiredUserAgent, forHTTPHeaderField: "User-Agent")
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

        if httpResponse.statusCode == 401 {
            throw NetworkError.authenticationFailed
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("百度网盘 HTTP \(httpResponse.statusCode): \(message)")
        }

        let envelope = try JSONDecoder.baidu.decode(BaiduAPIEnvelope.self, from: data)
        if let errno = envelope.errno, errno != 0 {
            if Self.isAuthError(errno) {
                throw NetworkError.authenticationFailed
            }
            let message = envelope.errmsg ?? envelope.showMsg ?? "未知错误"
            throw NetworkError.transferFailed("百度网盘 API \(errno): \(message)")
        }

        do {
            return try JSONDecoder.baidu.decode(ResponseBody.self, from: data)
        } catch {
            throw NetworkError.transferFailed("百度网盘响应解析失败: \(error.localizedDescription)")
        }
    }

    /// 百度 errno -6 表示 access_token 无效或过期。
    private static func isAuthError(_ errno: Int) -> Bool {
        errno == -6
    }

    // MARK: - Path helpers

    public static func directoryPath(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "/" }
        if trimmed.hasPrefix("/file/") { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    public static func fsId(from path: String) throws -> Int64 {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "file", let fsId = Int64(components[1]) else {
            throw NetworkError.invalidURL
        }
        return fsId
    }
}

// MARK: - API models

private struct BaiduAPIEnvelope: Decodable {
    let errno: Int?
    let errmsg: String?
    let showMsg: String?

    enum CodingKeys: String, CodingKey {
        case errno
        case errmsg
        case showMsg = "show_msg"
    }
}

private struct BaiduFileListResponse: Decodable {
    let list: [BaiduFileItem]
}

private struct BaiduFileItem: Decodable {
    let fsId: Int64
    let path: String
    let serverFilename: String
    let size: Int64?
    let isDir: Int
    let serverMtime: Int?

    enum CodingKeys: String, CodingKey {
        case fsId = "fs_id"
        case path
        case serverFilename = "server_filename"
        case size
        case isDir = "isdir"
        case serverMtime = "server_mtime"
    }

    public func remoteFile() -> RemoteFile? {
        let isDirectory = isDir == 1
        let modifiedDate = serverMtime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        if isDirectory {
            return RemoteFile(
                name: serverFilename,
                path: path,
                size: 0,
                isDirectory: true,
                modifiedDate: modifiedDate,
                type: .directory
            )
        }
        return RemoteFile(
            name: serverFilename,
            path: "/file/\(fsId)",
            size: size ?? 0,
            isDirectory: false,
            modifiedDate: modifiedDate,
            type: .from(filename: serverFilename)
        )
    }
}

private struct BaiduFileMetaResponse: Decodable {
    let list: [BaiduFileMetaItem]
}

private struct BaiduFileMetaItem: Decodable {
    let fsId: Int64
    let dlink: String?

    enum CodingKeys: String, CodingKey {
        case fsId = "fs_id"
        case dlink
    }
}

private extension JSONDecoder {
    public static var baidu: JSONDecoder {
        JSONDecoder()
    }
}
