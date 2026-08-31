import XCTest
@testable import VanmoCore

final class SFTPServiceTests: XCTestCase {
    func testNormalizeAndJoinPaths() {
        XCTAssertEqual(SFTPPath.normalize(""), "/")
        XCTAssertEqual(SFTPPath.normalize("media"), "/media")
        XCTAssertEqual(SFTPPath.normalize("/media/"), "/media")
        XCTAssertEqual(SFTPPath.join("/", name: "clip.mp4"), "/clip.mp4")
        XCTAssertEqual(SFTPPath.join("/media", name: "clip.mp4"), "/media/clip.mp4")
        XCTAssertFalse(SFTPPath.isListableName("."))
        XCTAssertFalse(SFTPPath.isListableName(".."))
        XCTAssertTrue(SFTPPath.isListableName("clip.mp4"))
    }

    func testDirectoryDetectionUsesPOSIXTypeBits() {
        XCTAssertTrue(SFTPPath.isDirectory(permissions: 0o040755, longname: "-rw-r--r--"))
        XCTAssertFalse(SFTPPath.isDirectory(permissions: 0o100644, longname: "drwxr-xr-x"))
        XCTAssertTrue(SFTPPath.isDirectory(permissions: nil, longname: "drwxr-xr-x 2 user"))
        XCTAssertFalse(SFTPPath.isDirectory(permissions: nil, longname: "-rw-r--r-- 1 user"))
    }

    func testPlaybackTargetFromSFTPURL() {
        let url = URL(string: "sftp://alice:secret@192.168.31.59:2222/Movies/clip.mp4")!
        guard let target = SFTPService.playbackTarget(from: url) else {
            return XCTFail("expected playback target")
        }
        XCTAssertEqual(target.config.host, "192.168.31.59")
        XCTAssertEqual(target.config.port, 2222)
        XCTAssertEqual(target.config.username, "alice")
        XCTAssertEqual(target.config.password, "secret")
        XCTAssertEqual(target.path, "/Movies/clip.mp4")
    }

    func testPlaybackTargetRejectsFTP() {
        let url = URL(string: "ftp://alice:secret@192.168.31.59/Movies/clip.mp4")!
        XCTAssertNil(SFTPService.playbackTarget(from: url))
    }

    func testStreamURLOmitsDefaultPort() throws {
        let config = ConnectionConfig(
            type: .sftp,
            host: "192.168.31.59",
            port: 22,
            username: "alice",
            password: "secret"
        )
        let url = try SFTPService.makeStreamURL(config: config, filePath: "/Movies/clip.mp4")
        XCTAssertEqual(url.scheme, "sftp")
        XCTAssertEqual(url.host, "192.168.31.59")
        XCTAssertNil(url.port)
        XCTAssertEqual(url.path, "/Movies/clip.mp4")
        XCTAssertEqual(url.user, "alice")
        XCTAssertEqual(url.password, "secret")
    }

    func testStreamURLIncludesNonDefaultPort() throws {
        let config = ConnectionConfig(
            type: .sftp,
            host: "sftp://alice@192.168.31.59:2222",
            port: 2222,
            username: "alice",
            password: "secret"
        )
        let url = try SFTPService.makeStreamURL(config: config, filePath: "Movies/Jinx League.mp4")
        XCTAssertEqual(url.host, "192.168.31.59")
        XCTAssertEqual(url.port, 2222)
        XCTAssertEqual(url.path, "/Movies/Jinx League.mp4")
    }
}
