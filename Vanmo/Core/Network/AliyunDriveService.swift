import Foundation

enum AliyunDriveEndpoint {
    static func baseURL(from host: String) throws -> URL {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            guard url.scheme?.lowercased() == "https" else {
                throw NetworkError.connectionFailed("阿里云盘官方 API 必须使用 HTTPS")
            }
            guard let host = url.host?.lowercased(), isAllowedPDSHost(host) else {
                throw NetworkError.connectionFailed("阿里云盘 API 域名需为 {domainId}.api.aliyunpds.com")
            }
            if let port = url.port, port != 443 {
                throw NetworkError.connectionFailed("阿里云盘官方 API 仅支持 HTTPS 默认端口")
            }
            return URL(string: "https://\(host)")!
        }

        let host: String
        if trimmed.contains(".") {
            host = trimmed.lowercased()
        } else {
            host = "\(trimmed.lowercased()).api.aliyunpds.com"
        }
        guard isAllowedPDSHost(host) else {
            throw NetworkError.connectionFailed("阿里云盘 API 域名需为 {domainId}.api.aliyunpds.com")
        }
        return URL(string: "https://\(host)")!
    }

    static func apiURL(from host: String, path: String) throws -> URL {
        let base = try baseURL(from: host)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = path.hasPrefix("/") ? path : "/" + path
        return components?.url ?? base
    }

    private static func isAllowedPDSHost(_ host: String) -> Bool {
        host.hasSuffix(".api.aliyunpds.com") && host.split(separator: ".").count >= 4
    }
}

enum AliyunDriveTokenClient {
    static func requestToken(host: String, formItems: [URLQueryItem], session: URLSession = .shared) async throws -> AliyunDriveTokenResponse {
        let url = try AliyunDriveEndpoint.apiURL(from: host, path: "/v2/oauth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formItems.formURLEncodedData
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.authenticationFailed
        }

        do {
            return try JSONDecoder.aliyunDrive.decode(AliyunDriveTokenResponse.self, from: data)
        } catch {
            throw NetworkError.transferFailed("阿里云盘 token 响应解析失败: \(error.localizedDescription)")
        }
    }
}

final class AliyunDriveService: RemoteFileService {
    let type: ConnectionType = .aliyunDrive
    private(set) var isConnected = false

