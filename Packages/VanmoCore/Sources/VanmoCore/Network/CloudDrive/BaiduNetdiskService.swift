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
        var start = 0

        while true {
            let response: BaiduCategoryListResponse = try await requestMultimedia(
                queryItems: [
                    URLQueryItem(name: "method", value: "categorylist"),
                    URLQueryItem(name: "category", value: "1"),
                    URLQueryItem(name: "parent_path", value: dir),
                    URLQueryItem(name: "recursion", value: "0"),
                    URLQueryItem(name: "show_dir", value: "1"),
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(Self.pageSize)),
                    URLQueryItem(name: "order", value: "name"),
                    URLQueryItem(name: "desc", value: "0"),
                ]
            )
            let items = response.list ?? []
            let hasMore = (response.hasMore ?? 0) == 1
            files.append(contentsOf: items.compactMap { $0.remoteFile(forceVideo: true) })

            guard let next = BaiduCategoryListParser.nextStart(
                currentStart: start,
                cursor: response.cursor,
                returned: items.count,
                hasMore: hasMore
            ) else { break }
            start = next
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

        // 开放平台 dlink 是整文件下载地址（约 8 小时有效，可能 302），不是可 seek 的原片流。
        let separator = dlink.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(dlink)\(separator)access_token=\(accessToken)") else {
            throw NetworkError.invalidURL
        }
        return url
    }

    /// 官方封面：`filemetas` 带 `thumb=1` 后取 `thumbs.url3/url2/url1/icon`。
    public func officialThumbnailJPEG(forFilePath path: String) async throws -> Data? {
        let fsId = try Self.fsId(from: path)
        let meta: BaiduFileMetaResponse = try await requestMultimedia(
            queryItems: [
                URLQueryItem(name: "method", value: "filemetas"),
                URLQueryItem(name: "fsids", value: "[\(fsId)]"),
                URLQueryItem(name: "thumb", value: "1"),
            ]
        )
        guard let url = meta.list.first?.preferredThumbnailURL else {
            LibraryScanDebugLog.thumbnail("baiduThumbs file=\(fsId) hasThumb=false")
            return nil
        }
        LibraryScanDebugLog.thumbnail("baiduThumbs file=\(fsId) hasThumb=true")
        return try await downloadImage(url)
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

    private func downloadImage(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.requiredUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw NetworkError.transferFailed("百度网盘封面下载失败")
        }
        return data
    }

    // MARK: - Requests

    private func requestMultimedia<ResponseBody: Decodable>(queryItems: [URLQueryItem]) async throws -> ResponseBody {
        try await performRequest(base: Self.multimediaBase, queryItems: queryItems)
    }

    private func performRequest<ResponseBody: Decodable>(
        base: URL,
        queryItems: [URLQueryItem]
    ) async throws -> ResponseBody {
        var didRefreshAuth = false
        var frequencyAttempt = 0
        while true {
            do {
                return try await sendRequest(base: base, queryItems: queryItems)
            } catch NetworkError.authenticationFailed {
                guard !didRefreshAuth, let connectionId else { throw NetworkError.authenticationFailed }
                didRefreshAuth = true
                accessToken = try await OAuthCoordinator.shared.validAccessToken(
                    for: type,
                    connectionId: connectionId,
                    forceRefresh: false
                )
            } catch {
                guard BaiduFrequencyLimit.isLimit(error), frequencyAttempt < 3 else { throw error }
                frequencyAttempt += 1
                let waitSec = 1 << frequencyAttempt
                #if DEBUG
                VanmoLogger.library.debug("[Debug][Baidu] rate-limited, retry \(frequencyAttempt, privacy: .public) in \(waitSec, privacy: .public)s")
                #endif
                try await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
            }
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
        if BaiduFrequencyLimit.containsLimit(in: data) {
            throw NetworkError.transferFailed("百度网盘 API 31034: hit frequency limit")
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

private struct BaiduCategoryListResponse: Decodable {
    let list: [BaiduFileItem]?
    let hasMore: Int?
    let cursor: Int?

    enum CodingKeys: String, CodingKey {
        case list
        case hasMore = "has_more"
        case cursor
    }
}

private struct BaiduFileItem: Decodable {
    let fsId: Int64
    let path: String
    let serverFilename: String
    let size: Int64?
    let isDir: Int?
    let serverMtime: Int?
    let category: Int?

    enum CodingKeys: String, CodingKey {
        case fsId = "fs_id"
        case path
        case serverFilename = "server_filename"
        case size
        case isDir = "isdir"
        case serverMtime = "server_mtime"
        case category
    }

    var isDirectory: Bool { isDir == 1 }

    func remoteFile(forceVideo: Bool) -> RemoteFile? {
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
            type: forceVideo ? .video : .from(filename: serverFilename)
        )
    }
}

public enum BaiduFrequencyLimit {
    public static let errno = 31034

    public static func containsLimit(in data: Data) -> Bool {
        if let envelope = try? JSONDecoder.baidu.decode(BaiduAPIEnvelope.self, from: data),
           let parsedErrno = envelope.errno {
            return parsedErrno == errno
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("hit frequency limit")
    }

    public static func isLimit(_ error: Error) -> Bool {
        guard let network = error as? NetworkError,
              case .transferFailed(let message) = network else { return false }
        return message.contains("31034") || message.contains("hit frequency limit")
    }
}

public enum BaiduCategoryListParser {
    public static func nextStart(
        currentStart: Int,
        cursor: Int?,
        returned: Int,
        hasMore: Bool
    ) -> Int? {
        guard hasMore else { return nil }
        let next = cursor ?? (currentStart + returned)
        guard next > currentStart else { return nil }
        return next
    }

    public static func page(fromJSON data: Data) throws -> (videos: Int, directories: Int, hasMore: Bool, nextStart: Int?) {
        let response = try JSONDecoder.baidu.decode(BaiduCategoryListResponse.self, from: data)
        let items = response.list ?? []
        let hasMore = (response.hasMore ?? 0) == 1
        return (
            videos: items.filter { !$0.isDirectory }.count,
            directories: items.filter(\.isDirectory).count,
            hasMore: hasMore,
            nextStart: nextStart(
                currentStart: 0,
                cursor: response.cursor,
                returned: items.count,
                hasMore: hasMore
            )
        )
    }
}

private struct BaiduFileMetaResponse: Decodable {
    let list: [BaiduFileMetaItem]
}

private struct BaiduFileMetaItem: Decodable {
    let fsId: Int64
    let dlink: String?
    let thumbs: BaiduThumbs?

    enum CodingKeys: String, CodingKey {
        case fsId = "fs_id"
        case dlink
        case thumbs
    }

    var preferredThumbnailURL: URL? {
        BaiduFileMetaParser.preferredThumbnailURL(
            icon: thumbs?.icon,
            url1: thumbs?.url1,
            url2: thumbs?.url2,
            url3: thumbs?.url3
        )
    }
}

private struct BaiduThumbs: Decodable {
    let icon: String?
    let url1: String?
    let url2: String?
    let url3: String?
}

public enum BaiduFileMetaParser {
    public static func preferredThumbnailURL(
        icon: String?,
        url1: String?,
        url2: String?,
        url3: String?
    ) -> URL? {
        for raw in [url3, url2, url1, icon] {
            guard let raw, !raw.isEmpty, let url = URL(string: raw) else { continue }
            return url
        }
        return nil
    }

    public static func preferredThumbnailURL(fromFilemetasJSON data: Data) throws -> URL? {
        let response = try JSONDecoder.baidu.decode(BaiduFileMetaResponse.self, from: data)
        return response.list.first?.preferredThumbnailURL
    }
}

private extension JSONDecoder {
    public static var baidu: JSONDecoder {
        JSONDecoder()
    }
}
