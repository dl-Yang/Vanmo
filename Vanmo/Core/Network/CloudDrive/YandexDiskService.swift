import Foundation

/// Yandex.Disk REST API v1 客户端（https://cloud-api.yandex.net/v1/disk）。
///
/// 与其他网盘不同，Yandex.Disk 原生就以路径（而不是 id）寻址资源，所以这里
/// `RemoteFile.path` 直接就是 Yandex 侧的资源路径（如 `/Movies/foo.mkv`），无需额外编码。
/// 注意鉴权头固定是 `Authorization: OAuth {token}`，不是标准的 `Bearer`。
final class YandexDiskService: RemoteFileService {
    let type: ConnectionType = .yandexDisk
    private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let apiBase = URL(string: "https://cloud-api.yandex.net/v1/disk/resources")!
    private static let pageSize = 200

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
        let resourcePath = path.isEmpty ? "/" : path

        var files: [RemoteFile] = []
        var offset = 0

        while true {
            let response: YandexResourceResponse = try await request(
                queryItems: [
                    URLQueryItem(name: "path", value: resourcePath),
                    URLQueryItem(name: "limit", value: String(Self.pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "sort", value: "name"),
                ]
            )
            guard let embedded = response.embedded else { break }
            files.append(contentsOf: embedded.items.compactMap { $0.remoteFile() })

            offset += embedded.items.count
            if embedded.items.isEmpty || offset >= embedded.total {
                break
            }
        }

        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        let response: YandexDownloadLinkResponse = try await request(
            path: "/download",
            queryItems: [URLQueryItem(name: "path", value: file.path)]
        )
        guard let url = URL(string: response.href) else {
            throw NetworkError.connectionFailed("Yandex.Disk 未返回可用下载直链")
        }
        return url
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
            throw NetworkError.transferFailed("Yandex.Disk 下载失败 (\(httpResponse.statusCode))")
        }
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Requests

    private func request<ResponseBody: Decodable>(
        path: String = "",
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        do {
            return try await performRequest(path: path, queryItems: queryItems)
        } catch NetworkError.authenticationFailed {
            guard let connectionId else { throw NetworkError.authenticationFailed }
            accessToken = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId, forceRefresh: true)
            return try await performRequest(path: path, queryItems: queryItems)
        }
    }

    private func performRequest<ResponseBody: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        guard let accessToken else { throw NetworkError.notConnected }

        let base = path.isEmpty ? Self.apiBase : Self.apiBase.appendingPathComponent(String(path.dropFirst()))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        // Yandex.Disk 要求固定使用 "OAuth" 鉴权方案，不是标准的 "Bearer"。
        request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")
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
                return try JSONDecoder.yandex.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("Yandex.Disk 响应解析失败: \(error.localizedDescription)")
            }
        case 401:
            throw NetworkError.authenticationFailed
        case 429:
            throw NetworkError.transferFailed("Yandex.Disk 请求过于频繁，请稍后重试")
        default:
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("Yandex.Disk API \(httpResponse.statusCode): \(message)")
        }
    }
}

// MARK: - API models

private struct YandexResourceResponse: Decodable {
    let embedded: YandexEmbedded?

    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

private struct YandexEmbedded: Decodable {
    let items: [YandexResourceItem]
    let total: Int
}

private struct YandexResourceItem: Decodable {
    let name: String
    let path: String
    let type: String
    let size: Int64?
    let modified: Date?

    /// Yandex 返回的 path 形如 `disk:/Movies/foo.mkv`，去掉 `disk:` 前缀方便后续 API 调用复用。
    func remoteFile() -> RemoteFile? {
        let isDirectory = type == "dir"
        guard isDirectory || type == "file" else { return nil }
        let normalizedPath = path.hasPrefix("disk:") ? String(path.dropFirst("disk:".count)) : path
        return RemoteFile(
            name: name,
            path: normalizedPath,
            size: size ?? 0,
            isDirectory: isDirectory,
            modifiedDate: modified,
            type: isDirectory ? .directory : .from(filename: name)
        )
    }
}

private struct YandexDownloadLinkResponse: Decodable {
    let href: String
}

private extension JSONDecoder {
    static var yandex: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
