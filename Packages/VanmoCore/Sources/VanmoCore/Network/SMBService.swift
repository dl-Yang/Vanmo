import Foundation
import SMBClient

/// SMB 2.0 协议实现，基于 kishikawakatsumi/SMBClient。
///
/// 路径模型：对外暴露的 `RemoteFile.path` 为 POSIX 风格 `/{share}/{relative}`，
/// 第一段被解释为 share 名，剩余为 share 内的相对路径。`/` 表示根（列出所有 share）。
///
/// 流播放：`streamURL(for:)` 返回带凭据的 `smb://user:pass@host:port/share/path`，
/// 由 KSPlayer 内嵌的 libsmbclient 直接消费。该 URL 会被持久化到
/// `MediaItem.fileURL`，需注意 SwiftData 数据库中会包含密码（已知 trade-off，
/// 后续可由 PrefetchProxy 代理为本地 HTTP 来消除）。
public final class SMBService: RemoteFileService {
    public let type: ConnectionType = .smb
    public private(set) var isConnected = false

    private var client: SMBClient?
    private var config: ConnectionConfig?
    private var connectedShare: String?

    public func connect(config: ConnectionConfig) async throws {
        guard !config.host.isEmpty else {
            throw NetworkError.connectionFailed("缺少主机地址")
        }

        let smb = config.port > 0 && config.port != 445
            ? SMBClient(host: config.host, port: config.port)
            : SMBClient(host: config.host)

        do {
            try await smb.login(
                username: config.username,
                password: config.password
            )
        } catch {
            throw mapError(error, fallback: "SMB 登录失败")
        }

        self.client = smb
        self.config = config
        self.connectedShare = nil
        self.isConnected = true
        VanmoLogger.network.info("SMB connected to \(config.host):\(config.port) as \(config.username ?? "anonymous")")
    }

    public func disconnect() async {
        if let client {
            if connectedShare != nil {
                try? await client.disconnectShare()
            }
            try? await client.logoff()
        }
        client = nil
        config = nil
        connectedShare = nil
        isConnected = false
        VanmoLogger.network.info("SMB disconnected")
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let client else { throw NetworkError.notConnected }

        let normalized = path.isEmpty ? "/" : path

        if normalized == "/" {
            return try await listShareEntries(client)
        }

        let (shareName, subpath) = splitSharePath(normalized)
        guard !shareName.isEmpty else {
            throw NetworkError.invalidURL
        }

        try await ensureConnected(to: shareName, on: client)

        let files: [File]
        do {
            files = try await client.listDirectory(path: subpath)
        } catch {
            throw mapError(error, fallback: "列目录失败 (\(normalized))")
        }

        return files.compactMap { entry -> RemoteFile? in
            let name = entry.name
            if name == "." || name == ".." { return nil }
            if entry.isHidden || entry.isSystem { return nil }

            let entryPath: String
            if subpath.isEmpty {
                entryPath = "/\(shareName)/\(name)"
            } else {
                entryPath = "/\(shareName)/\(subpath)/\(name)"
            }

            let fileType: RemoteFileType = entry.isDirectory
                ? .directory
                : .from(filename: name)

            return RemoteFile(
                name: name,
                path: entryPath,
                size: Int64(entry.size),
                isDirectory: entry.isDirectory,
                modifiedDate: entry.lastWriteTime,
                type: fileType
            )
        }
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard isConnected, let config else { throw NetworkError.notConnected }

        let host = config.host
        let port = config.port
        let portSegment = (port > 0 && port != 445) ? ":\(port)" : ""

        let auth: String
        if let user = config.username, !user.isEmpty {
            let encodedUser = user.percentEncodedSMBComponent
            if let pass = config.password, !pass.isEmpty {
                auth = "\(encodedUser):\(pass.percentEncodedSMBComponent)@"
            } else {
                auth = "\(encodedUser)@"
            }
        } else {
            auth = ""
        }

        let encodedPath = file.path
            .split(separator: "/")
            .map { String($0).percentEncodedSMBPathSegment }
            .joined(separator: "/")
        let pathSegment = encodedPath.isEmpty ? "" : "/\(encodedPath)"

        let urlString = "smb://\(auth)\(host)\(portSegment)\(pathSegment)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        return url
    }