    private let session: URLSession
    private var config: ConnectionConfig?
    private var credential: OAuthCredential?
    private var baseURL: URL?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(config: ConnectionConfig) async throws {
        guard let connectionId = config.connectionId else {
            throw NetworkError.authenticationFailed
        }
        guard var credential = try OAuthCredentialStore.load(connectionId: connectionId) else {
            throw NetworkError.authenticationFailed
        }

        self.config = config
        self.baseURL = try AliyunDriveEndpoint.baseURL(from: config.host)

        if credential.isExpired {
            credential = try await refreshCredential(credential, connectionId: connectionId)
        }

        self.credential = credential
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
        config = nil
        credential = nil
        baseURL = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        let target = try fileReference(from: path)
        var marker: String?
        var files: [RemoteFile] = []

        repeat {
            let body = AliyunDriveListRequest(
                driveId: target.driveID,
                parentFileId: target.fileID,
                marker: marker,
                limit: 100
            )
            let response: AliyunDriveListResponse = try await request(
                path: "/v2/file/list",
                body: body
            )
            files.append(contentsOf: response.items.map { $0.remoteFile(driveID: target.driveID) })
            marker = response.nextMarker?.isEmpty == false ? response.nextMarker : nil
        } while marker != nil

        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard isConnected else { throw NetworkError.notConnected }
        let target = try fileReference(from: file.path)
        let body = AliyunDriveDownloadURLRequest(
            driveId: target.driveID,
            fileId: target.fileID,
            fileName: file.name,
            expireSec: 7200
        )
        let response: AliyunDriveDownloadURLResponse = try await request(
            path: "/v2/file/get_download_url",
            body: body
        )
        guard let url = URL(string: response.url), !response.url.isEmpty else {
            throw NetworkError.invalidURL
        }
        return url
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        let url = try await streamURL(for: file)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.transferFailed("HTTP \(httpResponse.statusCode)")
        }
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    private func request<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        do {
            return try await performRequest(path: path, body: body)
        } catch NetworkError.authenticationFailed {
            guard let config, let connectionId = config.connectionId, let credential else {
                throw NetworkError.authenticationFailed
            }
            self.credential = try await refreshCredential(credential, connectionId: connectionId)
            return try await performRequest(path: path, body: body)
        }
    }

    private func performRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        guard let baseURL, let credential else { throw NetworkError.notConnected }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path.hasPrefix("/") ? path : "/" + path
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Vanmo/AliyunDrive", forHTTPHeaderField: "User-Agent")
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.aliyunDrive.encode(body)
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
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
                return try JSONDecoder.aliyunDrive.decode(ResponseBody.self, from: data)
            } catch {
                throw NetworkError.transferFailed("阿里云盘响应解析失败: \(error.localizedDescription)")
            }
        case 401, 403:
            throw NetworkError.authenticationFailed
        case 429:
            throw NetworkError.transferFailed("阿里云盘请求过于频繁，请稍后重试")
        default:
            let message = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.transferFailed("阿里云盘 API \(httpResponse.statusCode): \(message)")
        }
    }

    private func refreshCredential(_ credential: OAuthCredential, connectionId: UUID) async throws -> OAuthCredential {
        guard let config else { throw NetworkError.notConnected }
        guard OAuthProviderConfiguration.isConfigured(for: .aliyunDrive) else {
            throw NetworkError.connectionFailed("阿里云盘 OAuth 尚未配置 client id")
        }

        var items = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credential.refreshToken),
            URLQueryItem(name: "client_id", value: OAuthProviderConfiguration.clientID(for: .aliyunDrive)),
        ]
        if let secret = OAuthProviderConfiguration.clientSecret(for: .aliyunDrive), !secret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: secret))
        }

        let token = try await AliyunDriveTokenClient.requestToken(host: config.host, formItems: items, session: session)
        let refreshed = token.makeCredential(provider: .aliyunDrive)
        try OAuthCredentialStore.save(refreshed, connectionId: connectionId)
        return refreshed
    }

    private func fileReference(from path: String) throws -> AliyunDriveFileReference {
        if path.isEmpty || path == "/" {
            guard let driveID = credential?.defaultDriveID else {
                throw NetworkError.connectionFailed("阿里云盘 token 未返回 default_drive_id，无法定位根目录")
            }
            return AliyunDriveFileReference(driveID: driveID, fileID: "root")
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count == 4,
              components[0] == "drive",
              components[2] == "file" else {
            throw NetworkError.invalidURL
        }
        return AliyunDriveFileReference(driveID: components[1], fileID: components[3])
    }
}

private struct AliyunDriveFileReference {
    let driveID: String
    let fileID: String
}

struct AliyunDriveTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let tokenType: String?
    let scope: String?
    let userId: String?
    let defaultDriveId: String?
    let domainId: String?

    func makeCredential(provider: ConnectionType) -> OAuthCredential {
        OAuthCredential(
            provider: provider,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            tokenType: tokenType ?? "Bearer",
            scope: scope,
            userID: userId,
            defaultDriveID: defaultDriveId,
            domainID: domainId
        )
    }
}

private struct AliyunDriveListRequest: Encodable {
    let driveId: String
    let parentFileId: String
    let marker: String?
    let limit: Int
}

private struct AliyunDriveListResponse: Decodable {
    let items: [AliyunDriveFileItem]
    let nextMarker: String?
}

private struct AliyunDriveFileItem: Decodable {
    let fileId: String
    let name: String
    let type: String
    let size: Int64?
    let updatedAt: Date?

    func remoteFile(driveID: String) -> RemoteFile {
        let isDirectory = type == "folder"
        return RemoteFile(
            name: name,
            path: "/drive/\(driveID)/file/\(fileId)",
            size: size ?? 0,
            isDirectory: isDirectory,
            modifiedDate: updatedAt,
            type: isDirectory ? .directory : .from(filename: name)
        )
    }
}

private struct AliyunDriveDownloadURLRequest: Encodable {
    let driveId: String
    let fileId: String
    let fileName: String
    let expireSec: Int
}

private struct AliyunDriveDownloadURLResponse: Decodable {
    let url: String
}

private extension JSONEncoder {
    static var aliyunDrive: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension JSONDecoder {
    static var aliyunDrive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Array where Element == URLQueryItem {
    var formURLEncodedData: Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
