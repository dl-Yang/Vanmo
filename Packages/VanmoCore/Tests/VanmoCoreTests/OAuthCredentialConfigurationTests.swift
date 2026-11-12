import XCTest
@testable import VanmoCore

final class OAuthCredentialConfigurationTests: XCTestCase {
    func testReadsEachProviderFromInfoCredentials() {
        let credentials: [String: Any] = [
            "GoogleDriveClientID": "g.apps.googleusercontent.com",
            "OneDriveClientID": "one",
            "BoxClientID": "box-id",
            "BoxClientSecret": "box-secret",
            "PCloudClientID": "pc-id",
            "PCloudClientSecret": "pc-secret",
            "YandexDiskClientID": "yx",
            "BaiduNetdiskAppKey": "baidu",
        ]

        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .googleDrive, in: credentials), "g.apps.googleusercontent.com")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .oneDrive, in: credentials), "one")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .box, in: credentials), "box-id")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .pCloudDrive, in: credentials), "pc-id")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .yandexDisk, in: credentials), "yx")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .baiduNetdisk, in: credentials), "baidu")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .smb, in: credentials), "")
        XCTAssertEqual(OAuthProviderConfiguration.clientSecret(for: .box, in: credentials), "box-secret")
        XCTAssertEqual(OAuthProviderConfiguration.clientSecret(for: .pCloudDrive, in: credentials), "pc-secret")
        XCTAssertNil(OAuthProviderConfiguration.clientSecret(for: .oneDrive, in: credentials))
    }

    func testEmptyWhitespaceAndUnexpandedValuesCountAsMissing() {
        let credentials: [String: Any] = [
            "BoxClientID": "  box-id \n",
            "BoxClientSecret": "   ",
            "OneDriveClientID": "$(VANMO_ONEDRIVE_CLIENT_ID)",
            "YandexDiskClientID": 42,
        ]

        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .box, in: credentials), "box-id")
        XCTAssertNil(OAuthProviderConfiguration.clientSecret(for: .box, in: credentials))
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .oneDrive, in: credentials), "")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .yandexDisk, in: credentials), "")
        XCTAssertEqual(OAuthProviderConfiguration.clientID(for: .googleDrive, in: [:]), "")
    }

    func testTestProcessHasNoBundledCredentials() {
        XCTAssertTrue(OAuthProviderConfiguration.bundledCredentials.isEmpty)
        XCTAssertFalse(OAuthProviderConfiguration.isConfigured(for: .box))
    }
}
