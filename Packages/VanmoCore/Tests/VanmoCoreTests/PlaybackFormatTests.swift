import XCTest
@testable import VanmoCore

final class PlaybackFormatTests: XCTestCase {
    func testSMBMP4UsesFFmpegPath() {
        let url = URL(string: "smb://user:secret@192.168.1.10/share/movie.mp4")!
        XCTAssertEqual(SupportedFormat.detect(from: url), .ffmpeg)
        XCTAssertTrue(url.usesSMBScheme)
    }

    func testLocalMP4StaysNative() {
        let url = URL(fileURLWithPath: "/tmp/movie.mp4")
        XCTAssertEqual(SupportedFormat.detect(from: url), .native)
        XCTAssertFalse(url.usesSMBScheme)
    }

    func testSafePlaybackLogStripsUserInfo() {
        let url = URL(string: "smb://user:secret@192.168.1.10/share/movie.mp4")!
        XCTAssertEqual(
            url.safePlaybackLogDescription,
            "smb://192.168.1.10/share/movie.mp4"
        )
        XCTAssertFalse(url.safePlaybackLogDescription.contains("secret"))
        XCTAssertFalse(url.safePlaybackLogDescription.contains("user:"))
    }

    func testPlaybackTargetFromSMBURL() {
        let url = URL(string: "smb://alice:secret@192.168.1.10/yinguSMB/Jinx%20League%20of%20Legends.mp4")!
        guard let target = SMBConnectionEndpoint.playbackTarget(from: url) else {
            return XCTFail("expected playback target")
        }
        XCTAssertEqual(target.config.host, "192.168.1.10")
        XCTAssertEqual(target.config.port, 445)
        XCTAssertEqual(target.config.username, "alice")
        XCTAssertEqual(target.config.password, "secret")
        XCTAssertEqual(target.config.path, "/yinguSMB")
        XCTAssertEqual(target.path, "/yinguSMB/Jinx League of Legends.mp4")
    }

    func testPlaybackTargetRejectsHTTP() {
        let url = URL(string: "https://example.com/movie.mp4")!
        XCTAssertNil(SMBConnectionEndpoint.playbackTarget(from: url))
    }
}
