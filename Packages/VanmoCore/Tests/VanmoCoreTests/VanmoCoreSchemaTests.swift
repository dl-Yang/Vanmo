import XCTest
@testable import VanmoCore

final class VanmoCoreSchemaTests: XCTestCase {
    func testMediaTypeRawValues() {
        XCTAssertEqual(MediaType.movie.rawValue, "movie")
        XCTAssertEqual(MediaType.tvShow.rawValue, "tvShow")
        XCTAssertEqual(MediaType.tvEpisode.rawValue, "tvEpisode")
    }

    func testConnectionTypeDefaults() {
        XCTAssertEqual(ConnectionType.smb.defaultPort, 445)
        XCTAssertEqual(ConnectionType.webdav.defaultPort, 80)
        XCTAssertTrue(ConnectionType.googleDrive.supportsOAuthLogin)
        XCTAssertFalse(ConnectionType.smb.supportsOAuthLogin)
        XCTAssertTrue(ConnectionType.googleDrive.requiresManualDirectorySync)
        XCTAssertTrue(ConnectionType.baiduNetdisk.requiresManualDirectorySync)
        XCTAssertTrue(ConnectionType.smb.requiresManualDirectorySync)
        XCTAssertTrue(ConnectionType.webdav.requiresManualDirectorySync)
        XCTAssertTrue(ConnectionType.localFolder.requiresManualDirectorySync)
        XCTAssertFalse(ConnectionType.emby.requiresManualDirectorySync)
        XCTAssertFalse(ConnectionType.jellyfin.requiresManualDirectorySync)
        XCTAssertFalse(ConnectionType.plex.requiresManualDirectorySync)
        XCTAssertFalse(ConnectionType.iptv.requiresManualDirectorySync)
        XCTAssertFalse(ConnectionType.dlna.requiresManualDirectorySync)
    }

    func testRemoteFileTypeFromFilename() {
        XCTAssertEqual(RemoteFileType.from(filename: "movie.mkv"), .video)
        XCTAssertEqual(RemoteFileType.from(filename: "subtitle.srt"), .subtitle)
        XCTAssertEqual(RemoteFileType.from(filename: "readme.txt"), .other)
    }

    func testSubtitleFormatDetection() {
        let srtURL = URL(fileURLWithPath: "/tmp/sample.srt")
        let vttURL = URL(fileURLWithPath: "/tmp/sample.vtt")
        let assURL = URL(fileURLWithPath: "/tmp/sample.ass")

        XCTAssertEqual(SubtitleFormat.detect(from: srtURL), .srt)
        XCTAssertEqual(SubtitleFormat.detect(from: vttURL), .vtt)
        XCTAssertEqual(SubtitleFormat.detect(from: assURL), .ass)
        XCTAssertTrue(SubtitleFormat.ass.isRichTextFormat)
        XCTAssertFalse(SubtitleFormat.srt.isRichTextFormat)
    }

    @MainActor
    func testServerMediaItemMapperPreservesMediaType() {
        let item = ServerMediaItemMapper.makeMediaItem(from: ServerMediaItem(
            serverId: "abc",
            title: "Test Movie",
            mediaType: .movie,
            streamURL: URL(string: "https://example.com/stream")!,
            fileSize: 1024,
            duration: 3600
        ))
        XCTAssertEqual(item.mediaType, .movie)
        XCTAssertEqual(item.serverId, "abc")
    }
}
