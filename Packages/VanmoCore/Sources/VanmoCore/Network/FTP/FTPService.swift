import Foundation

public struct FTPPlaybackTarget {
    public let config: ConnectionConfig
    public let path: String
}

/// Real RFC 959 FTP service. SFTP stays on `SFTPPlaceholderService`.
public final class FTPService: RemoteFileService, @unchecked Sendable {
    public let type: ConnectionType = .ftp
    public private(set) var isConnected = false

    private var client: FTPClient?
    private var config: ConnectionConfig?

    public init() {}

    public func connect(config: ConnectionConfig) async throws {
        let host = Self.strippedHost(config.host)
        guard !host.isEmpty else { throw NetworkError.connectionFailed("缺少主机地址") }

        let client = FTPClient(
            host: host,
            port: config.port,
            username: config.username,
            password: config.password
        )
        try await client.login()
        self.client = client
        self.config = ConnectionConfig(
            connectionId: config.connectionId,
            type: .ftp,
            host: host,
            port: config.port,
            username: config.username,
            password: config.password,
            path: config.path
        )
        isConnected = true
        VanmoLogger.network.info("[FTP] connected to \(host):\(config.port)")
    }

    public func disconnect() async {
        await client?.quit()
        client = nil
        config = nil
        isConnected = false
        VanmoLogger.network.info("[FTP] disconnected")
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let client else { throw NetworkError.notConnected }
        let normalized = FTPListingParser.normalizePath(path)
        return try await client.listDirectory(path: normalized)
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard isConnected, let config else { throw NetworkError.notConnected }
        return try Self.makeStreamURL(config: config, filePath: file.path)
    }

    public func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        try await downloadResuming(file: file, to: localURL) { received, total in
            guard total > 0 else { return }
            progress(min(max(Double(received) / Double(total), 0), 1))
        }
    }

    public func fileSize(at path: String) async throws -> Int64 {
        guard isConnected, let client else { throw NetworkError.notConnected }
        return try await client.fileSize(at: path)
    }

    public func readRange(at path: String, offset: UInt64, length: UInt32) async throws -> Data {
        guard isConnected, let client else { throw NetworkError.notConnected }
        return try await client.readRange(path: path, offset: offset, length: length)
    }

    public func downloadResuming(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        guard isConnected, let client else { throw NetworkError.notConnected }
        try await client.downloadResuming(
            path: file.path,
            to: localURL,
            expectedSize: file.size,
            progress: progress
        )
    }

    public static func playbackTarget(from url: URL) -> FTPPlaybackTarget? {
        guard url.usesFTPScheme, let host = url.host, !host.isEmpty else { return nil }
        let port = url.port ?? 21
        let filePath = FTPListingParser.normalizePath(url.path)
        let parent = (filePath as NSString).deletingLastPathComponent
        let config = ConnectionConfig(
            type: .ftp,
            host: host,
            port: port,
            username: url.user,
            password: url.password,
            path: parent == "/" ? nil : parent
        )
        return FTPPlaybackTarget(config: config, path: filePath)
    }

    public static func makeStreamURL(config: ConnectionConfig, filePath: String) throws -> URL {
        let host = strippedHost(config.host)
        let port = config.port > 0 ? config.port : 21
        let portSegment = port == 21 ? "" : ":\(port)"
        var auth = ""
        if let user = config.username, !user.isEmpty {
            let encodedUser = user.percentEncodedFTPComponent
            if let pass = config.password, !pass.isEmpty {
                auth = "\(encodedUser):\(pass.percentEncodedFTPComponent)@"
            } else {
                auth = "\(encodedUser)@"
            }
        }
        let encodedPath = FTPListingParser.normalizePath(filePath)
            .split(separator: "/")
            .map { String($0).percentEncodedFTPPathSegment }
            .joined(separator: "/")
        let pathSegment = encodedPath.isEmpty ? "" : "/\(encodedPath)"
        let urlString = "ftp://\(auth)\(host)\(portSegment)\(pathSegment)"
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        return url
    }

    private static func strippedHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["ftp://", "ftps://"] where host.lowercased().hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if host.contains(":"), let colon = host.lastIndex(of: ":"),
           host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        return host
    }
}

private extension String {
    var percentEncodedFTPComponent: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    var percentEncodedFTPPathSegment: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
