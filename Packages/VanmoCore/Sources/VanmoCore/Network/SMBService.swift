import Foundation
import SMBClient

/// SMB 2/3 协议实现，基于 kishikawakatsumi/SMBClient。
///
/// 路径模型：对外暴露的 `RemoteFile.path` 为 POSIX 风格 `/{share}/{relative}`，
/// 第一段被解释为 share 名，剩余为 share 内的相对路径。`/` 表示根（列出可读 share）。
/// 若连接配置了默认 share，根浏览直接进入该 share。
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
    private var endpoint: SMBConnectionEndpoint?
    private var connectedShare: String?
    private var sessionIsGuest = false

    public func connect(config: ConnectionConfig) async throws {
        let parsed = SMBConnectionEndpoint.parse(
            host: config.host,
            port: config.port,
            username: config.username,
            path: config.path
        )
        guard !parsed.host.isEmpty else {
            throw NetworkError.connectionFailed("缺少主机地址")
        }

        let password = SMBConnectionEndpoint.emptyToNil(config.password)
        let hosts = await SMBConnectionEndpoint.resolvedConnectionHosts(for: parsed.host)
        let dialectSets: [[Negotiate.Dialects]] = [
            [.smb202, .smb210],
            [.smb202, .smb210, .smb300, .smb302],
            [.smb202, .smb210, .smb300, .smb302, .smb311],
        ]

        debugLog(
            "connect host=\(parsed.host) port=\(parsed.port) share=\(parsed.share ?? "-") user=\(parsed.username ?? "guest") domain=\(parsed.domain ?? "-") hosts=\(hosts.joined(separator: ","))"
        )

        var lastError: Error = NetworkError.connectionFailed("SMB 登录失败")
        var sawGuestSession = false
        for host in hosts {
            let endpoint = parsed.replacingHost(host)
            for dialects in dialectSets {
                connectedShare = nil
                sessionIsGuest = false
                let smb = makeClient(endpoint: endpoint)
                do {
                    try await login(on: smb, endpoint: endpoint, password: password, dialects: dialects)
                    if sessionIsGuest { sawGuestSession = true }
                    if let share = endpoint.share, !share.isEmpty {
                        let readable = await isShareReadable(share, on: smb)
                        if !readable {
                            debugLog("login ok but share \(share) unreadable; trying next dialect/host")
                            _ = try? await smb.logoff()
                            lastError = guestOrShareError(share: share, sawGuest: sessionIsGuest)
                            continue
                        }
                    }
                    self.client = smb
                    self.config = config
                    self.endpoint = endpoint
                    self.isConnected = true
                    VanmoLogger.network.info("SMB connected to \(endpoint.host):\(endpoint.port) as \(endpoint.username ?? "anonymous")")
                    return
                } catch {
                    lastError = error
                    debugLog("login attempt failed host=\(host) dialects=\(dialectLabel(dialects)) status=\(error.localizedDescription)")
                    _ = try? await smb.logoff()
                }
            }
        }

        if sawGuestSession, parsed.share != nil {
            throw guestOrShareError(share: parsed.share ?? "", sawGuest: true)
        }
        throw mapError(lastError, fallback: "SMB 登录失败")
    }

    public func disconnect() async {
        if let client {
            if connectedShare != nil {
                _ = try? await client.disconnectShare()
            }
            _ = try? await client.logoff()
        }
        client = nil
        config = nil
        endpoint = nil
        connectedShare = nil
        sessionIsGuest = false
        isConnected = false
        VanmoLogger.network.info("SMB disconnected")
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let client else { throw NetworkError.notConnected }

        var normalized = path.isEmpty ? "/" : path
        if normalized == "/", let browse = endpoint?.rootBrowsePath, browse != "/" {
            debugLog("root redirected to \(browse)")
            normalized = browse
        }

        if normalized == "/" {
            return try await listShareEntries(client)
        }

        let (shareName, subpath) = SMBConnectionEndpoint.splitSharePath(normalized)
        guard !shareName.isEmpty else {
            throw NetworkError.invalidURL
        }

        do {
            try await ensureConnected(to: shareName, on: client)
            let files = try await client.listDirectory(path: subpath)
            debugLog("list path=\(normalized) count=\(files.count)")
            return files.compactMap { entry in remoteFile(from: entry, shareName: shareName, subpath: subpath) }
        } catch {
            if SMBShareListingPolicy.isUnreadable(error) {
                debugLog("unreadable path=\(normalized) status=\(error.localizedDescription)")
                return []
            }
            debugLog("list failed path=\(normalized) status=\(error.localizedDescription)")
            throw mapError(error, fallback: "列目录失败 (\(normalized))")
        }
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard isConnected, let config, let endpoint else { throw NetworkError.notConnected }

        let host = endpoint.host
        let port = endpoint.port
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

        let (shareName, subpath) = SMBConnectionEndpoint.splitSharePath(file.path)
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

    public func fileSize(at path: String) async throws -> Int64 {
        guard isConnected, let client else { throw NetworkError.notConnected }
        let (shareName, subpath) = SMBConnectionEndpoint.splitSharePath(path)
        guard !shareName.isEmpty else { throw NetworkError.invalidURL }
        try await ensureConnected(to: shareName, on: client)
        let stat = try await client.fileStat(path: subpath)
        return Int64(stat.size)
    }

    public func readRange(at path: String, offset: UInt64, length: UInt32) async throws -> Data {
        guard isConnected, let client else { throw NetworkError.notConnected }
        let (shareName, subpath) = SMBConnectionEndpoint.splitSharePath(path)
        guard !shareName.isEmpty else { throw NetworkError.invalidURL }
        try await ensureConnected(to: shareName, on: client)
        let reader = client.fileReader(path: subpath)
        let data = try await reader.read(offset: offset, length: length)
        try? await reader.close()
        return data
    }

    /// 从本地部分文件的实际长度继续读取 SMB 文件，供用户下载队列跨启动恢复。
    public func downloadResuming(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        guard isConnected, let client else { throw NetworkError.notConnected }
        let (shareName, subpath) = SMBConnectionEndpoint.splitSharePath(file.path)
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

    private func makeClient(endpoint: SMBConnectionEndpoint) -> SMBClient {
        endpoint.port > 0 && endpoint.port != 445
            ? SMBClient(host: endpoint.host, port: endpoint.port)
            : SMBClient(host: endpoint.host)
    }

    private func login(
        on smb: SMBClient,
        endpoint: SMBConnectionEndpoint,
        password: String?,
        dialects: [Negotiate.Dialects]
    ) async throws {
        let negotiate = try await smb.session.negotiate(
            securityMode: [.signingRequired],
            dialects: dialects
        )
        let serverSigningRequired = negotiate.securityMode.contains(.signingRequired)
        let serverSigningEnabled = negotiate.securityMode.contains(.signingEnabled)
        let clientWillSign = serverSigningRequired || serverSigningEnabled
        let dialectIs311 = negotiate.dialectRevision == Negotiate.Dialects.smb311.rawValue
        let cipher = negotiate.selectedCipher.map { String(format: "0x%04x", $0) } ?? "-"
        debugLog(
            "negotiate ok host=\(endpoint.host) dialect=0x\(String(negotiate.dialectRevision, radix: 16)) cipher=\(cipher) serverSigningEnabled=\(serverSigningEnabled) serverSigningRequired=\(serverSigningRequired) clientWillSign=\(clientWillSign) caps=0x\(String(negotiate.capabilities.rawValue, radix: 16))"
        )

        let setup = try await smb.session.sessionSetup(
            username: endpoint.username,
            password: password,
            domain: endpoint.domain,
            requireSigning: true
        )
        let encryptRequired = setup.sessionFlags.contains(.encryptData)
        debugLog(
            "sessionSetup ok host=\(endpoint.host) flags=0x\(String(setup.sessionFlags.rawValue, radix: 16)) guest=\(setup.sessionFlags.contains(.guest)) null=\(setup.sessionFlags.contains(.nullSession)) encrypt=\(encryptRequired)"
        )

        if encryptRequired, !dialectIs311 {
            throw NetworkError.connectionFailed("服务器要求 SMB 加密，但协商到的方言不是 3.1.1。当前仅支持 3.1.1 AES-GCM。")
        }
        sessionIsGuest = setup.sessionFlags.contains(.guest) || setup.sessionFlags.contains(.nullSession)
        if sessionIsGuest {
            debugLog("session is guest/null; Mac 文件共享需为该用户勾选 Windows 文件共享")
        }
    }

    private func guestOrShareError(share: String, sawGuest: Bool) -> NetworkError {
        if sawGuest {
            return .connectionFailed("服务器将登录降为访客，无法打开共享 \(share)。请在 Mac「文件共享 → 选项」中为该用户勾选 Windows 文件共享，保存后重新输入密码。")
        }
        return .connectionFailed("无法连接到共享 \(share)")
    }

    private func dialectLabel(_ dialects: [Negotiate.Dialects]) -> String {
        dialects.map { String(format: "0x%03x", $0.rawValue) }.joined(separator: ",")
    }

    private func ensureConnected(to share: String, on client: SMBClient) async throws {
        if connectedShare == share { return }

        if connectedShare != nil {
            _ = try? await client.disconnectShare()
            connectedShare = nil
        }

        do {
            try await client.connectShare(share)
            connectedShare = share
            debugLog("tree connect share=\(share)")
        } catch {
            debugLog("tree connect failed share=\(share) status=\(error.localizedDescription)")
            throw mapError(error, fallback: "无法连接到共享 \(share)")
        }
    }

    private func listShareEntries(_ client: SMBClient) async throws -> [RemoteFile] {
        let shares: [Share]
        do {
            shares = try await client.listShares()
            debugLog("listShares count=\(shares.count)")
        } catch {
            debugLog("listShares failed status=\(error.localizedDescription)")
            if let share = endpoint?.share, !share.isEmpty {
                if await isShareReadable(share, on: client) {
                    return [makeShareFile(name: share)]
                }
                return []
            }

            let fallbacks = SMBShareListingPolicy.fallbackShareNames(username: endpoint?.username)
            debugLog("listShares fallback candidates=\(fallbacks.joined(separator: ","))")
            var readable: [RemoteFile] = []
            for name in fallbacks where await isShareReadable(name, on: client) {
                readable.append(makeShareFile(name: name))
            }
            if !readable.isEmpty {
                debugLog("listShares fallback visible=\(readable.map(\.name).joined(separator: ","))")
                return readable
            }
            throw NetworkError.sharePathRequired
        }

        var readable: [RemoteFile] = []
        for share in shares {
            if SMBShareListingPolicy.isHiddenSystemShare(
                name: share.name,
                isIPC: share.type.contains(.ipc)
            ) {
                continue
            }
            if await isShareReadable(share.name, on: client) {
                readable.append(makeShareFile(name: share.name))
            } else {
                debugLog("hide unreadable share=\(share.name)")
            }
        }
        return readable
    }

    private func isShareReadable(_ share: String, on client: SMBClient) async -> Bool {
        do {
            try await ensureConnected(to: share, on: client)
            _ = try await client.listDirectory(path: "")
            return true
        } catch {
            debugLog("share unreadable name=\(share) status=\(error.localizedDescription)")
            if connectedShare == share {
                _ = try? await client.disconnectShare()
                connectedShare = nil
            }
            return false
        }
    }

    private func makeShareFile(name: String) -> RemoteFile {
        RemoteFile(
            name: name,
            path: "/\(name)",
            size: 0,
            isDirectory: true,
            modifiedDate: nil,
            type: .directory
        )
    }

    private func remoteFile(from entry: File, shareName: String, subpath: String) -> RemoteFile? {
        let name = entry.name
        if SMBShareListingPolicy.isHiddenSystemShare(name: name, isIPC: false) { return nil }
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

    private func mapError(_ error: Error, fallback: String) -> NetworkError {
        if let networkError = error as? NetworkError { return networkError }

        let description = error.localizedDescription.lowercased()
        if description.contains("logon") ||
            description.contains("auth") ||
            description.contains("password") ||
            description.contains("status_logon_failure") {
            return .authenticationFailed
        }
        if description.contains("timed out") || description.contains("timeout") {
            return .timeout
        }
        return .connectionFailed("\(fallback): \(error.localizedDescription)")
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[Debug][SMB] \(message)")
        #endif
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
