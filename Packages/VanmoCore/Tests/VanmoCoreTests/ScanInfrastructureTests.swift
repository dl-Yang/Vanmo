import XCTest
@testable import VanmoCore

final class PlaybackURLResolverTests: XCTestCase {
    func testDetectsCatalogPlaceholder() {
        let url = ConnectionType.googleDrive.catalogPlaybackURL(serverPath: "/Movies/a.mkv")
        XCTAssertTrue(PlaybackURLResolver.isPlaceholder(url))
    }

    func testStorageURLUsesCatalogForLazyProtocols() {
        let file = RemoteFile(
            name: "a.mkv",
            path: "/a.mkv",
            size: 100,
            isDirectory: false,
            modifiedDate: nil,
            type: .video
        )
        let service = StubRemoteService(type: .googleDrive)
        let url = PlaybackURLResolver.storageURL(for: file, service: service)
        XCTAssertTrue(PlaybackURLResolver.isPlaceholder(url))
        XCTAssertEqual(url.host, "playback")
    }

    func testResolvePlaybackURLUsesServiceStreamURLForPlaceholder() async throws {
        let item = MediaItem(
            title: "Demo",
            fileURL: ConnectionType.webdav.catalogPlaybackURL(serverPath: "/Movies/a.mkv"),
            mediaType: .movie,
            fileSize: 100
        )
        item.serverId = "/Movies/a.mkv"
        item.originalFileName = "a.mkv"

        let service = StubRemoteService(type: .webdav)
        let resolved = try await PlaybackURLResolver.resolvePlaybackURL(item: item, service: service)
        XCTAssertEqual(resolved.absoluteString, "https://example.com/Movies/a.mkv")
    }
}

final class RemoteServiceCapabilitiesTests: XCTestCase {
    func testGoogleDriveDeclaresLazyPlaybackAndPagination() {
        let caps = ConnectionType.googleDrive.serviceCapabilities
        XCTAssertEqual(caps.listing, .paginated)
        XCTAssertEqual(caps.playbackPersistence, .catalogPlaceholder)
        XCTAssertTrue(ConnectionType.googleDrive.requiresLazyPlaybackURL)
    }

    func testWebDAVUsesStableDirectURLCapability() {
        let caps = ConnectionType.webdav.serviceCapabilities
        XCTAssertEqual(caps.playbackPersistence, .stableDirectURL)
        XCTAssertFalse(ConnectionType.webdav.requiresLazyPlaybackURL)
    }

    func testAListBrowserRootUsesConfiguredDavPath() {
        XCTAssertTrue(ConnectionType.alist.usesConfiguredDirectoryRoot)
        XCTAssertEqual(ConnectionType.alist.browserRootPath(configuredPath: "/dav"), "/dav")
        XCTAssertEqual(ConnectionType.alist.browserRootPath(configuredPath: "dav"), "/dav")
        XCTAssertEqual(ConnectionType.smb.browserRootPath(configuredPath: "/share"), "/")
    }

    func testWebDAVListingRootUsesMountPath() {
        XCTAssertEqual(WebDAVService.resolvedListingPath("/", mountPath: "/dav"), "/dav")
        XCTAssertEqual(WebDAVService.resolvedListingPath("", mountPath: "/dav"), "/dav")
        XCTAssertEqual(WebDAVService.resolvedListingPath("/dav/Movies", mountPath: "/dav"), "/dav/Movies")
        XCTAssertEqual(WebDAVService.resolvedListingPath("/", mountPath: nil), "/")
    }
}

private final class StubRemoteService: RemoteFileService {
    let type: ConnectionType
    var isConnected = true

    init(type: ConnectionType) {
        self.type = type
    }

    func connect(config: ConnectionConfig) async throws {}
    func disconnect() async {}
    func listDirectory(path: String) async throws -> [RemoteFile] { [] }
    func streamURL(for file: RemoteFile) async throws -> URL {
        URL(string: "https://example.com\(file.path)")!
    }
    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {}
}