    public func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected, let client else { throw NetworkError.notConnected }

        let (shareName, subpath) = splitSharePath(file.path)
        guard !shareName.isEmpty else { throw NetworkError.invalidURL }

        try await ensureConnected(to: shareName, on: client)

        do {
            try await client.download(
                path: subpath,
                localPath: localURL,
                overwrite: true,
                progressHandler: { p in progress(p) }
            )
        } catch {
            throw mapError(error, fallback: "下载失败")
        }
    }

    /// 从本地部分文件的实际长度继续读取 SMB 文件，供用户下载队列跨启动恢复。
    public func downloadResuming(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        guard isConnected, let client else { throw NetworkError.notConnected }
        let (shareName, subpath) = splitSharePath(file.path)
        guard !shareName.isEmpty else { throw NetworkError.invalidURL }
        try await ensureConnected(to: shareName, on: client)

        if !FileManager.default.fileExists(atPath: localURL.path) {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        var offset = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let expectedSize = file.size > 0 ? UInt64(file.size) : UInt64.max
        if offset > expectedSize {
            let handle = try FileHandle(forWritingTo: localURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
            offset = 0
        }

        let reader = client.fileReader(path: subpath)
        defer { Task { try? await reader.close() } }
        let destination = try FileHandle(forWritingTo: localURL)
        defer { try? destination.close() }
        try destination.seekToEnd()

        let chunkSize: UInt32 = 4 * 1_024 * 1_024
        while offset < expectedSize {
            try Task.checkCancellation()
            let remaining = expectedSize == UInt64.max
                ? UInt64(chunkSize)
                : min(UInt64(chunkSize), expectedSize - offset)
            let data = try await reader.read(offset: offset, length: UInt32(remaining))
            guard !data.isEmpty else { break }
            try destination.write(contentsOf: data)
            offset += UInt64(data.count)
            progress(Int64(offset), file.size)
        }
        try destination.synchronize()

        if file.size > 0, offset < UInt64(file.size) {
            throw NetworkError.transferFailed("SMB 下载提前结束")
        }
    }

    // MARK: - Private

    private func ensureConnected(to share: String, on client: SMBClient) async throws {
        if connectedShare == share { return }

        if connectedShare != nil {
            try? await client.disconnectShare()
        }

        do {
            try await client.connectShare(share)
            connectedShare = share
        } catch {
            throw mapError(error, fallback: "无法连接到共享 \(share)")
        }
    }

    private func listShareEntries(_ client: SMBClient) async throws -> [RemoteFile] {
        let shares: [Share]
        do {
            shares = try await client.listShares()
        } catch {
            throw mapError(error, fallback: "枚举共享失败")
        }

        return shares.compactMap { share -> RemoteFile? in
            guard !share.type.contains(.ipc) else { return nil }
            guard !share.name.hasSuffix("$") else { return nil }

            return RemoteFile(
                name: share.name,
                path: "/\(share.name)",
                size: 0,
                isDirectory: true,
                modifiedDate: nil,
                type: .directory
            )
        }
    }

    /// 把 `/share/a/b/c` 拆成 `("share", "a/b/c")`；`/share` → `("share", "")`。
    private func splitSharePath(_ path: String) -> (share: String, subpath: String) {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return ("", "") }

        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let share = String(parts[0])
        let sub = parts.count > 1 ? String(parts[1]) : ""
        return (share, sub)
    }

    private func mapError(_ error: Error, fallback: String) -> NetworkError {
        if let networkError = error as? NetworkError { return networkError }

        let description = error.localizedDescription.lowercased()
        if description.contains("logon") ||
            description.contains("auth") ||
            description.contains("password") ||
            description.contains("access denied") ||
            description.contains("status_logon_failure") {
            return .authenticationFailed
        }
        if description.contains("timed out") || description.contains("timeout") {
            return .timeout
        }
        return .connectionFailed("\(fallback): \(error.localizedDescription)")
    }
}

// MARK: - Percent encoding helpers

private extension String {
    /// 适用于 smb:// URL 中 user / password 单段的 percent encoding。
    var percentEncodedSMBComponent: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    /// 适用于 smb:// URL 路径单段（保留 `/` 由调用方拼接）。
    var percentEncodedSMBPathSegment: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
