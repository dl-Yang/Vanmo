import XCTest
@testable import VanmoCore

final class BoxOAuthTests: XCTestCase {
    func testBoxUsesSecretBasedAuthorizationCodeFlow() {
        // Box 的 authorize 接口没有 code_challenge，无法走 PKCE；这里固定住 Secret 模式，
        // 避免以后误把它接进公共客户端分支。
        XCTAssertFalse(OAuthProviderConfiguration.usesPKCE(for: .box))
        XCTAssertFalse(OAuthProviderConfiguration.usesImplicitGrant(for: .box))
        XCTAssertNil(OAuthProviderConfiguration.googleURLScheme(for: .box))
        XCTAssertEqual(OAuthProviderConfiguration.scope(for: .box), "root_readwrite")
        XCTAssertEqual(OAuthProviderConfiguration.redirectURI(for: .box), "vanmo://oauth/box")
        XCTAssertEqual(OAuthProviderConfiguration.callbackURLScheme(for: .box), "vanmo")
        XCTAssertEqual(
            OAuthProviderConfiguration.authorizationEndpoint(for: .box)?.absoluteString,
            "https://account.box.com/api/oauth2/authorize"
        )
        XCTAssertEqual(
            OAuthProviderConfiguration.tokenEndpoint(for: .box)?.absoluteString,
            "https://api.box.com/oauth2/token"
        )
        XCTAssertTrue(OAuthProviderConfiguration.prefersEphemeralWebBrowserSession(for: .box))

        // 仓库只保留空占位，真实 Client ID / Secret 由构建者在本机填入；
        // 是否可登录必须同时取决于两者，不能只填 Client ID 就解锁。
        let clientID = OAuthProviderConfiguration.clientID(for: .box)
        let clientSecret = OAuthProviderConfiguration.clientSecret(for: .box) ?? ""
        XCTAssertEqual(
            OAuthProviderConfiguration.isConfigured(for: .box),
            !clientID.isEmpty && !clientSecret.isEmpty
        )
    }

    func testSecretModeRequiresBothIDAndSecretWhilePKCEClientsDoNot() {
        // 纯函数契约：Box/pCloud 这类 Secret 模式必须 ID + Secret 同时存在。
        XCTAssertFalse(OAuthProviderConfiguration.isConfigured(clientID: "", clientSecret: nil, type: .box))
        XCTAssertFalse(OAuthProviderConfiguration.isConfigured(clientID: "id", clientSecret: nil, type: .box))
        XCTAssertFalse(OAuthProviderConfiguration.isConfigured(clientID: "id", clientSecret: "   ", type: .box))
        XCTAssertTrue(OAuthProviderConfiguration.isConfigured(clientID: "id", clientSecret: "secret", type: .box))

        // PKCE 公共客户端与简化模式只要求 Client ID。
        XCTAssertTrue(OAuthProviderConfiguration.isConfigured(clientID: "id", clientSecret: nil, type: .oneDrive))
        XCTAssertTrue(OAuthProviderConfiguration.isConfigured(clientID: "id", clientSecret: nil, type: .baiduNetdisk))
        XCTAssertFalse(OAuthProviderConfiguration.isConfigured(clientID: " ", clientSecret: "secret", type: .box))
    }

    func testBoxCallbackMatchesOnlyTheBoxRedirectPath() {
        let exact = URLComponents(string: "vanmo://oauth/box?code=abc&state=state")!
        XCTAssertTrue(OAuthProviderConfiguration.matchesCallback(exact, type: .box))

        let uppercase = URLComponents(string: "vanmo://oauth/Box?code=abc&state=state")!
        XCTAssertFalse(OAuthProviderConfiguration.matchesCallback(uppercase, type: .box))

        let otherProvider = URLComponents(string: "vanmo://oauth/pCloudDrive?code=abc&state=state")!
        XCTAssertFalse(OAuthProviderConfiguration.matchesCallback(otherProvider, type: .box))
    }

    func testBoxIsRegisteredForItsConnectionType() {
        XCTAssertTrue(RemoteServiceFactory.create(for: .box) is BoxDriveService)
        XCTAssertTrue(ConnectionType.box.requiresLazyPlaybackURL)
        XCTAssertTrue(DownloadEligibility.isSupported(connectionType: .box))
        // Box 的取流地址是匿名签名直链，播放期间不需要 Bearer 头或自定义请求头。
        XCTAssertFalse(ConnectionType.box.requiresBearerStreaming)
        XCTAssertFalse(ConnectionType.box.requiresStreamingHeaderProvider)
    }

