import Foundation

// MARK: - Models

/// 一次 Plex PIN 授权会话。
///
/// `plex.tv` 在 `POST /api/v2/pins` 返回四位授权码与有效期；
/// 用户在 `plex.tv/link` 输入授权码后，轮询接口返回 `authToken`。
public struct PlexPin: Sendable, Equatable {
    public let id: Int
    public let code: String
    public let authURL: URL
    public let expiresAt: Date

    public var isExpired: Bool { Date() >= expiresAt }
}

/// 已授权 Plex 账号的展示信息；账号查询失败不影响登录。
public struct PlexAccount: Sendable, Equatable {
    public let username: String
    public let email: String?
}

/// plex.tv `/api/v2/resources` 返回的单个可达端点。
public struct PlexServerConnection: Codable, Sendable, Equatable, Identifiable {
    public let uri: String
    public let address: String?
    public let port: Int
    public let isLocal: Bool
    public let isRelay: Bool
    public let protocolName: String

    public var id: String { uri }

    enum CodingKeys: String, CodingKey {
        case uri, address, port
        case isLocal = "local"
        case isRelay = "relay"
        case protocolName = "protocol"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 32400
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        isRelay = try container.decodeIfPresent(Bool.self, forKey: .isRelay) ?? false
        protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName) ?? "http"
    }
}

/// plex.tv `/api/v2/resources` 返回的一台 Plex Media Server。
public struct PlexServerResource: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let clientIdentifier: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let isOwned: Bool
    public let accessToken: String?
    public let connections: [PlexServerConnection]

    public var id: String { clientIdentifier }

    enum CodingKeys: String, CodingKey {
        case name, clientIdentifier, product, productVersion, platform, accessToken, connections
        case isOwned = "owned"
    }

    /// 共享服务器的 token：`/api/v2/resources` 可能为不属于当前账号的服务器
    /// 下发 `accessToken`；存在时优先使用它，否则回退到账号 token。
    public func effectiveToken(accountToken: String) -> String {
        accessToken ?? accountToken
    }

    /// 探测顺序：非 relay 优先，其次本地，其次 https，最后 IPv4 地址。
    public var orderedConnections: [PlexServerConnection] {
        connections.enumerated().sorted { lhs, rhs in
            Self.rank(lhs.element, index: lhs.offset) < Self.rank(rhs.element, index: rhs.offset)
        }.map(\.element)
    }

    private static func rank(
        _ connection: PlexServerConnection,
        index: Int
    ) -> (Int, Int, Int, Int, Int) {
        (
            connection.isRelay ? 1 : 0,
            connection.isLocal ? 0 : 1,
            connection.protocolName.caseInsensitiveCompare("https") == .orderedSame ? 0 : 1,
            isIPv4Address(connection.address) ? 0 : 1,
            index
        )
    }

    private static func isIPv4Address(_ address: String?) -> Bool {
        guard let address else { return false }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return true
        }
    }
}

public enum PlexAuthError: Error, LocalizedError, Equatable {
    case requestFailed(String)
    case pinExpired
    case authorizationTimedOut
    case authorizationCancelled
    case noServer
    case serverUnreachable(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        case .pinExpired:
            return L10n.tr("授权代码已过期，请重新获取代码。")
        case .authorizationTimedOut:
            return L10n.tr("等待 Plex 授权超时，请重试。")
        case .authorizationCancelled:
            return L10n.tr("已取消 Plex 授权。")
        case .noServer:
            return L10n.tr("未找到可用的 Plex 媒体服务器。")
        case .serverUnreachable(let name):
            return L10n.tr("无法连接 Plex 服务器 %@。", name)
        }
    }
}

// MARK: - API

/// Plex PIN 授权、服务器发现与端点探测。
///
/// 所有请求都带 `X-Plex-Client-Identifier` / `X-Plex-Product` / `X-Plex-Version`
/// 与 `Accept: application/json`；账号 token 只走 `X-Plex-Token` 请求头，
/// 不进入 URL、日志或错误文本。
///
/// 共享服务器可能在资源里带自己的 `accessToken`，保存连接或探测端点时用
/// `PlexServerResource.effectiveToken(accountToken:)` 取实际 token。
public struct PlexAuthAPI: Sendable {
    public init(
        session: URLSession = .shared,
        clientIdentifier: String = PlexCredentialStore.clientIdentifier
    ) {
        self.init(
            session: session,
            clientIdentifier: clientIdentifier,
            log: { message in
                VanmoLogger.network.info("\(message, privacy: .public)")
            }
        )
    }

