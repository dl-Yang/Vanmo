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

final class StreamingRequestHeadersTests: XCTestCase {
    func testGoogleDriveAndBaiduDeclareProviders() async {
        XCTAssertNotNil(StreamingRequestHeaders.provider(for: .googleDrive, connectionId: UUID()))
        let baidu = StreamingRequestHeaders.provider(for: .baiduNetdisk, connectionId: UUID())
        XCTAssertNotNil(baidu)
        let headers = await baidu!()
        XCTAssertEqual(headers["User-Agent"], BaiduNetdiskService.requiredUserAgent)
    }

    func testFileServersDoNotDeclareStreamingHeaders() {
        XCTAssertNil(StreamingRequestHeaders.provider(for: .smb, connectionId: UUID()))
        XCTAssertNil(StreamingRequestHeaders.provider(for: .webdav, connectionId: UUID()))
    }

    func testBaiduUsesOfficialDownloadLink() {
        XCTAssertTrue(ConnectionType.baiduNetdisk.usesOfficialDownloadLink)
        XCTAssertFalse(ConnectionType.googleDrive.usesOfficialDownloadLink)
        XCTAssertFalse(ConnectionType.smb.usesOfficialDownloadLink)
    }

    func testOfficialPosterSourceLeavesKeyframeSourcesAlone() async {
        let result = await OfficialPosterSource.resolve(
            type: .googleDrive,
            connectionId: UUID(),
            path: "/file/1",
            password: nil
        )
        if case .useKeyframe = result {
            return
        }
        XCTFail("Google Drive should keep keyframe extraction")
    }
}

final class BaiduFileMetaParserTests: XCTestCase {
    func testPrefersLargestOfficialThumb() {
        let url = BaiduFileMetaParser.preferredThumbnailURL(
            icon: "https://example.com/icon.jpg",
            url1: "https://example.com/url1.jpg",
            url2: "https://example.com/url2.jpg",
            url3: "https://example.com/url3.jpg"
        )
        XCTAssertEqual(url?.absoluteString, "https://example.com/url3.jpg")
    }

    func testFallsBackWhenLargerThumbsMissing() {
        let url = BaiduFileMetaParser.preferredThumbnailURL(
            icon: "https://example.com/icon.jpg",
            url1: nil,
            url2: "",
            url3: nil
        )
        XCTAssertEqual(url?.absoluteString, "https://example.com/icon.jpg")
    }

    func testParsesThumbsFromFilemetasJSON() throws {
        let json = """
        {
          "errno": 0,
          "list": [
            {
              "fs_id": 123,
              "dlink": "https://d.pcs.baidu.com/file/abc",
              "thumbs": {
                "icon": "https://example.com/icon.jpg",
                "url1": "https://example.com/url1.jpg",
                "url2": "https://example.com/url2.jpg",
                "url3": "https://example.com/url3.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let url = try BaiduFileMetaParser.preferredThumbnailURL(fromFilemetasJSON: json)
        XCTAssertEqual(url?.absoluteString, "https://example.com/url3.jpg")
    }

    func testCategoryListStopsWhenHasMoreIsZero() throws {
        let json = """
        {
          "errno": 0,
          "has_more": 0,
          "cursor": 2,
          "list": [
            {
              "fs_id": 1,
              "path": "/Movies/a.mkv",
              "server_filename": "a.mkv",
              "size": 10,
              "isdir": 0,
              "category": 1
            },
            {
              "fs_id": 2,
              "path": "/Movies/Season",
              "server_filename": "Season",
              "size": 0,
              "isdir": 1
            }
          ]
        }
        """.data(using: .utf8)!
        let page = try BaiduCategoryListParser.page(fromJSON: json)
        XCTAssertEqual(page.videos, 1)
        XCTAssertEqual(page.directories, 1)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextStart)
    }

    func testCategoryListUsesCursorAndRejectsUnchangedStart() {
        XCTAssertEqual(
            BaiduCategoryListParser.nextStart(currentStart: 0, cursor: 1000, returned: 1000, hasMore: true),
            1000
        )
        XCTAssertNil(
            BaiduCategoryListParser.nextStart(currentStart: 0, cursor: 0, returned: 1000, hasMore: true)
        )
        XCTAssertNil(
            BaiduCategoryListParser.nextStart(currentStart: 0, cursor: 1000, returned: 1000, hasMore: false)
        )
    }

    func testDetectsFrequencyLimitFromHTTP400Body() {
        let json = """
        {"errmsg":"hit frequency limit","errno":31034,"request_id":"1"}
        """.data(using: .utf8)!
        XCTAssertTrue(BaiduFrequencyLimit.containsLimit(in: json))
        XCTAssertTrue(
            BaiduFrequencyLimit.isLimit(NetworkError.transferFailed("百度网盘 API 31034: hit frequency limit"))
        )
        XCTAssertFalse(BaiduFrequencyLimit.containsLimit(in: Data(#"{"errno":0}"#.utf8)))
        let coincidental = """
        {"errno":0,"request_id":"31034","list":[{"fs_id":31034}]}
        """.data(using: .utf8)!
        XCTAssertFalse(BaiduFrequencyLimit.containsLimit(in: coincidental))
    }

    func testBaiduScanRateIsSerialized() {
        let caps = ConnectionType.baiduNetdisk.serviceCapabilities
        XCTAssertEqual(caps.maxConcurrentDirectoryReads, 1)
        XCTAssertEqual(caps.requestsPerSecond, 1, accuracy: 0.01)
    }

    func testFilemetasWithoutThumbsReturnsNil() throws {
        let json = """
        {
          "errno": 0,
          "list": [
            { "fs_id": 123, "dlink": "https://d.pcs.baidu.com/file/abc" }
          ]
        }
        """.data(using: .utf8)!
        XCTAssertNil(try BaiduFileMetaParser.preferredThumbnailURL(fromFilemetasJSON: json))
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
