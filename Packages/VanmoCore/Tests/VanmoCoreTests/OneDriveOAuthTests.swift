import XCTest
@testable import VanmoCore

final class OneDriveOAuthTests: XCTestCase {
    func testOneDriveIsConfiguredAsPKCEPublicClient() {
        XCTAssertTrue(OAuthProviderConfiguration.isConfigured(for: .oneDrive))
        XCTAssertTrue(OAuthProviderConfiguration.usesPKCE(for: .oneDrive))
        XCTAssertFalse(OAuthProviderConfiguration.usesImplicitGrant(for: .oneDrive))
        XCTAssertNil(OAuthProviderConfiguration.clientSecret(for: .oneDrive))
        XCTAssertEqual(OAuthProviderConfiguration.scope(for: .oneDrive), "Files.Read.All offline_access")
        XCTAssertEqual(OAuthProviderConfiguration.redirectURI(for: .oneDrive), "vanmo://oauth/oneDrive")
        XCTAssertEqual(OAuthProviderConfiguration.callbackURLScheme(for: .oneDrive), "vanmo")
        XCTAssertEqual(
            OAuthProviderConfiguration.authorizationEndpoint(for: .oneDrive)?.absoluteString,
            "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        )
        XCTAssertEqual(
            OAuthProviderConfiguration.tokenEndpoint(for: .oneDrive)?.absoluteString,
            "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        )
        XCTAssertTrue(OAuthProviderConfiguration.prefersEphemeralWebBrowserSession(for: .oneDrive))
    }

    func testOneDriveCallbackMatchesOnlyTheExactRedirectPath() {
        let exact = URLComponents(string: "vanmo://oauth/oneDrive?code=abc&state=state")!
        XCTAssertTrue(OAuthProviderConfiguration.matchesCallback(exact, type: .oneDrive))

        // Entra 的重定向 URI 区分大小写，注册成小写路径后回调不会被当成有效结果。
        let lowercase = URLComponents(string: "vanmo://oauth/onedrive?code=abc&state=state")!
        XCTAssertFalse(OAuthProviderConfiguration.matchesCallback(lowercase, type: .oneDrive))

        let otherProvider = URLComponents(string: "vanmo://oauth/yandexDisk?code=abc&state=state")!
        XCTAssertFalse(OAuthProviderConfiguration.matchesCallback(otherProvider, type: .oneDrive))
    }

    func testItemRequestOmitsSelectSoGraphReturnsTheDownloadAnnotation() {
        // Graph 会在 `$select` 中静默丢掉 `@microsoft.graph.downloadUrl`，真机联调因此拿不到
        // 播放/下载直链。这个用例固定住「单文件元数据请求不带 $select」的约定。
        let itemURL = OneDriveService.itemURL(for: "01ABCDEF")
        let components = URLComponents(url: itemURL, resolvingAgainstBaseURL: false)
        XCTAssertNil(components?.queryItems?.first { $0.name == "$select" })
        XCTAssertEqual(
            itemURL.absoluteString,
            "https://graph.microsoft.com/v1.0/me/drive/items/01ABCDEF"
        )
        XCTAssertEqual(
            OneDriveService.itemURL(for: "root").absoluteString,
            "https://graph.microsoft.com/v1.0/me/drive/root"
        )
    }

    func testOneDriveIsRegisteredForItsConnectionType() {
        XCTAssertTrue(RemoteServiceFactory.create(for: .oneDrive) is OneDriveService)
        XCTAssertTrue(ConnectionType.oneDrive.requiresLazyPlaybackURL)
        XCTAssertTrue(DownloadEligibility.isSupported(connectionType: .oneDrive))
    }

    func testGraphErrorMessagesAreReadable() {
        let forbidden = Data(#"{"error":{"code":"accessDenied","message":"Access denied"}}"#.utf8)
        let forbiddenMessage = OneDriveService.errorMessage(statusCode: 403, data: forbidden)
        XCTAssertTrue(forbiddenMessage.contains("权限不足"))
        XCTAssertTrue(forbiddenMessage.contains("Access denied"))

        XCTAssertEqual(
            OneDriveService.errorMessage(statusCode: 404, data: Data()),
            "OneDrive 文件或目录不存在，可能已被移动或删除。"
        )
        XCTAssertEqual(
            OneDriveService.errorMessage(statusCode: 429, data: Data()),
            "OneDrive 请求过于频繁，请稍后重试。"
        )
        XCTAssertEqual(
            OneDriveService.errorMessage(statusCode: 500, data: Data("oops".utf8)),
            "OneDrive API 500: oops"
        )
    }
}