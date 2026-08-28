import Foundation
import Darwin
import Network

/// Normalized SMB login target parsed from the connection form.
///
/// Host may arrive as an IP, hostname, `smb://` URL, or UNC path. A form `path`
/// wins over a share embedded in the host string. Usernames may include
/// `DOMAIN\user` or `user@WORKGROUP`; the latter is treated as a domain only
/// when the right-hand side is not host-like.
public struct SMBConnectionEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let share: String?
    public let initialSubpath: String?
    public let username: String?
    public let domain: String?

    public func replacingHost(_ host: String) -> SMBConnectionEndpoint {
        SMBConnectionEndpoint(
            host: host,
            port: port,
            share: share,
            initialSubpath: initialSubpath,
            username: username,
            domain: domain
        )
    }

    public var rootBrowsePath: String {
        guard let share, !share.isEmpty else { return "/" }
        if let initialSubpath, !initialSubpath.isEmpty {
            return "/\(share)/\(initialSubpath)"
        }
        return "/\(share)"
    }

    public init(
        host: String,
        port: Int,
        share: String? = nil,
        initialSubpath: String? = nil,
        username: String? = nil,
        domain: String? = nil
    ) {
        self.host = host
        self.port = port
        self.share = share
        self.initialSubpath = initialSubpath
        self.username = username
        self.domain = domain
    }

    public static func parse(
        host rawHost: String,
        port rawPort: Int,
        username rawUsername: String?,
        path rawPath: String?
    ) -> SMBConnectionEndpoint {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var port = rawPort > 0 ? rawPort : ConnectionType.smb.defaultPort
        var share: String?
        var subpath: String?
        var account = parseAccount(rawUsername)

        if let smbURL = parseSMBURL(host) {
            host = smbURL.host
            if let urlPort = smbURL.port {
                port = urlPort
            }
            share = smbURL.share
            subpath = smbURL.subpath
            if account.username == nil, let urlUser = smbURL.username {
                account = parseAccount(urlUser)
            }
        } else if let unc = parseUNC(host) {
            host = unc.host
            if let uncPort = unc.port {
                port = uncPort
            }
            share = unc.share
            subpath = unc.subpath
        } else if let slash = firstPathSeparator(in: host) {
            let hostPart = String(host[..<slash])
            let pathPart = String(host[host.index(after: slash)...])
            let parsed = parseHostAndPort(hostPart)
            host = parsed.host
            if let embeddedPort = parsed.port {
                port = embeddedPort
            }
            let split = splitSharePath(pathPart)
            share = emptyToNil(split.share)
            subpath = emptyToNil(split.subpath)
        } else {
            let parsed = parseHostAndPort(host)
            host = parsed.host
            if let embeddedPort = parsed.port {
                port = embeddedPort
            }
        }

        if let formPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !formPath.isEmpty {
            let split = splitSharePath(formPath)
            share = emptyToNil(split.share)
            subpath = emptyToNil(split.subpath)
        }

        return SMBConnectionEndpoint(
            host: host,
            port: port,
            share: share,
            initialSubpath: subpath,
            username: account.username,
            domain: account.domain
        )
    }

    /// Build a login config and POSIX `/{share}/{file}` path from a playback `smb://` URL.
    public static func playbackTarget(from url: URL) -> (config: ConnectionConfig, path: String)? {
        guard url.usesSMBScheme else { return nil }
        let parsed = parse(
            host: url.absoluteString,
            port: url.port ?? ConnectionType.smb.defaultPort,
            username: url.user,
            path: nil
        )
        guard !parsed.host.isEmpty, let share = parsed.share, !share.isEmpty else {
            return nil
        }
        let posixPath = url.path.isEmpty ? "/\(share)" : url.path
        let config = ConnectionConfig(
            type: .smb,
            host: parsed.host,
            port: parsed.port,
            username: parsed.username ?? url.user,
            password: url.password,
            path: "/\(share)"
        )
        return (config, posixPath)
    }

    /// `/share/a/b` → `("share", "a/b")`; `/share` → `("share", "")`.
    public static func splitSharePath(_ path: String) -> (share: String, subpath: String) {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        guard !trimmed.isEmpty else { return ("", "") }
        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let share = String(parts[0])
        let sub = parts.count > 1 ? String(parts[1]) : ""
        return (share, sub)
    }

    public static func parseAccount(_ raw: String?) -> (username: String?, domain: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        if let separator = raw.firstIndex(where: { $0 == "\\" }) {
            let domain = String(raw[..<separator])
            let user = String(raw[raw.index(after: separator)...])
            if !domain.isEmpty, !user.isEmpty, !user.contains("\\") {
                return (user, domain)
            }
        }

        if let at = raw.lastIndex(of: "@") {
            let user = String(raw[..<at])
            let domain = String(raw[raw.index(after: at)...])
            if !user.isEmpty, !domain.isEmpty, !isHostLike(domain) {
                return (user, domain)
            }
        }

        return (raw, nil)
    }

    public static func isIPv4(_ host: String) -> Bool {
        var addr = in_addr()
        return host.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
    }

    /// Hosts to try for tree connect. macOS File Sharing often accepts
    /// `hostname.local` in the UNC path after login by IP still fails.
    public static func connectionHosts(for host: String) -> [String] {
        var hosts = [host]
        if isIPv4(host), let name = reverseLookupIPv4(host), name != host {
            hosts.append(name)
        }
        return hosts
    }

    /// Sync host list plus a short Bonjour `_smb._tcp` match for IPv4.
    public static func resolvedConnectionHosts(for host: String) async -> [String] {
        var hosts = connectionHosts(for: host)
        guard isIPv4(host) else { return hosts }
        if let bonjour = await SMBBonjourHostLookup.hostname(matchingIPv4: host),
           !hosts.contains(bonjour) {
            hosts.append(bonjour)
        }
        return hosts
    }

    /// Bonjour instance names that are already DNS-safe become `name.local`.
    public static func localHostname(fromBonjourService name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        if trimmed.lowercased().hasSuffix(".local") {
            return trimmed
        }
        return "\(trimmed).local"
    }

    public static func reverseLookupIPv4(_ ip: String) -> String? {
        var addr = in_addr()
        guard ip.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }

        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_addr = addr
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &sa) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getnameinfo(
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: hostname)
        return name.isEmpty ? nil : name
    }

    public static func parseHostAndPort(_ raw: String) -> (host: String, port: Int?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), let close = value.firstIndex(of: "]") {
            let host = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            if rest.first == ":", let port = Int(rest.dropFirst()), (1...65535).contains(port) {
                return (host, port)
            }
            return (host, nil)
        }

        if value.filter({ $0 == ":" }).count >= 2 {
            return (value, nil)
        }

        if let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            let portString = String(value[value.index(after: colon)...])
            if let port = Int(portString), (1...65535).contains(port), !host.isEmpty {
                return (host, port)
            }
        }

        return (value, nil)
    }

    public static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isHostLike(_ value: String) -> Bool {
        value.contains(".") || value.contains(":")
    }

    private static func firstPathSeparator(in value: String) -> String.Index? {
        value.firstIndex(where: { $0 == "/" || $0 == "\\" })
    }

    private static func parseSMBURL(_ raw: String) -> (
        host: String,
        port: Int?,
        share: String?,
        subpath: String?,
        username: String?
    )? {
        let lowered = raw.lowercased()
        guard lowered.hasPrefix("smb://") else { return nil }
        let remainder = String(raw.dropFirst(6))
        return parseAuthorityAndPath(remainder)
    }

    private static func parseUNC(_ raw: String) -> (
        host: String,
        port: Int?,
        share: String?,
        subpath: String?
    )? {
        guard raw.hasPrefix("\\\\") || raw.hasPrefix("//") else { return nil }
        let remainder = String(raw.dropFirst(2))
        guard let parsed = parseAuthorityAndPath(remainder) else { return nil }
        return (parsed.host, parsed.port, parsed.share, parsed.subpath)
    }

    private static func parseAuthorityAndPath(_ raw: String) -> (
        host: String,
        port: Int?,
        share: String?,
        subpath: String?,
        username: String?
    )? {
        var remainder = raw
        var username: String?

        if let at = remainder.firstIndex(of: "@"),
           !remainder[..<at].contains("/") {
            username = String(remainder[..<at])
            remainder = String(remainder[remainder.index(after: at)...])
        }

        let slash = firstPathSeparator(in: remainder)
        let authority = slash.map { String(remainder[..<$0]) } ?? remainder
        let path = slash.map { String(remainder[remainder.index(after: $0)...]) } ?? ""
        let hostPort = parseHostAndPort(authority)
        guard !hostPort.host.isEmpty else { return nil }
        let split = splitSharePath(path)
        return (
            hostPort.host,
            hostPort.port,
            emptyToNil(split.share),
            emptyToNil(split.subpath),
            emptyToNil(username)
        )
    }
}

