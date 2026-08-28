import XCTest
@testable import VanmoCore

final class SMBConnectionTests: XCTestCase {
    func testParsesPlainHostAndDefaultPort() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "192.168.1.10",
            port: 445,
            username: "alice",
            path: nil
        )
        XCTAssertEqual(endpoint.host, "192.168.1.10")
        XCTAssertEqual(endpoint.port, 445)
        XCTAssertNil(endpoint.share)
        XCTAssertEqual(endpoint.username, "alice")
        XCTAssertNil(endpoint.domain)
        XCTAssertEqual(endpoint.rootBrowsePath, "/")
    }

    func testParsesSMBURLWithShareAndEmbeddedPort() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "smb://192.168.1.10:139/media/movies",
            port: 445,
            username: "alice",
            path: nil
        )
        XCTAssertEqual(endpoint.host, "192.168.1.10")
        XCTAssertEqual(endpoint.port, 139)
        XCTAssertEqual(endpoint.share, "media")
        XCTAssertEqual(endpoint.initialSubpath, "movies")
        XCTAssertEqual(endpoint.rootBrowsePath, "/media/movies")
    }

    func testParsesUNCPath() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: #"\\NAS\Movies"#,
            port: 445,
            username: "alice",
            path: nil
        )
        XCTAssertEqual(endpoint.host, "NAS")
        XCTAssertEqual(endpoint.share, "Movies")
        XCTAssertNil(endpoint.initialSubpath)
        XCTAssertEqual(endpoint.rootBrowsePath, "/Movies")
    }

    func testFormPathOverridesHostShare() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "smb://192.168.1.10/media",
            port: 445,
            username: "alice",
            path: "/Shows/Kids"
        )
        XCTAssertEqual(endpoint.host, "192.168.1.10")
        XCTAssertEqual(endpoint.share, "Shows")
        XCTAssertEqual(endpoint.initialSubpath, "Kids")
        XCTAssertEqual(endpoint.rootBrowsePath, "/Shows/Kids")
    }

    func testParsesHostWithInlineShare() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "192.168.1.10/media",
            port: 445,
            username: nil,
            path: nil
        )
        XCTAssertEqual(endpoint.host, "192.168.1.10")
        XCTAssertEqual(endpoint.share, "media")
    }

    func testParsesDomainBackslashUsername() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "nas.local",
            port: 445,
            username: #"CORP\alice"#,
            path: nil
        )
        XCTAssertEqual(endpoint.username, "alice")
        XCTAssertEqual(endpoint.domain, "CORP")
    }

    func testParsesWorkgroupAtUsername() {
        let account = SMBConnectionEndpoint.parseAccount("alice@WORKGROUP")
        XCTAssertEqual(account.username, "alice")
        XCTAssertEqual(account.domain, "WORKGROUP")
    }

    func testDoesNotTreatEmailOrHostAsDomain() {
        let email = SMBConnectionEndpoint.parseAccount("alice@nas.local")
        XCTAssertEqual(email.username, "alice@nas.local")
        XCTAssertNil(email.domain)

        let ipv4 = SMBConnectionEndpoint.parseAccount("alice@192.168.1.10")
        XCTAssertEqual(ipv4.username, "alice@192.168.1.10")
        XCTAssertNil(ipv4.domain)
    }

    func testEmptyAccountBecomesGuest() {
        let account = SMBConnectionEndpoint.parseAccount("  ")
        XCTAssertNil(account.username)
        XCTAssertNil(account.domain)
    }

    func testSplitSharePath() {
        let nested = SMBConnectionEndpoint.splitSharePath("/share/a/b/c")
        XCTAssertEqual(nested.share, "share")
        XCTAssertEqual(nested.subpath, "a/b/c")

        let root = SMBConnectionEndpoint.splitSharePath("/share")
        XCTAssertEqual(root.share, "share")
        XCTAssertEqual(root.subpath, "")

        let empty = SMBConnectionEndpoint.splitSharePath("/")
        XCTAssertEqual(empty.share, "")
        XCTAssertEqual(empty.subpath, "")
    }

    func testHidesIPCAndAdminShares() {
        XCTAssertTrue(SMBShareListingPolicy.isHiddenSystemShare(name: "IPC$", isIPC: true))
        XCTAssertTrue(SMBShareListingPolicy.isHiddenSystemShare(name: "C$", isIPC: false))
        XCTAssertTrue(SMBShareListingPolicy.isHiddenSystemShare(name: ".", isIPC: false))
        XCTAssertFalse(SMBShareListingPolicy.isHiddenSystemShare(name: "Movies", isIPC: false))
    }

    func testTreatsAccessDeniedAsUnreadable() {
        XCTAssertTrue(SMBShareListingPolicy.isUnreadable(NetworkError.authenticationFailed))
        XCTAssertTrue(SMBShareListingPolicy.isUnreadable(
            NSError(domain: "smb", code: 1, userInfo: [NSLocalizedDescriptionKey: "Access Denied"])
        ))
        XCTAssertTrue(SMBShareListingPolicy.isUnreadable(
            NSError(domain: "smb", code: 2, userInfo: [NSLocalizedDescriptionKey: "Logon Failure"])
        ))
        XCTAssertFalse(SMBShareListingPolicy.isUnreadable(
            NSError(domain: "smb", code: 3, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
        ))
    }

    func testFallbackShareNamesPrefersUsernameAndDeduplicates() {
        XCTAssertEqual(
            SMBShareListingPolicy.fallbackShareNames(username: "yingu"),
            ["yingu", "homes", "home", "Public", "media"]
        )
        XCTAssertEqual(
            SMBShareListingPolicy.fallbackShareNames(username: "home"),
            ["home", "homes", "Public", "media"]
        )
    }

    func testSharePathRequiredMessage() {
        XCTAssertEqual(
            NetworkError.sharePathRequired.localizedDescription,
            "已登录，但服务器不允许列出共享。请编辑连接并在路径中填写共享名（例如 /Movies）。"
        )
    }

    func testFiltersUnreadableShareNames() {
        let candidates = ["Movies", "IPC$", "Secret", "C$"]
        let readable = Set(["Movies"])
        let visible = candidates.filter { name in
            !SMBShareListingPolicy.isHiddenSystemShare(name: name, isIPC: name == "IPC$")
                && readable.contains(name)
        }
        XCTAssertEqual(visible, ["Movies"])
    }

    func testConnectionHostsIncludeReverseLookupForIPv4() {
        let hosts = SMBConnectionEndpoint.connectionHosts(for: "127.0.0.1")
        XCTAssertEqual(hosts.first, "127.0.0.1")
        XCTAssertTrue(SMBConnectionEndpoint.isIPv4("192.168.1.77"))
        XCTAssertFalse(SMBConnectionEndpoint.isIPv4("nas.local"))
    }

    func testBonjourServiceNameBecomesLocalHost() {
        XCTAssertEqual(
            SMBConnectionEndpoint.localHostname(fromBonjourService: "yingudeMacBook-Air"),
            "yingudeMacBook-Air.local"
        )
        XCTAssertEqual(
            SMBConnectionEndpoint.localHostname(fromBonjourService: "nas.local"),
            "nas.local"
        )
        XCTAssertNil(SMBConnectionEndpoint.localHostname(fromBonjourService: "银古的MacBook Air"))
        XCTAssertNil(SMBConnectionEndpoint.localHostname(fromBonjourService: "  "))
    }

    func testReplacingHostKeepsShareAndAccount() {
        let endpoint = SMBConnectionEndpoint.parse(
            host: "192.168.1.77",
            port: 445,
            username: "alice",
            path: "/yinguSMB"
        ).replacingHost("nas.local")
        XCTAssertEqual(endpoint.host, "nas.local")
        XCTAssertEqual(endpoint.share, "yinguSMB")
        XCTAssertEqual(endpoint.username, "alice")
    }

    func testBracketedIPv6HostAndPort() {
        let parsed = SMBConnectionEndpoint.parseHostAndPort("[fe80::1]:445")
        XCTAssertEqual(parsed.host, "fe80::1")
        XCTAssertEqual(parsed.port, 445)
    }
}
