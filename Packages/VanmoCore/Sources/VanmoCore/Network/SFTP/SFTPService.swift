import Foundation

public struct SFTPPlaybackTarget {
    public let config: ConnectionConfig
    public let path: String
}

/// Password-authenticated SFTP service. SSH keys and known-hosts stay out of scope.
public final class SFTPService: RemoteFileService, @unchecked Sendable {
    public let type: ConnectionType = .sftp
    public private(set) var isConnected = false

    private var session: SFTPSession?
    private var config: ConnectionConfig?

    public init() {}

    public func connect(config: ConnectionConfig) async throws {
        let host = Self.strippedHost(config.host)
        guard !host.isEmpty else { throw NetworkError.connectionFailed("缺少主机地址") }
        guard let username = config.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            throw NetworkError.authenticationFailed
        }

        let session = SFTPSession(
            host: host,
            port: config.port,
            username: username,
            password: config.password
        )
        try await session.login()
        self.session = session
        self.config = ConnectionConfig(
            connectionId: config.connectionId,
            type: .sftp,
            host: host,
            port: config.port,
            username: username,
            password: config.password,
            path: config.path
        )
        isConnected = true
        VanmoLogger.network.info("[SFTP] connected to \(host):\(config.port)")
    }

    public func disconnect() async {
        await session?.close()
        session = nil
        config = nil
        isConnected = false
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let session else { throw NetworkError.notConnected }
        return try await session.listDirectory(path: path)
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
        guard isConnected, let session else { throw NetworkError.notConnected }
        return try await session.fileSize(at: path)
    }

    public func readRange(at path: String, offset: UInt64, length: UInt32) async throws -> Data {
        guard isConnected, let session else { throw NetworkError.notConnected }
        return try await session.readRange(path: path, offset: offset, length: length)
    }

    public func downloadResuming(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        guard isConnected, let session else { throw NetworkError.notConnected }
        try await session.downloadResuming(
            path: file.path,
            to: localURL,
            expectedSize: file.size,
            progress: progress
        )
    }

    public static func playbackTarget(from url: URL) -> SFTPPlaybackTarget? {
        guard url.usesSFTPScheme, let host = url.host, !host.isEmpty else { return nil }
        let port = url.port ?? 22
        let filePath = SFTPPath.normalize(url.path)
        let parent = (filePath as NSString).deletingLastPathComponent
        let config = ConnectionConfig(
            type: .sftp,
            host: host,
            port: port,
            username: url.user,
            password: url.password,
            path: parent == "/" ? nil : parent
        )
        return SFTPPlaybackTarget(config: config, path: filePath)
    }

    public static func makeStreamURL(config: ConnectionConfig, filePath: String) throws -> URL {
        let host = strippedHost(config.host)
        let port = config.port > 0 ? config.port : 22
        let portSegment = port == 22 ? "" : ":\(port)"
        var auth = ""
        if let user = config.username, !user.isEmpty {
            let encodedUser = user.percentEncodedSFTPComponent
            if let pass = config.password, !pass.isEmpty {
                auth = "\(encodedUser):\(pass.percentEncodedSFTPComponent)@"
            } else {
                auth = "\(encodedUser)@"
            }
        }
        let encodedPath = SFTPPath.normalize(filePath)
            .split(separator: "/")
            .map { String($0).percentEncodedSFTPPathSegment }
            .joined(separator: "/")
        let pathSegment = encodedPath.isEmpty ? "" : "/\(encodedPath)"
        let urlString = "sftp://\(auth)\(host)\(portSegment)\(pathSegment)"
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        return url
    }

    private static func strippedHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sftp://", "ssh://"] where host.lowercased().hasPrefix(prefix) {
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
    var percentEncodedSFTPComponent: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    var percentEncodedSFTPPathSegment: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