enum SMBShareListingPolicy {
    static func isHiddenSystemShare(name: String, isIPC: Bool) -> Bool {
        if isIPC { return true }
        if name.hasSuffix("$") { return true }
        if name == "." || name == ".." { return true }
        return false
    }

    /// Names to probe when `NetShareEnum` is denied and the form has no share.
    static func fallbackShareNames(username: String?) -> [String] {
        var names: [String] = []
        if let username, !username.isEmpty {
            names.append(username)
        }
        names.append(contentsOf: ["homes", "home", "Public", "media"])
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    static func isUnreadable(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .authenticationFailed:
                return true
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("access denied")
            || description.contains("logon failure")
            || description.contains("status_access_denied")
            || description.contains("status_logon_failure")
            || description.contains("bad network name")
            || description.contains("network name deleted")
            || description.contains("object path not found")
            || description.contains("object name not found")
    }
}

enum SMBBonjourHostLookup {
    static func hostname(matchingIPv4 ip: String, timeout: TimeInterval = 2) async -> String? {
        await withCheckedContinuation { continuation in
            LookupBox(ip: ip, continuation: continuation).start(timeout: timeout)
        }
    }

    private final class LookupBox: @unchecked Sendable {
        private let ip: String
        private let continuation: CheckedContinuation<String?, Never>
        private let lock = NSLock()
        private var finished = false
        private var keepAlive: LookupBox?
        private var browser: NWBrowser?
        private var connections: [NWConnection] = []