    func testBoxPathMapsToItemIDs() {
        XCTAssertEqual(BoxDriveService.itemId(from: "/"), BoxDriveService.rootFolderId)
        XCTAssertEqual(BoxDriveService.itemId(from: ""), BoxDriveService.rootFolderId)
        XCTAssertEqual(BoxDriveService.itemId(from: "/item/12345"), "12345")
        // 非 `/item/{id}` 形式一律回退到根目录，避免把未知路径当成文件 id 发给 Box。
        XCTAssertEqual(BoxDriveService.itemId(from: "Movies/clip.mp4"), BoxDriveService.rootFolderId)
        XCTAssertEqual(BoxDriveService.itemId(from: "/item/1/item/2"), BoxDriveService.rootFolderId)
    }

    func testBoxItemsRequestCarriesListShapeAndPaging() throws {
        let url = try BoxDriveService.itemsURL(folderId: BoxDriveService.rootFolderId, offset: 1000)
        XCTAssertEqual(url.host, "api.box.com")
        XCTAssertEqual(url.path, "/2.0/folders/0/items")

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            queryItems.first { $0.name == "fields" }?.value,
            "id,name,type,size,modified_at"
        )
        XCTAssertEqual(queryItems.first { $0.name == "limit" }?.value, "1000")
        XCTAssertEqual(queryItems.first { $0.name == "offset" }?.value, "1000")
    }

    func testBoxItemJSONMapsFilesAndFoldersAndSkipsWebLinks() throws {
        let json = """
        {
          "total_count": 3,
          "entries": [
            {"id": "11", "name": "Movies", "type": "folder", "modified_at": "2024-01-02T03:04:05-07:00"},
            {"id": "12", "name": "clip.mp4", "type": "file", "size": 1234, "modified_at": "2024-01-02T03:04:05Z"},
            {"id": "13", "name": "bookmark", "type": "web_link"}
          ]
        }
        """
        let decoded = try BoxDriveService.remoteFiles(fromItemsData: Data(json.utf8))
        XCTAssertEqual(decoded.totalCount, 3)
        XCTAssertEqual(decoded.files.count, 2)

        XCTAssertEqual(decoded.files[0].name, "Movies")
        XCTAssertTrue(decoded.files[0].isDirectory)
        XCTAssertEqual(decoded.files[0].path, "/item/11")
        let folderDate = try XCTUnwrap(decoded.files[0].modifiedDate)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: folderDate), 2024)

        XCTAssertEqual(decoded.files[1].name, "clip.mp4")
        XCTAssertFalse(decoded.files[1].isDirectory)
        XCTAssertEqual(decoded.files[1].size, 1234)
        XCTAssertEqual(decoded.files[1].path, "/item/12")
    }

    func testBoxErrorMessagesAreReadable() {
        let forbidden = Data(
            #"{"type":"error","status":403,"code":"access_denied_insufficient_permissions","message":"Insufficient permissions"}"#.utf8
        )
        let forbiddenMessage = BoxDriveService.errorMessage(statusCode: 403, data: forbidden)
        XCTAssertTrue(forbiddenMessage.contains("权限不足"))
        XCTAssertTrue(forbiddenMessage.contains("Insufficient permissions"))

        XCTAssertEqual(
            BoxDriveService.errorMessage(statusCode: 404, data: Data()),
            "Box 文件或目录不存在，可能已被移动或删除。"
        )
        XCTAssertEqual(
            BoxDriveService.errorMessage(statusCode: 429, data: Data()),
            "Box 请求过于频繁，请稍后重试。"
        )
        XCTAssertEqual(
            BoxDriveService.errorMessage(statusCode: 500, data: Data("oops".utf8)),
            "Box API 500: oops"
        )
    }

    func testBoxTokenFormsUseSecretAndNeverPKCEVerifier() {
        let codeItems = OAuthCoordinator.authorizationCodeFormItems(
            code: "auth-code",
            type: .box,
            codeVerifier: nil,
            clientSecret: "test-secret"
        )
        XCTAssertEqual(value(of: "grant_type", in: codeItems), "authorization_code")
        XCTAssertEqual(value(of: "client_id", in: codeItems), OAuthProviderConfiguration.clientID(for: .box))
        XCTAssertEqual(value(of: "redirect_uri", in: codeItems), "vanmo://oauth/box")
        XCTAssertEqual(value(of: "client_secret", in: codeItems), "test-secret")
        XCTAssertNil(value(of: "code_verifier", in: codeItems))

        let credential = OAuthCredential(
            provider: .box,
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: "root_readwrite",
            apiHost: nil
        )
        let refreshItems = OAuthCoordinator.refreshFormItems(
            credential: credential,
            type: .box,
            clientSecret: "test-secret"
        )
        XCTAssertEqual(value(of: "grant_type", in: refreshItems), "refresh_token")
        XCTAssertEqual(value(of: "refresh_token", in: refreshItems), "refresh")
        XCTAssertEqual(value(of: "client_secret", in: refreshItems), "test-secret")
        XCTAssertNil(value(of: "code_verifier", in: refreshItems))
    }

    func testPKCEProviderKeepsVerifierAndOmitsSecret() {
        let items = OAuthCoordinator.authorizationCodeFormItems(
            code: "code",
            type: .oneDrive,
            codeVerifier: "verifier",
            clientSecret: nil
        )
        XCTAssertEqual(value(of: "code_verifier", in: items), "verifier")
        XCTAssertNil(value(of: "client_secret", in: items))
    }

    func testTokenEndpointErrorsAreReadable() {
        let invalidGrant = Data(#"{"error":"invalid_grant","error_description":"Refresh token has expired"}"#.utf8)
        let expired = OAuthCoordinator.tokenErrorMessage(statusCode: 400, data: invalidGrant, type: .box)
        XCTAssertTrue(expired.contains("Box"))
        XCTAssertTrue(expired.contains("重新授权"))

        let invalidClient = Data(#"{"error":"invalid_client"}"#.utf8)
        let wrongCredentials = OAuthCoordinator.tokenErrorMessage(statusCode: 400, data: invalidClient, type: .box)
        XCTAssertTrue(wrongCredentials.contains("Client ID / Client Secret"))

        let other = Data(#"{"error":"invalid_scope"}"#.utf8)
        XCTAssertTrue(
            OAuthCoordinator.tokenErrorMessage(statusCode: 400, data: other, type: .box).contains("invalid_scope")
        )
    }

    @MainActor
    func testConcurrentRefreshIsCoalescedIntoOneOperation() async throws {
        let flight = OAuthRefreshSingleFlight()
        let connectionId = UUID()
        let counter = CallCounter()
        let gate = RefreshGate()
        let credential = makeCredential(accessToken: "fresh-token")

        let tasks = (0..<5).map { _ in
            Task { @MainActor in
                try await flight.credential(for: connectionId) {
                    counter.value += 1
                    await gate.wait()
                    return credential
                }
            }
        }

        // 等 1 个 owner 进入刷新、其余 4 个调用合并到同一个在途任务上。
        var spins = 0
        while flight.pendingWaiterCount < 4 && spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(flight.pendingWaiterCount, 4)
        XCTAssertTrue(flight.hasInFlightRefresh)
        XCTAssertEqual(counter.value, 1)

        gate.release()
        let results = try await withThrowingTaskGroup(of: OAuthCredential.self) { group in
            for task in tasks {
                group.addTask { try await task.value }
            }
            var values: [OAuthCredential] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(Set(results.map(\.accessToken)), ["fresh-token"])
        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(flight.hasInFlightRefresh)
    }

    @MainActor
    func testFailedRefreshIsNotCachedForTheNextCall() async throws {
        let flight = OAuthRefreshSingleFlight()
        let connectionId = UUID()
        let counter = CallCounter()

        do {
            _ = try await flight.credential(for: connectionId) {
                counter.value += 1
                throw RefreshFailure.rejected
            }
            XCTFail("expected the first refresh to fail")
        } catch {
            XCTAssertTrue(error is RefreshFailure)
        }
        XCTAssertFalse(flight.hasInFlightRefresh)

        let credential = try await flight.credential(for: connectionId) {
            counter.value += 1
            return self.makeCredential(accessToken: "second-attempt")
        }
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(credential.accessToken, "second-attempt")
        XCTAssertFalse(flight.hasInFlightRefresh)
    }

    private func makeCredential(accessToken: String) -> OAuthCredential {
        OAuthCredential(
            provider: .box,
            accessToken: accessToken,
            refreshToken: "rotated-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: "root_readwrite",
            apiHost: nil
        )
    }

    private func value(of name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }
}

private enum RefreshFailure: Error {
    case rejected
}

private final class CallCounter: @unchecked Sendable {
    var value = 0
}

/// 测试用放行闸门：owner 在刷新任务内自旋等待，直到测试放行。
@MainActor
private final class RefreshGate {
    private var isReleased = false

    func wait() async {
        while !isReleased {
            await Task.yield()
        }
    }

    func release() {
        isReleased = true
    }
}