    /// 测试注入点：单元测试进程（未签名）无法访问 Keychain 与真实日志系统时使用。
    init(
        session: URLSession,
        clientIdentifier: String,
        log: @escaping @Sendable (String) -> Void
    ) {
        self.session = session
        self.clientIdentifier = clientIdentifier
        self.log = log
    }

    private static let plexTVBaseURL = URL(string: "https://plex.tv")!
    /// `app.plex.tv/auth` 只接受 strong PIN（25 位）；四位代码必须由用户在 plex.tv/link 输入。
    private static let linkPageURL = URL(string: "https://plex.tv/link")!
    private static let clientName = "Vanmo"
    private static let clientVersion = "1.0.0"
    private static let requestTimeout: TimeInterval = 15
    private static let probeTimeout: TimeInterval = 4
    private static let defaultPinLifetime: TimeInterval = 900

    private let session: URLSession
    private let clientIdentifier: String
    private let log: @Sendable (String) -> Void
    private let expiryStore = PlexPinExpiryStore()

    // MARK: PIN

    public func createPin() async throws -> PlexPin {
        let url = Self.plexTVBaseURL.appendingPathComponent("api/v2/pins")
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = Data()
        request.timeoutInterval = Self.requestTimeout

        let (data, http) = try await perform(request, context: "PIN create")
        guard (200...299).contains(http.statusCode) else {
            log("[Plex] PIN create failed status=\(http.statusCode)")
            throw PlexAuthError.requestFailed(L10n.tr("Plex 授权请求失败（HTTP %d）。", http.statusCode))
        }

        let payload: PinCreateResponse
        do {
            payload = try JSONDecoder().decode(PinCreateResponse.self, from: data)
        } catch {
            log("[Plex] PIN create response was not decodable")
            throw PlexAuthError.requestFailed(L10n.tr("无法解析 Plex 授权响应。"))
        }
        guard !payload.code.isEmpty else {
            log("[Plex] PIN create response had an empty code")
            throw PlexAuthError.requestFailed(L10n.tr("无法解析 Plex 授权响应。"))
        }

        let lifetime = TimeInterval(payload.expiresIn ?? Int(Self.defaultPinLifetime))
        let expiresAt = Date().addingTimeInterval(max(lifetime, 0))
        expiryStore.set(expiresAt, for: payload.id)
        log("[Plex] PIN created lifetime=\(Int(lifetime))s")
        return PlexPin(id: payload.id, code: payload.code, authURL: Self.linkPageURL, expiresAt: expiresAt)
    }