        init(ip: String, continuation: CheckedContinuation<String?, Never>) {
            self.ip = ip
            self.continuation = continuation
        }

        func start(timeout: TimeInterval) {
            keepAlive = self
            let browser = NWBrowser(for: .bonjour(type: "_smb._tcp", domain: "local."), using: .tcp)
            self.browser = browser
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.resolve(results)
            }
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.finish(nil)
                }
            }
            browser.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(nil)
            }
        }

        private func resolve(_ results: Set<NWBrowser.Result>) {
            lock.lock()
            let alreadyFinished = finished
            lock.unlock()
            guard !alreadyFinished else { return }

            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint else { continue }
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                lock.lock()
                connections.append(connection)
                lock.unlock()
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if self.matches(connection) {
                            self.finish(SMBConnectionEndpoint.localHostname(fromBonjourService: name))
                        }
                        connection.cancel()
                    case .failed, .cancelled:
                        connection.cancel()
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        }

        private func matches(_ connection: NWConnection) -> Bool {
            guard let endpoint = connection.currentPath?.remoteEndpoint,
                  case .hostPort(let host, _) = endpoint else { return false }
            switch host {
            case .ipv4(let address):
                return IPv4Address(ip).map { $0 == address } ?? false
            case .name(let name, _):
                return name == ip
            default:
                return false
            }
        }

        private func finish(_ hostname: String?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            browser?.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
            keepAlive = nil
            lock.unlock()
            continuation.resume(returning: hostname)
        }
    }
}
