import XCTest
@testable import VanmoCore

final class FTPListingParserTests: XCTestCase {
    func testParsePASVAndRewriteLoopback() {
        let pasv = FTPListingParser.parsePASV(
            "227 Entering Passive Mode (127,0,0,1,195,80).",
            controlHost: "192.168.31.59"
        )
        XCTAssertEqual(pasv?.host, "192.168.31.59")
        XCTAssertEqual(pasv?.port, 195 * 256 + 80)

        let lan = FTPListingParser.parsePASV(
            "227 Entering Passive Mode (192,168,31,59,20,21).",
            controlHost: "192.168.31.59"
        )
        XCTAssertEqual(lan?.host, "192.168.31.59")
        XCTAssertEqual(lan?.port, 20 * 256 + 21)
    }

    func testParseEPSVUsesControlHost() {
        let endpoint = FTPListingParser.parseEPSV(
            "229 Entering Extended Passive Mode (|||41234|)",
            controlHost: "192.168.31.59"
        )
        XCTAssertEqual(endpoint?.host, "192.168.31.59")
        XCTAssertEqual(endpoint?.port, 41234)
    }

    func testParseUnixLIST() {
        let text = """
        total 2
        drwxr-xr-x  2 user group     4096 Jan 22 10:15 Movies
        -rw-r--r--  1 user group  1234567 Jan 22 10:15 clip.mp4
        -rw-r--r--  1 user group        0 Jan 22 10:15 .
        """
        let files = FTPListingParser.parseListing(text, directoryPath: "/")
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.name == "Movies" && $0.isDirectory && $0.path == "/Movies" })
        XCTAssertTrue(files.contains { $0.name == "clip.mp4" && !$0.isDirectory && $0.size == 1_234_567 && $0.type == .video })
    }

    func testParseWindowsLIST() {
        let text = """
        01-22-26  10:15AM       <DIR>          Movies
        01-22-26  10:15PM              1234567 clip.mp4
        """
        let files = FTPListingParser.parseListing(text, directoryPath: "/share")
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.name == "Movies" && $0.isDirectory && $0.path == "/share/Movies" })
        XCTAssertTrue(files.contains { $0.name == "clip.mp4" && $0.size == 1_234_567 && $0.path == "/share/clip.mp4" })
    }

    func testParseMLSD() {
        let text = """
        type=cdir;modify=20260122101500; .
        type=pdir;modify=20260122101500; ..
        type=dir;modify=20260122101500; Movies
        type=file;size=88;modify=20260122101500; clip.mp4
        """
        let files = FTPListingParser.parseListing(text, directoryPath: "/")
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.name == "Movies" && $0.isDirectory })
        XCTAssertTrue(files.contains { $0.name == "clip.mp4" && $0.size == 88 && $0.type == .video })
    }

    func testFTPReplyConsumesMultiline() {
        var buffer = Data("220-hello\r\n220 ready\r\n".utf8)
        let reply = FTPReply.consume(from: &buffer)
        XCTAssertEqual(reply?.code, 220)
        XCTAssertTrue(reply?.message.contains("ready") == true)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testPlaybackTargetFromFTPURL() {
        let url = URL(string: "ftp://alice:secret@192.168.31.59:21/Movies/clip.mp4")!
        guard let target = FTPService.playbackTarget(from: url) else {
            return XCTFail("expected FTP playback target")
        }
        XCTAssertEqual(target.config.host, "192.168.31.59")
        XCTAssertEqual(target.config.port, 21)
        XCTAssertEqual(target.config.username, "alice")
        XCTAssertEqual(target.config.password, "secret")
        XCTAssertEqual(target.path, "/Movies/clip.mp4")
    }

    func testFTPBrowserRootUsesConfiguredPath() {
        XCTAssertTrue(ConnectionType.ftp.usesConfiguredDirectoryRoot)
        XCTAssertEqual(ConnectionType.ftp.browserRootPath(configuredPath: nil), "/")
        XCTAssertEqual(ConnectionType.ftp.browserRootPath(configuredPath: "media"), "/media")
        XCTAssertFalse(ConnectionType.sftp.usesConfiguredDirectoryRoot)
    }

    func testStreamURLOmitsDefaultPort() throws {
        let config = ConnectionConfig(type: .ftp, host: "192.168.31.59", port: 21, username: "alice", password: "secret")
        let url = try FTPService.makeStreamURL(config: config, filePath: "/Movies/clip.mp4")
        XCTAssertEqual(url.scheme, "ftp")
        XCTAssertEqual(url.host, "192.168.31.59")
        XCTAssertEqual(url.path, "/Movies/clip.mp4")
        XCTAssertTrue(url.safePlaybackLogDescription.contains("192.168.31.59"))
        XCTAssertFalse(url.safePlaybackLogDescription.contains("secret"))
    }
}