    /// 轮询 `GET /api/v2/pins/{id}`，直到拿到 `authToken`、PIN 过期或超时。
    ///
    /// `timeout` 是调用方愿意等待的总时长；PIN 自身有效期来自 `createPin` 的
    /// `expiresIn`，以两者中更早的时间为准。短暂的网络错误会重试到截止时间。
    ///
    /// PIN 有效期记录在 `PlexAuthAPI` 实例内，因此 `createPin` 与
    /// `awaitAuthorization` 必须在同一个实例上调用；否则只能依赖 `timeout`。
    public func awaitAuthorization(
        pinId: Int,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> String {
        let timeoutDeadline = Date().addingTimeInterval(max(timeout, 0))
        let interval = max(pollInterval, 0)
        var lastLoggedOutcome: String?

        while true {
            if Task.isCancelled {
                expiryStore.remove(pinId)
                throw PlexAuthError.authorizationCancelled
            }

            let now = Date()
            if let expiry = expiryStore.expiry(for: pinId), now >= expiry {
                expiryStore.remove(pinId)
                log("[Plex] PIN expired before authorization completed")
                throw PlexAuthError.pinExpired
            }
            if now >= timeoutDeadline {
                expiryStore.remove(pinId)
                log("[Plex] PIN authorization timed out")
                throw PlexAuthError.authorizationTimedOut
            }

            do {
                if let token = try await pollOnce(pinId: pinId), !token.isEmpty {
                    expiryStore.remove(pinId)
                    log("[Plex] PIN authorization completed")
                    return token
                }
            } catch let error as PlexAuthError {
                expiryStore.remove(pinId)
                throw error
            } catch let error as PlexTransientPollError {
                logRetryOnce(error.outcome, lastLoggedOutcome: &lastLoggedOutcome)
            } catch let error as URLError where error.code == .cancelled {
                expiryStore.remove(pinId)
                throw PlexAuthError.authorizationCancelled
            } catch {
                logRetryOnce("network", lastLoggedOutcome: &lastLoggedOutcome)
            }

            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(for: interval))
            } catch {
                expiryStore.remove(pinId)
                throw PlexAuthError.authorizationCancelled
            }
        }
    }

    // MARK: Discovery

    public func fetchServers(token: String) async throws -> [PlexServerResource] {
        guard var components = URLComponents(
            url: Self.plexTVBaseURL.appendingPathComponent("api/v2/resources"),
            resolvingAgainstBaseURL: false
        ) else {
            throw PlexAuthError.requestFailed(L10n.tr("无法构建 Plex 服务器发现请求。"))
        }
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]
        guard let url = components.url else {
            throw PlexAuthError.requestFailed(L10n.tr("无法构建 Plex 服务器发现请求。"))
        }

        var request = makeRequest(url: url, token: token)
        request.timeoutInterval = Self.requestTimeout
        let (data, http) = try await perform(request, context: "discovery")
        guard (200...299).contains(http.statusCode) else {
            log("[Plex] Discovery failed status=\(http.statusCode)")
            throw PlexAuthError.requestFailed(L10n.tr("Plex 服务器发现失败（HTTP %d）。", http.statusCode))
        }

        let resources: [PlexResourceResponse]
        do {
            resources = try JSONDecoder().decode([PlexResourceResponse].self, from: data)
        } catch {
            log("[Plex] Discovery response was not decodable")
            throw PlexAuthError.requestFailed(L10n.tr("无法解析 Plex 服务器列表。"))
        }

        let servers = resources.compactMap(\.serverResource)
        log("[Plex] Discovery resources=\(resources.count) servers=\(servers.count)")
        return servers
    }

    public func fetchAccount(token: String) async throws -> PlexAccount? {
        let url = Self.plexTVBaseURL.appendingPathComponent("api/v2/user")
        var request = makeRequest(url: url, token: token)
        request.timeoutInterval = Self.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            log("[Plex] Account lookup unavailable")
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            log("[Plex] Account lookup returned a non-success status")
            return nil
        }
        guard let payload = try? JSONDecoder().decode(PlexUserResponse.self, from: data) else {
            log("[Plex] Account response was not decodable")
            return nil
        }

        let candidates = [payload.username, payload.friendlyName, payload.title, payload.email]
        let username = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let username else { return nil }
        return PlexAccount(username: username, email: payload.email)
    }

    /// 按 `orderedConnections` 顺序探测 `GET /identity`，返回第一个可达端点。
    public func resolveEndpoint(
        for server: PlexServerResource,
        token: String
    ) async throws -> PlexServerConnection {
        for connection in server.orderedConnections {
            if Task.isCancelled {
                throw PlexAuthError.authorizationCancelled
            }
            // 资源来自远程响应：只探测 http/https URL，忽略其他 scheme。
            guard let baseURL = URL(string: connection.uri),
                  let scheme = baseURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = baseURL.host,
                  !host.isEmpty else {
                continue
            }
            // 明文 http 只允许局域网端点，避免 X-Plex-Token 以明文经过公网。
            if scheme == "http", !connection.isLocal {
                continue
            }

            var request = makeRequest(url: baseURL.appendingPathComponent("identity"), token: token)
            request.timeoutInterval = Self.probeTimeout
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    continue
                }
                log("[Plex] Endpoint probe succeeded kind=\(Self.probeKind(connection))")
                return connection
            } catch let error as URLError where error.code == .cancelled {
                throw PlexAuthError.authorizationCancelled
            } catch {
                continue
            }
        }
        log("[Plex] No reachable endpoint for server")
        throw PlexAuthError.serverUnreachable(server.name)
    }

    // MARK: - Requests

    private func makeRequest(url: URL, method: String = "GET", token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(Self.clientName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "X-Plex-Version")
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        return request
    }

    private func perform(
        _ request: URLRequest,
        context: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PlexAuthError.requestFailed(L10n.tr("Plex 返回了无法识别的响应。"))
            }
            return (data, http)
        } catch let error as PlexAuthError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw PlexAuthError.authorizationCancelled
        } catch is CancellationError {
            throw PlexAuthError.authorizationCancelled
        } catch {
            log("[Plex] \(context) request failed")
            throw PlexAuthError.requestFailed(L10n.tr("无法连接 Plex 服务，请检查网络后重试。"))
        }
    }

    private func pollOnce(pinId: Int) async throws -> String? {
        let url = Self.plexTVBaseURL.appendingPathComponent("api/v2/pins/\(pinId)")
        var request = makeRequest(url: url)
        request.timeoutInterval = Self.requestTimeout

        // 轮询期间的传输错误交给 awaitAuthorization 当作短暂失败重试，
        // 因此这里不经过 perform（它会立即转成 requestFailed）。
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw PlexAuthError.authorizationCancelled
        } catch is CancellationError {
            throw PlexAuthError.authorizationCancelled
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlexTransientPollError(outcome: "invalid-response")
        }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(PinPollResponse.self, from: data).authToken
            } catch {
                throw PlexTransientPollError(outcome: "status \(http.statusCode)")
            }
        case 404:
            throw PlexAuthError.pinExpired
        case 408, 425, 429, 500...599:
            throw PlexTransientPollError(outcome: "status \(http.statusCode)")
        default:
            throw PlexAuthError.requestFailed(L10n.tr("Plex 授权轮询失败（HTTP %d）。", http.statusCode))
        }
    }

    private func logRetryOnce(_ outcome: String, lastLoggedOutcome: inout String?) {
        guard lastLoggedOutcome != outcome else { return }
        lastLoggedOutcome = outcome
        log("[Plex] PIN poll retry outcome=\(outcome)")
    }

    private static func probeKind(_ connection: PlexServerConnection) -> String {
        if connection.isRelay { return "relay" }
        if connection.isLocal { return "local" }
        return "remote"
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((max(interval, 0) * 1_000_000_000).rounded())
    }
}

