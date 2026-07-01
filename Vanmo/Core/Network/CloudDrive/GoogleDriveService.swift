import Foundation

/// Google Drive API v3 客户端。
///
/// 路径模型：`RemoteFile.path` 编码为 `/item/{fileId}`；根目录用 Drive API 的
/// `root` 别名表示，对应 `RemoteFile.path == "/"`。
final class GoogleDriveService: RemoteFileService {
    let type: ConnectionType = .googleDrive
    private(set) var isConnected = false

    private let session: URLSession
    private var connectionId: UUID?
    private var accessToken: String?

    private static let apiBase = URL(string: "https://www.googleapis.com/drive/v3")!
    private static let fields = "id,name,mimeType,size,modifiedTime"

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
        let folderId = Self.fileId(from: path)

        var files: [RemoteFile] = []
        var pageToken: String?

        repeat {
            let response: GoogleDriveFileListResponse = try await request(
                path: "/files",
                queryItems: [
                    URLQueryItem(name: "q", value: "'\(folderId)' in parents and trashed = false"),
                    URLQueryItem(name: "fields", value: "nextPageToken, files(\(Self.fields))"),
                    URLQueryItem(name: "pageSize", value: "1000"),
                    URLQueryItem(name: "supportsAllDrives", value: "true"),
                    URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
                    URLQueryItem(name: "spaces", value: "drive"),
                    URLQueryItem(name: "orderBy", value: "folder,name"),
                ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            )
            files.append(contentsOf: response.files.compactMap { $0.remoteFile() })
            pageToken = response.nextPageToken
        } while pageToken != nil

        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        let fileId = Self.fileId(from: file.path)
        var components = URLComponents(url: Self.apiBase.appendingPathComponent("files/\(fileId)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "media"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ]
        guard let url = components?.url else { throw NetworkError.invalidURL }
        return url
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected, let connectionId else { throw NetworkError.notConnected }
        let url = try await streamURL(for: file)

        func makeRequest(token: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            return request
        }

        guard var token = accessToken else { throw NetworkError.authenticationFailed }

        var (tempURL, response) = try await session.download(for: makeRequest(token: token))
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            token = try await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId, forceRefresh: true)
            accessToken = token
            (tempURL, response) = try await session.download(for: makeRequest(token: token))
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.transferFailed("Google Drive 下载失败 (\(httpResponse.statusCode))")
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Requests

    private func request<ResponseBody: Decodable>(
        path: String,
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

        var components = URLComponents(url: Self.apiBase.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw NetworkError.invalidURL }

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
                return try JSONDecoder.googleDrive.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("Google Drive 响应解析失败: \(error.localizedDescription)")
            }
        case 401:
            throw NetworkError.authenticationFailed
        case 403:
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("Google Drive 权限不足或超出配额: \(message)")
        case 429:
            throw NetworkError.transferFailed("Google Drive 请求过于频繁，请稍后重试")
        default:
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("Google Drive API \(httpResponse.statusCode): \(message)")
        }
    }

    // MARK: - Path <-> file id

    private static func fileId(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/", !trimmed.isEmpty else { return "root" }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2, components[0] == "item" else { return "root" }
        return String(components[1])
    }
}

// MARK: - API models

private struct GoogleDriveFileListResponse: Decodable {
    let nextPageToken: String?
    let files: [GoogleDriveFileItem]
}

private struct GoogleDriveFileItem: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: Date?

    private static let folderMimeType = "application/vnd.google-apps.folder"
    private static let googleAppsPrefix = "application/vnd.google-apps."

    /// Google Docs/Sheets/Slides 等原生文档没有可下载的媒体字节，播放器场景直接过滤掉。
    func remoteFile() -> RemoteFile? {
        let isDirectory = mimeType == Self.folderMimeType
        if !isDirectory, mimeType.hasPrefix(Self.googleAppsPrefix) {
            return nil
        }
        return RemoteFile(
            name: name,
            path: "/item/\(id)",
            size: size.flatMap(Int64.init) ?? 0,
            isDirectory: isDirectory,
            modifiedDate: modifiedTime,
            type: isDirectory ? .directory : .from(filename: name)
        )
    }
}

private extension JSONDecoder {
    static var googleDrive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
