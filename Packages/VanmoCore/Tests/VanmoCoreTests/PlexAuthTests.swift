import Foundation
import XCTest
@testable import VanmoCore

final class PlexAuthTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlexURLProtocolStub.reset()
    }

    override func tearDown() {
        PlexURLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - PIN creation

    func testCreatePinParsesPayloadAndBuildsAuthURL() async throws {
        PlexURLProtocolStub.setHandler { request in
            let method = request.httpMethod ?? ""
            guard method == "POST", request.url?.path == "/api/v2/pins" else {
                throw URLError(.unsupportedURL)
            }
            return (201, Self.pinJSON(id: 41_320_231, code: "7PSW", expiresIn: 900))
        }

        let api = makeAPI()
        let pin = try await api.createPin()

        XCTAssertEqual(pin.id, 41_320_231)
        XCTAssertEqual(pin.code, "7PSW")
        XCTAssertFalse(pin.isExpired)
        // app.plex.tv/auth 只接受 strong PIN；四位代码必须在 plex.tv/link 输入。
        XCTAssertEqual(pin.authURL.absoluteString, "https://plex.tv/link")

        let request = try XCTUnwrap(PlexURLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v2/pins")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "TEST-CLIENT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Product"), "Vanmo")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Version"), "1.0.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        // 不能请求 strong PIN（那会返回 25 位代码），也不带额外查询参数。
        XCTAssertNil(request.url?.query)
        let body = PlexURLProtocolStub.requestBodies.first ?? nil
        XCTAssertTrue(body?.isEmpty ?? true)
    }

    func testPlexPinIsExpiredTracksDeadline() throws {
        let url = try XCTUnwrap(URL(string: "https://app.plex.tv/auth"))
        XCTAssertTrue(
            PlexPin(id: 1, code: "ABCD", authURL: url, expiresAt: Date(timeIntervalSinceNow: -1)).isExpired
        )
        XCTAssertFalse(
            PlexPin(id: 2, code: "ABCD", authURL: url, expiresAt: Date(timeIntervalSinceNow: 60)).isExpired
        )
    }

    // MARK: - Authorization polling

    func testAwaitAuthorizationReturnsTokenAfterPollTransition() async throws {
        let pollCount = LockedCounter()
        PlexURLProtocolStub.setHandler { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v2/pins"):
                return (201, Self.pinJSON(expiresIn: 900))
            case ("GET", "/api/v2/pins/41320231"):
                let count = pollCount.increment()
                return (200, Self.pollJSON(authToken: count >= 2 ? "ACCOUNT-TOKEN" : nil))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let api = makeAPI()
        let pin = try await api.createPin()
        let token = try await api.awaitAuthorization(pinId: pin.id, timeout: 2, pollInterval: 0.01)

        XCTAssertEqual(token, "ACCOUNT-TOKEN")
        let polls = PlexURLProtocolStub.requests.filter { $0.url?.path == "/api/v2/pins/41320231" }
        XCTAssertEqual(polls.count, 2)
        for poll in polls {
            XCTAssertEqual(poll.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "TEST-CLIENT")
            XCTAssertNil(poll.value(forHTTPHeaderField: "X-Plex-Token"))
        }
    }

    func testAwaitAuthorizationThrowsPinExpiredWhenPinLifetimeElapses() async throws {
        PlexURLProtocolStub.setHandler { request in
            guard request.httpMethod == "POST", request.url?.path == "/api/v2/pins" else {
                throw URLError(.unsupportedURL)
            }
            return (201, Self.pinJSON(expiresIn: 0))
        }

        let api = makeAPI()
        let pin = try await api.createPin()
        XCTAssertTrue(pin.isExpired)

        await assertPlexAuthError(.pinExpired) {
            try await api.awaitAuthorization(pinId: pin.id, timeout: 2, pollInterval: 0.01)
        }
        XCTAssertTrue(
            PlexURLProtocolStub.requests.filter { $0.url?.path.hasPrefix("/api/v2/pins/") == true }.isEmpty
        )
    }

    func testAwaitAuthorizationThrowsAuthorizationTimedOut() async throws {
        PlexURLProtocolStub.setHandler { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v2/pins"):
                return (201, Self.pinJSON(expiresIn: 900))
            case ("GET", "/api/v2/pins/41320231"):
                return (200, Self.pollJSON(authToken: nil))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let api = makeAPI()
        let pin = try await api.createPin()
        await assertPlexAuthError(.authorizationTimedOut) {
            try await api.awaitAuthorization(pinId: pin.id, timeout: 0.05, pollInterval: 0.01)
        }
    }

    func testAwaitAuthorizationThrowsAuthorizationCancelled() async throws {
        PlexURLProtocolStub.setHandler { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v2/pins"):
                return (201, Self.pinJSON(expiresIn: 900))
            case ("GET", "/api/v2/pins/41320231"):
                return (200, Self.pollJSON(authToken: nil))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let api = makeAPI()
        let pin = try await api.createPin()
        let task = Task {
            try await api.awaitAuthorization(pinId: pin.id, timeout: 5, pollInterval: 0.02)
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the poll to be cancelled")
        } catch let error as PlexAuthError {
            XCTAssertEqual(error, .authorizationCancelled)
        }
    }

    func testAwaitAuthorizationRetriesTransientNetworkErrors() async throws {
        let attempts = LockedCounter()
        PlexURLProtocolStub.setHandler { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v2/pins"):
                return (201, Self.pinJSON(expiresIn: 900))
            case ("GET", "/api/v2/pins/41320231"):
                if attempts.increment() <= 2 {
                    throw URLError(.networkConnectionLost)
                }
                return (200, Self.pollJSON(authToken: "RETRIED-TOKEN"))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let api = makeAPI()
        let pin = try await api.createPin()
        let token = try await api.awaitAuthorization(pinId: pin.id, timeout: 2, pollInterval: 0.01)

        XCTAssertEqual(token, "RETRIED-TOKEN")
        XCTAssertEqual(attempts.current, 3)
    }

    func testLogsNeverContainPINCodeOrToken() async throws {
        let logs = LockedBox<[String]>([])
        let api = PlexAuthAPI(
            session: makeSession(),
            clientIdentifier: "TEST-CLIENT",
            log: { message in logs.update { $0.append(message) } }
        )
        let attempts = LockedCounter()
        PlexURLProtocolStub.setHandler { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/v2/pins"):
                return (201, Self.pinJSON(code: "ABCD", expiresIn: 900))
            case ("GET", "/api/v2/pins/41320231"):
                if attempts.increment() <= 2 {
                    throw URLError(.networkConnectionLost)
                }
                return (200, Self.pollJSON(authToken: "SECRET-AUTH-TOKEN"))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let pin = try await api.createPin()
        let token = try await api.awaitAuthorization(pinId: pin.id, timeout: 2, pollInterval: 0.01)
        XCTAssertEqual(token, "SECRET-AUTH-TOKEN")

        let text = logs.current.joined(separator: "\n")
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("[Plex]"))
        XCTAssertFalse(text.contains("SECRET-AUTH-TOKEN"))
        XCTAssertFalse(text.contains("ABCD"))
        XCTAssertFalse(text.contains("TEST-CLIENT"))
    }

    // MARK: - Discovery

    func testFetchServersFiltersResourcesWithoutServerCapability() async throws {
        PlexURLProtocolStub.setHandler { request in
            guard request.url?.path == "/api/v2/resources" else {
                throw URLError(.unsupportedURL)
            }
            return (200, Self.resourcesJSON())
        }

        let api = makeAPI()
        let servers = try await api.fetchServers(token: "ACCOUNT-TOKEN")

        XCTAssertEqual(servers.count, 1)
        let server = try XCTUnwrap(servers.first)
        XCTAssertEqual(server.name, "Living Room")
        XCTAssertEqual(server.clientIdentifier, "server-1")
        XCTAssertEqual(server.productVersion, "1.41.0")
        XCTAssertEqual(server.accessToken, "SERVER-ACCESS-TOKEN")
        XCTAssertTrue(server.isOwned)
        XCTAssertEqual(server.connections.count, 4)

        let request = try XCTUnwrap(PlexURLProtocolStub.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v2/resources")
        let items = queryItems(try XCTUnwrap(request.url))
        XCTAssertEqual(items["includeHttps"], "1")
        XCTAssertEqual(items["includeRelay"], "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Token"), "ACCOUNT-TOKEN")
        XCTAssertFalse((request.url?.absoluteString ?? "").contains("ACCOUNT-TOKEN"))
    }

    func testOrderedConnectionsPreferNonRelayThenLocalThenHTTPSThenIPv4() async throws {
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.resourcesJSON())
        }

        let api = makeAPI()
        let servers = try await api.fetchServers(token: "ACCOUNT-TOKEN")
        let server = try XCTUnwrap(servers.first)
        XCTAssertEqual(
            server.orderedConnections.map(\.uri),
            [
                "http://192.168.1.20:32400",
                "https://home.example.com:32400",
                "http://203.0.113.10:32400",
                "https://relay.example:443",
            ]
        )
    }

    // MARK: - Endpoint probing

    func testResolveEndpointFallsBackToNextCandidate() async throws {
        let failedHosts = LockedBox<[String]>([])
        PlexURLProtocolStub.setHandler { request in
            if request.url?.path == "/api/v2/resources" {
                return (200, Self.resourcesJSON())
            }
            guard request.url?.path == "/identity" else {
                throw URLError(.unsupportedURL)
            }
            let host = request.url?.host ?? ""
            if host == "192.168.1.20" {
                failedHosts.update { $0.append(host) }
                throw URLError(.cannotConnectToHost)
            }
            return (200, Self.identityJSON())
        }

        let api = makeAPI()
        let servers = try await api.fetchServers(token: "ACCOUNT-TOKEN")
        let server = try XCTUnwrap(servers.first)
        let endpoint = try await api.resolveEndpoint(for: server, token: "ACCOUNT-TOKEN")

        XCTAssertEqual(endpoint.uri, "https://home.example.com:32400")
        XCTAssertEqual(failedHosts.current, ["192.168.1.20"])

        let probes = PlexURLProtocolStub.requests.filter { $0.url?.path == "/identity" }
        XCTAssertEqual(probes.map { $0.url?.host }, ["192.168.1.20", "home.example.com"])
        for probe in probes {
            XCTAssertEqual(probe.value(forHTTPHeaderField: "X-Plex-Token"), "ACCOUNT-TOKEN")
            XCTAssertEqual(probe.timeoutInterval, 4)
            XCTAssertFalse((probe.url?.absoluteString ?? "").contains("ACCOUNT-TOKEN"))
        }
    }

    func testResolveEndpointThrowsServerUnreachableWhenNoCandidateAnswers() async throws {
        PlexURLProtocolStub.setHandler { request in
            if request.url?.path == "/api/v2/resources" {
                return (200, Self.resourcesJSON())
            }
            throw URLError(.cannotConnectToHost)
        }

        let api = makeAPI()
        let servers = try await api.fetchServers(token: "ACCOUNT-TOKEN")
        let server = try XCTUnwrap(servers.first)
        await assertPlexAuthError(.serverUnreachable("Living Room")) {
            try await api.resolveEndpoint(for: server, token: "ACCOUNT-TOKEN")
        }
        let probedHosts = PlexURLProtocolStub.requests
            .filter { $0.url?.path == "/identity" }
            .compactMap { $0.url?.host }
        // 远程明文 http 端点不会带着 token 被探测。
        XCTAssertEqual(probedHosts, ["192.168.1.20", "home.example.com", "relay.example"])
    }

    // MARK: - Account

    func testFetchAccountDecodesTolerantPayload() async throws {
        PlexURLProtocolStub.setHandler { request in
            guard request.url?.path == "/api/v2/user" else {
                throw URLError(.unsupportedURL)
            }
            return (200, Self.accountJSON())
        }

        let api = makeAPI()
        let account = try await api.fetchAccount(token: "ACCOUNT-TOKEN")

        XCTAssertEqual(account, PlexAccount(username: "alice", email: "alice@example.com"))
        let request = try XCTUnwrap(PlexURLProtocolStub.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Token"), "ACCOUNT-TOKEN")
    }

    func testFetchAccountFallsBackToEmailWhenUsernameMissing() async throws {
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.json(["email": "only@example.com"]))
        }

        let api = makeAPI()
        let account = try await api.fetchAccount(token: "ACCOUNT-TOKEN")
        XCTAssertEqual(account, PlexAccount(username: "only@example.com", email: "only@example.com"))
    }

    func testFetchAccountReturnsNilForNonSuccessStatus() async throws {
        PlexURLProtocolStub.setHandler { _ in
            (500, Data())
        }

        let api = makeAPI()
        let account = try await api.fetchAccount(token: "ACCOUNT-TOKEN")
        XCTAssertNil(account)
    }

    // MARK: - Token-first connect

    func testTokenFirstConnectUsesPerConnectionToken() async throws {
        let connectionId = UUID()
        let recorder = PlexCredentialRecorder()
        recorder.setToken("CONNECTION-TOKEN", for: connectionId)
        PlexURLProtocolStub.setHandler { request in
            guard request.url?.path == "/identity" else {
                throw URLError(.unsupportedURL)
            }
            return (200, Self.identityJSON())
        }

        let service = makePlexService(recorder)
        let config = ConnectionConfig(
            connectionId: connectionId,
            type: .plex,
            host: "http://127.0.0.1:32400",
            port: 32400
        )
        try await service.connect(config: config)

        XCTAssertTrue(service.isConnected)
        XCTAssertFalse(
            PlexURLProtocolStub.requests.contains { $0.url?.path == "/api/v2/users/signin" }
        )
        let identity = try XCTUnwrap(
            PlexURLProtocolStub.requests.first { $0.url?.path == "/identity" }
        )
        let items = queryItems(try XCTUnwrap(identity.url))
        XCTAssertEqual(items["X-Plex-Token"], "CONNECTION-TOKEN")

        XCTAssertEqual(recorder.resolvedIdentifiers, [connectionId])
        // token-first 不需要重写 per-connection Keychain 槽。
        XCTAssertTrue(recorder.savedTokens.isEmpty)
        XCTAssertEqual(recorder.mirrors.map(\.0), ["http://127.0.0.1:32400"])
        XCTAssertEqual(recorder.mirrors.map(\.1), ["CONNECTION-TOKEN"])

        await service.disconnect()
    }

    func testPerConnectionTokensAreIsolated() async throws {
        let firstId = UUID()
        let secondId = UUID()
        let recorder = PlexCredentialRecorder()
        recorder.setToken("TOKEN-A", for: firstId)
        recorder.setToken("TOKEN-B", for: secondId)
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.identityJSON())
        }

        let firstService = makePlexService(recorder)
        let secondService = makePlexService(recorder)
        try await firstService.connect(config: ConnectionConfig(
            connectionId: firstId,
            type: .plex,
            host: "http://127.0.0.1:32400",
            port: 32400
        ))
        try await secondService.connect(config: ConnectionConfig(
            connectionId: secondId,
            type: .plex,
            host: "http://127.0.0.1:32401",
            port: 32400
        ))

        let tokens = PlexURLProtocolStub.requests
            .filter { $0.url?.path == "/identity" }
            .map { request in
                request.url.flatMap { queryItems($0)["X-Plex-Token"] } ?? ""
            }
        XCTAssertEqual(tokens, ["TOKEN-A", "TOKEN-B"])
        XCTAssertEqual(recorder.resolvedIdentifiers, [firstId, secondId])
        XCTAssertEqual(recorder.mirrors.map(\.1), ["TOKEN-A", "TOKEN-B"])

        await firstService.disconnect()
        await secondService.disconnect()
    }

    // MARK: - Legacy password fallback

    func testLegacyPasswordFallbackSignsInThroughPlexTV() async throws {
        let connectionId = UUID()
        let recorder = PlexCredentialRecorder()
        PlexURLProtocolStub.setHandler { request in
            switch request.url?.path ?? "" {
            case "/api/v2/users/signin":
                return (200, Self.signinJSON())
            case "/identity":
                return (200, Self.identityJSON())
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let service = makePlexService(recorder)
        let config = ConnectionConfig(
            connectionId: connectionId,
            type: .plex,
            host: "192.168.1.30",
            port: 32400,
            username: "user@example.com",
            password: "not-a-real-password"
        )
        try await service.connect(config: config)

        XCTAssertTrue(service.isConnected)
        XCTAssertEqual(recorder.resolvedIdentifiers, [connectionId])
        XCTAssertEqual(recorder.savedTokens.map(\.0), [connectionId])
        XCTAssertEqual(recorder.savedTokens.map(\.1), ["LEGACY-TOKEN"])
        XCTAssertEqual(recorder.mirrors.map(\.0), ["http://192.168.1.30:32400"])
        XCTAssertEqual(recorder.mirrors.map(\.1), ["LEGACY-TOKEN"])

        let signinIndex = try XCTUnwrap(
            PlexURLProtocolStub.requests.firstIndex { $0.url?.path == "/api/v2/users/signin" }
        )
        let signinRequest = PlexURLProtocolStub.requests[signinIndex]
        XCTAssertEqual(signinRequest.httpMethod, "POST")
        XCTAssertEqual(
            signinRequest.value(forHTTPHeaderField: "X-Plex-Client-Identifier"),
            PlexCredentialStore.clientIdentifier
        )
        let body = try XCTUnwrap(PlexURLProtocolStub.requestBodies[signinIndex] ?? nil)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("login="))
        XCTAssertTrue(bodyString.contains("user"))
        XCTAssertTrue(bodyString.contains("password=not-a-real-password"))

        await service.disconnect()
    }

    func testConnectFailsWithoutAnyCredential() async throws {
        let service = makePlexService(PlexCredentialRecorder())
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.identityJSON())
        }

        do {
            try await service.connect(config: ConnectionConfig(type: .plex, host: "192.168.1.30", port: 32400))
            XCTFail("Expected authenticationFailed")
        } catch NetworkError.authenticationFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(PlexURLProtocolStub.requests.isEmpty)
    }

    // MARK: - Base URL composition

    func testConnectHostWithSchemeKeepsItsOwnPort() async throws {
        let connectionId = UUID()
        let recorder = PlexCredentialRecorder()
        recorder.setToken("TOKEN", for: connectionId)
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.identityJSON())
        }

        let service = makePlexService(recorder)
        try await service.connect(config: ConnectionConfig(
            connectionId: connectionId,
            type: .plex,
            host: "https://plex.example:8443",
            port: 8443
        ))

        let identity = try XCTUnwrap(
            PlexURLProtocolStub.requests.first { $0.url?.path == "/identity" }
        )
        let url = try XCTUnwrap(identity.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "plex.example")
        XCTAssertEqual(url.port, 8443)
        await service.disconnect()
    }

    func testConnectBareHostComposesConfiguredPort() async throws {
        let connectionId = UUID()
        let recorder = PlexCredentialRecorder()
        recorder.setToken("TOKEN", for: connectionId)
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.identityJSON())
        }

        let service = makePlexService(recorder)
        try await service.connect(config: ConnectionConfig(
            connectionId: connectionId,
            type: .plex,
            host: "plex.example",
            port: 32400
        ))

        let identity = try XCTUnwrap(
            PlexURLProtocolStub.requests.first { $0.url?.path == "/identity" }
        )
        let url = try XCTUnwrap(identity.url)
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "plex.example")
        XCTAssertEqual(url.port, 32400)
        await service.disconnect()
    }

    func testConnectBareHostOnPort443UsesHTTPS() async throws {
        let connectionId = UUID()
        let recorder = PlexCredentialRecorder()
        recorder.setToken("TOKEN", for: connectionId)
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.identityJSON())
        }

        let service = makePlexService(recorder)
        try await service.connect(config: ConnectionConfig(
            connectionId: connectionId,
            type: .plex,
            host: "plex.example",
            port: 443
        ))

        let identity = try XCTUnwrap(
            PlexURLProtocolStub.requests.first { $0.url?.path == "/identity" }
        )
        let url = try XCTUnwrap(identity.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "plex.example")
        XCTAssertNil(url.port)
        await service.disconnect()
    }

    func testMediaServerConnectionSnapshotConfigCarriesConnectionId() {
        let connection = SavedConnection(
            name: "Plex",
            type: .plex,
            host: "http://127.0.0.1:32400",
            port: 32400
        )
        let snapshot = MediaServerConnectionSnapshot(connection: connection, password: nil)
        XCTAssertEqual(snapshot.config.connectionId, connection.id)
    }

    // MARK: - Credential store

    func testPlexConnectionTokenUsesDedicatedKeychainAccount() {
        let connectionId = UUID()
        XCTAssertEqual(
            PlexCredentialStore.connectionTokenAccount(for: connectionId),
            "conn_\(connectionId.uuidString)_plex"
        )
    }

    func testPlexCredentialStoreRoundTripsPerConnectionToken() throws {
        let connectionId = UUID()
        let token = "keychain-token-\(UUID().uuidString)"
        do {
            try PlexCredentialStore.saveToken(token, forConnectionId: connectionId)
        } catch KeychainError.saveFailed(let status) where status == -34_018 {
            // errSecMissingEntitlement：未签名测试进程无法使用 Data Protection Keychain。
            throw XCTSkip("Data Protection Keychain is unavailable in this unsigned test process.")
        } catch {
            return XCTFail("Unexpected Keychain failure: \(error)")
        }
        defer { try? PlexCredentialStore.deleteToken(forConnectionId: connectionId) }

        XCTAssertEqual(PlexCredentialStore.token(forConnectionId: connectionId), token)
        try PlexCredentialStore.deleteToken(forConnectionId: connectionId)
        XCTAssertNil(PlexCredentialStore.token(forConnectionId: connectionId))
    }

    func testEffectiveTokenPrefersSharedServerAccessToken() async throws {
        PlexURLProtocolStub.setHandler { _ in
            (200, Self.sharedServersJSON())
        }

        let api = makeAPI()
        let servers = try await api.fetchServers(token: "ACCOUNT-TOKEN")
        XCTAssertEqual(servers.count, 2)

        let shared = try XCTUnwrap(servers.first { $0.clientIdentifier == "shared-server" })
        let owned = try XCTUnwrap(servers.first { $0.clientIdentifier == "owned-server" })
        XCTAssertEqual(shared.effectiveToken(accountToken: "ACCOUNT-TOKEN"), "SHARED-TOKEN")
        XCTAssertEqual(owned.effectiveToken(accountToken: "ACCOUNT-TOKEN"), "ACCOUNT-TOKEN")
    }

    func testPlexAuthErrorMessagesAreLocalizedAtCallSite() async throws {
        let previousPreference = AppLanguagePreference.stored
        AppLanguagePreference.stored = .english
        defer { AppLanguagePreference.stored = previousPreference }

        let expiredDescription = PlexAuthError.pinExpired.localizedDescription
        XCTAssertEqual(expiredDescription, L10n.tr("授权代码已过期，请重新获取代码。"))
        XCTAssertNil(expiredDescription.range(of: "\\p{Han}", options: .regularExpression))

        PlexURLProtocolStub.setHandler { _ in
            (500, Data())
        }
        let api = makeAPI()
        do {
            _ = try await api.createPin()
            XCTFail("Expected createPin to fail")
        } catch let error as PlexAuthError {
            guard case .requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("500"))
            XCTAssertNil(message.range(of: "\\p{Han}", options: .regularExpression))
        }
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlexURLProtocolStub.self]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }

    private func makeAPI(
        clientIdentifier: String = "TEST-CLIENT",
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> PlexAuthAPI {
        PlexAuthAPI(session: makeSession(), clientIdentifier: clientIdentifier, log: log)
    }

    private func makePlexService(_ recorder: PlexCredentialRecorder) -> PlexService {
        PlexService(
            session: makeSession(),
            tokenResolver: { recorder.resolve($0) },
            tokenSaver: { connectionId, token in try recorder.save(token, for: connectionId) },
            mirrorSaver: { baseURL, token in recorder.mirror(baseURL: baseURL, token: token) }
        )
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func assertPlexAuthError<T>(
        _ expected: PlexAuthError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as PlexAuthError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    // MARK: - Payloads

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func identityJSON() -> Data {
        json(["MediaContainer": ["size": 0]])
    }

    private static func pinJSON(
        id: Int = 41_320_231,
        code: String = "7PSW",
        expiresIn: Int = 900
    ) -> Data {
        json(["id": id, "code": code, "expiresIn": expiresIn, "authToken": NSNull()])
    }

    private static func pollJSON(authToken: String?) -> Data {
        let tokenValue: Any = authToken ?? NSNull()
        return json([
            "id": 41_320_231,
            "code": "7PSW",
            "expiresIn": 900,
            "authToken": tokenValue,
        ])
    }

    private static func signinJSON() -> Data {
        json(["authToken": "LEGACY-TOKEN"])
    }

    private static func accountJSON() -> Data {
        json(["username": "alice", "email": "alice@example.com", "friendlyName": "Alice"])
    }

    private static func resourcesJSON() -> Data {
        let server: [String: Any] = [
            "name": "Living Room",
            "clientIdentifier": "server-1",
            "product": "Plex Media Server",
            "productVersion": "1.41.0",
            "platform": "Linux",
            "owned": true,
            "accessToken": "SERVER-ACCESS-TOKEN",
            "provides": "server,pubsub,player",
            "connections": [
                connection(
                    uri: "https://relay.example:443",
                    address: "relay.example",
                    port: 443,
                    local: false,
                    relay: true,
                    protocolName: "https"
                ),
                connection(
                    uri: "http://192.168.1.20:32400",
                    address: "192.168.1.20",
                    port: 32400,
                    local: true,
                    relay: false
                ),
                connection(
                    uri: "http://203.0.113.10:32400",
                    address: "203.0.113.10",
                    port: 32400,
                    local: false,
                    relay: false
                ),
                connection(
                    uri: "https://home.example.com:32400",
                    address: "home.example.com",
                    port: 32400,
                    local: false,
                    relay: false,
                    protocolName: "https"
                ),
            ],
        ]
        let client: [String: Any] = [
            "name": "Plex Web",
            "clientIdentifier": "client-1",
            "provides": "client,player",
            "connections": [],
        ]
        return json([server, client])
    }

    private static func sharedServersJSON() -> Data {
        let shared: [String: Any] = [
            "name": "Friend's Server",
            "clientIdentifier": "shared-server",
            "owned": false,
            "accessToken": "SHARED-TOKEN",
            "provides": "server",
            "connections": [],
        ]
        let owned: [String: Any] = [
            "name": "My Server",
            "clientIdentifier": "owned-server",
            "owned": true,
            "provides": "server",
            "connections": [],
        ]
        return json([shared, owned])
    }

    private static func connection(
        uri: String,
        address: String,
        port: Int,
        local: Bool,
        relay: Bool,
        protocolName: String = "http"
    ) -> [String: Any] {
        [
            "uri": uri,
            "address": address,
            "port": port,
            "local": local,
            "relay": relay,
            "protocol": protocolName,
        ]
    }
}

// MARK: - Fakes

private final class PlexCredentialRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String] = [:]
    private var resolved: [UUID] = []
    private var saved: [(UUID, String)] = []
    private var mirrored: [(String, String)] = []

    func setToken(_ token: String, for connectionId: UUID) {
        lock.withLock { tokens[connectionId] = token }
    }

    func resolve(_ connectionId: UUID) -> String? {
        lock.withLock {
            resolved.append(connectionId)
            return tokens[connectionId]
        }
    }

    func save(_ token: String, for connectionId: UUID) throws {
        lock.withLock { saved.append((connectionId, token)) }
    }

    func mirror(baseURL: String, token: String) {
        lock.withLock { mirrored.append((baseURL, token)) }
    }

    var resolvedIdentifiers: [UUID] {
        lock.withLock { resolved }
    }

    var savedTokens: [(UUID, String)] {
        lock.withLock { saved }
    }

    var mirrors: [(String, String)] {
        lock.withLock { mirrored }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var current: Value {
        lock.withLock { value }
    }

    func update(_ body: (inout Value) -> Void) {
        lock.withLock { body(&value) }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var current: Int {
        lock.withLock { value }
    }
}

private final class PlexURLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) private static var recorded: [(request: URLRequest, body: Data?)] = []

    static func setHandler(_ handler: ((URLRequest) throws -> (Int, Data))?) {
        lock.withLock { self.handler = handler }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            recorded.removeAll()
        }
    }

    static var requests: [URLRequest] {
        lock.withLock { recorded.map(\.request) }
    }

    static var requestBodies: [Data?] {
        lock.withLock { recorded.map(\.body) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        let handler = Self.lock.withLock { () -> ((URLRequest) throws -> (Int, Data))? in
            Self.recorded.append((request, body))
            return Self.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: status,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}