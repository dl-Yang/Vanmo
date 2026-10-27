import XCTest
@testable import VanmoCore

@MainActor
final class YandexDiskOAuthTests: XCTestCase {
    func testYandexDiskIsConfiguredAsPKCEPublicClient() {
        XCTAssertTrue(OAuthProviderConfiguration.isConfigured(for: .yandexDisk))
        XCTAssertTrue(OAuthProviderConfiguration.usesPKCE(for: .yandexDisk))
        XCTAssertNil(OAuthProviderConfiguration.clientSecret(for: .yandexDisk))
        XCTAssertEqual(OAuthProviderConfiguration.scope(for: .yandexDisk), "cloud_api:disk.read")
        XCTAssertEqual(OAuthProviderConfiguration.redirectURI(for: .yandexDisk), "vanmo://oauth/yandexDisk")
        XCTAssertEqual(OAuthProviderConfiguration.callbackURLScheme(for: .yandexDisk), "vanmo")
        XCTAssertFalse(OAuthProviderConfiguration.prefersEphemeralWebBrowserSession(for: .yandexDisk))
        XCTAssertTrue(OAuthProviderConfiguration.prefersEphemeralWebBrowserSession(for: .googleDrive))
    }

    func testRegisteredExternalAuthenticatorHandlesLogin() async throws {
        let coordinator = OAuthCoordinator()
        let stub = StubAuthenticator()
        coordinator.externalAuthenticators[.yandexDisk] = stub

        let credential = try await coordinator.authenticate(type: .yandexDisk)

        XCTAssertEqual(stub.requestedTypes, [.yandexDisk])
        XCTAssertEqual(credential.accessToken, "stub-token")
        XCTAssertEqual(credential.provider, .yandexDisk)
    }

    func testUnsupportedAccountTypeErrorIsReadable() {
        let body = Data(#"{"error":"DiskUnsupportedUserAccountTypeError","description":"User account type is not supported."}"#.utf8)

        let message = YandexDiskService.errorMessage(statusCode: 403, data: body)

        XCTAssertTrue(message.contains("Yandex 邮箱"))
        XCTAssertFalse(message.contains("DiskUnsupportedUserAccountTypeError"))
        XCTAssertEqual(
            YandexDiskService.errorMessage(statusCode: 500, data: Data(#"{"error":"Other"}"#.utf8)),
            #"Yandex.Disk API 500: {"error":"Other"}"#
        )
    }
}

@MainActor
private final class StubAuthenticator: OAuthExternalAuthenticator {
    private(set) var requestedTypes: [ConnectionType] = []

    func authenticate(type: ConnectionType) async throws -> OAuthCredential {
        requestedTypes.append(type)
        return OAuthCredential(
            provider: type,
            accessToken: "stub-token",
            refreshToken: "",
            expiresAt: .distantFuture,
            tokenType: "OAuth",
            scope: nil,
            apiHost: nil
        )
    }
}