// MARK: - Private types

/// 轮询期间的短暂失败（网络错误、5xx/429、临时不可解析的响应）。
private struct PlexTransientPollError: Error {
    let outcome: String
}

private final class PlexPinExpiryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var expiries: [Int: Date] = [:]

    func set(_ date: Date, for pinId: Int) {
        lock.withLock { expiries[pinId] = date }
    }

    func expiry(for pinId: Int) -> Date? {
        lock.withLock { expiries[pinId] }
    }

    func remove(_ pinId: Int) {
        lock.withLock { expiries.removeValue(forKey: pinId) }
    }
}

private struct PinCreateResponse: Decodable {
    let id: Int
    let code: String
    let expiresIn: Int?
}

private struct PinPollResponse: Decodable {
    let authToken: String?
}

private struct PlexUserResponse: Decodable {
    let username: String?
    let email: String?
    let friendlyName: String?
    let title: String?
}

private struct PlexResourceResponse: Decodable {
    let name: String?
    let clientIdentifier: String?
    let product: String?
    let productVersion: String?
    let platform: String?
    let owned: Bool?
    let accessToken: String?
    let provides: String?
    let connections: [PlexServerConnection]?

    var serverResource: PlexServerResource? {
        guard let clientIdentifier, !clientIdentifier.isEmpty else { return nil }
        guard let provides,
              provides.split(separator: ",").contains(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare("server") == .orderedSame
              }) else {
            return nil
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PlexServerResource(
            name: trimmedName.isEmpty ? "Plex Media Server" : trimmedName,
            clientIdentifier: clientIdentifier,
            product: product,
            productVersion: productVersion,
            platform: platform,
            isOwned: owned ?? false,
            accessToken: accessToken,
            connections: connections ?? []
        )
    }
}