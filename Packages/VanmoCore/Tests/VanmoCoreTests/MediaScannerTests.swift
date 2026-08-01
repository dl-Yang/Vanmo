import XCTest
import SwiftData
@testable import VanmoCore

final class FileNameParserTests: XCTestCase {
    func testParsesMovieWithYear() {
        let parsed = FileNameParser.parse("Inception.2010.1080p.BluRay.x264.mkv")
        XCTAssertEqual(parsed.title, "Inception")
        XCTAssertEqual(parsed.year, 2010)
        XCTAssertFalse(parsed.isTV)
    }

    func testParsesStandardEpisode() {
        let parsed = FileNameParser.parse("Breaking.Bad.S01E02.720p.mkv")
        XCTAssertTrue(parsed.isTV)
        XCTAssertEqual(parsed.season, 1)
        XCTAssertEqual(parsed.episode, 2)
        XCTAssertEqual(parsed.title, "Breaking Bad")
    }

    func testParsesChineseEpisode() {
        let parsed = FileNameParser.parse("庆余年.第01集.1080p.mp4")
        XCTAssertTrue(parsed.isTV)
        XCTAssertEqual(parsed.episode, 1)
    }

    func testParsesAnimeBracketEpisode() {
        let parsed = FileNameParser.parse("Demo.Anime.[12].mkv")
        XCTAssertTrue(parsed.isTV)
        XCTAssertEqual(parsed.episode, 12)
    }

    func testIgnoresSampleInPipeline() {
        let result = MediaIdentificationPipeline.identify(
            fileName: "Movie.2020.1080p.sample.mkv",
            directoryPath: "/Movies"
        )
        XCTAssertNil(result)
    }
}

final class DirectorySemanticsTests: XCTestCase {
    func testMovieFolderSemantics() {
        let semantics = DirectorySemanticsParser.parse(directoryPath: "/Media/Movies/Inception (2010)")
        XCTAssertEqual(semantics?.kind, .movieRoot)
        XCTAssertEqual(semantics?.title, "Inception")
        XCTAssertEqual(semantics?.year, 2010)
    }

    func testTVSeasonFolderSemantics() {
        let semantics = DirectorySemanticsParser.parse(directoryPath: "/TV/Breaking Bad/Season 01")
        XCTAssertEqual(semantics?.kind, .tvSeason)
        XCTAssertEqual(semantics?.showTitle, "Breaking Bad")
        XCTAssertEqual(semantics?.season, 1)
    }
}

final class NFOMetadataParserTests: XCTestCase {
    func testParsesMovieNFOWithTMDBID() {
        let xml = """
        <movie>
            <title>Test Movie</title>
            <year>2020</year>
            <plot>Overview text</plot>
            <uniqueid type="tmdb" default="true">12345</uniqueid>
        </movie>
        """.data(using: .utf8)!

        let parsed = NFOMetadataParser.parse(data: xml, fileName: "movie.nfo")
        XCTAssertEqual(parsed?.title, "Test Movie")
        XCTAssertEqual(parsed?.year, 2020)
        XCTAssertEqual(parsed?.overview, "Overview text")
        XCTAssertEqual(parsed?.tmdbID, 12345)
        XCTAssertEqual(parsed?.kind, .movie)
    }

    func testSameNameMovieNFONotTreatedAsEpisode() {
        let xml = """
        <movie>
            <title>Inception</title>
            <year>2010</year>
        </movie>
        """.data(using: .utf8)!

        let parsed = NFOMetadataParser.parse(data: xml, fileName: "Inception.nfo")
        XCTAssertEqual(parsed?.kind, .movie)
        XCTAssertEqual(parsed?.title, "Inception")
    }

    func testParsesYearFromPremieredDate() {
        let xml = """
        <movie>
            <title>Demo</title>
            <premiered>2010-07-16</premiered>
        </movie>
        """.data(using: .utf8)!

        let parsed = NFOMetadataParser.parse(data: xml, fileName: "Demo.nfo")
        XCTAssertEqual(parsed?.year, 2010)
    }
}

final class MediaItemFactoryTests: XCTestCase {
    func testRemoteFileChangedDetectsModificationDate() {
        let item = MediaItem(title: "A", fileURL: URL(string: "file:///a.mkv")!, mediaType: .movie)
        item.originalFileName = "a.mkv"
        item.fileSize = 100
        item.remoteModifiedAt = Date(timeIntervalSince1970: 100)

        let unchanged = RemoteFile(
            name: "a.mkv",
            path: "/a.mkv",
            size: 100,
            isDirectory: false,
            modifiedDate: Date(timeIntervalSince1970: 100),
            type: .video
        )
        XCTAssertFalse(MediaItemFactory.remoteFileChanged(existing: item, file: unchanged, forceFullScan: false))

        let changed = RemoteFile(
            name: "a.mkv",
            path: "/a.mkv",
            size: 200,
            isDirectory: false,
            modifiedDate: Date(timeIntervalSince1970: 200),
            type: .video
        )
        XCTAssertTrue(MediaItemFactory.remoteFileChanged(existing: item, file: changed, forceFullScan: false))
    }

    func testApplyRemoteFileMetadataUpdatesURLAndSize() {
        let item = MediaItem(
            title: "Old",
            fileURL: URL(string: "https://example.com/old.mkv")!,
            mediaType: .movie,
            fileSize: 100
        )
        item.originalFileName = "Movie.2020.mkv"
        item.remoteModifiedAt = Date(timeIntervalSince1970: 100)

        let file = RemoteFile(
            name: "Movie.2020.mkv",
            path: "/Movies/Movie.2020.mkv",
            size: 500,
            isDirectory: false,
            modifiedDate: Date(timeIntervalSince1970: 200),
            type: .video
        )
        let newURL = URL(string: "https://example.com/new.mkv")!

        MediaItemFactory.applyRemoteFileMetadata(
            file,
            streamURL: newURL,
            connectionId: UUID(),
            directoryPath: "/Movies",
            nfoByFileName: [:],
            to: item
        )

        XCTAssertEqual(item.fileURL, newURL)
        XCTAssertEqual(item.fileSize, 500)
        XCTAssertEqual(item.remoteModifiedAt, file.modifiedDate)
        XCTAssertFalse(MediaItemFactory.remoteFileChanged(existing: item, file: file, forceFullScan: false))
    }

    func testIdentificationUsesDirectoryAndFilename() {
        let file = RemoteFile(
            name: "Breaking.Bad.S01E02.mkv",
            path: "/TV/Breaking Bad/Season 01/Breaking.Bad.S01E02.mkv",
            size: 1_000,
            isDirectory: false,
            modifiedDate: nil,
            type: .video
        )

        let item = MediaItemFactory.makeMediaItem(
            from: file,
            streamURL: URL(string: "file:///tv.mkv")!,
            connectionId: UUID(),
            directoryPath: "/TV/Breaking Bad/Season 01"
        )

        XCTAssertEqual(item?.mediaType, .tvEpisode)
        XCTAssertEqual(item?.showTitle, "Breaking Bad")
        XCTAssertEqual(item?.seasonNumber, 1)
        XCTAssertEqual(item?.episodeNumber, 2)
    }
}

@MainActor
final class MediaScannerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func testIncrementalScanSkipsUnchangedItems() async throws {
        let connectionId = UUID()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let service = MockRemoteFileService(filesByDirectory: [
            "/": [
                mockVideo(path: "/movie.mkv", name: "Movie.2020.mkv", size: 500, modified: modified)
            ]
        ])

        let scanner = MediaScanner(modelContainer: container)
        let first = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )
        XCTAssertEqual(first.insertedItems.count, 1)
        XCTAssertEqual(first.status, .completed)

        let second = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )
        XCTAssertEqual(second.insertedItems.count, 0)
        XCTAssertEqual(second.unchangedCount, 1)
    }

    func testFullScanPrunesMissingItems() async throws {
        let connectionId = UUID()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        var files: [String: [RemoteFile]] = [
            "/": [
                mockVideo(path: "/a.mkv", name: "A.mkv", size: 100, modified: modified),
                mockVideo(path: "/b.mkv", name: "B.mkv", size: 100, modified: modified),
            ]
        ]
        let service = MockRemoteFileService(filesByDirectory: files)

        let scanner = MediaScanner(modelContainer: container)
        _ = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )

        files["/"] = [mockVideo(path: "/a.mkv", name: "A.mkv", size: 100, modified: modified)]
        service.filesByDirectory = files

        let result = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )

        XCTAssertEqual(result.prunedCount, 1)
        let remaining = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.serverId, "/a.mkv")
    }

    func testPartialScanDoesNotPrune() async throws {
        let connectionId = UUID()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let service = MockRemoteFileService(filesByDirectory: [
            "/": [mockVideo(path: "/a.mkv", name: "A.mkv", size: 100, modified: modified)],
            "/sub": [mockVideo(path: "/sub/c.mkv", name: "C.mkv", size: 100, modified: modified)],
        ])

        let scanner = MediaScanner(modelContainer: container)
        _ = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )

        let partial = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/sub",
            connectionId: connectionId,
            in: context,
            options: .forPartialDirectory()
        )

        XCTAssertEqual(partial.prunedCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MediaItem>()).count, 2)
    }

    func testFailedDirectoryPreventsPrune() async throws {
        let connectionId = UUID()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let service = MockRemoteFileService(
            filesByDirectory: [
                "/": [
                    mockVideo(path: "/a.mkv", name: "A.mkv", size: 100, modified: modified),
                    mockVideo(path: "/b.mkv", name: "B.mkv", size: 100, modified: modified),
                ]
            ]
        )

        let scanner = MediaScanner(modelContainer: container)
        _ = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )

        service.filesByDirectory["/"] = [
            mockVideo(path: "/a.mkv", name: "A.mkv", size: 100, modified: modified),
            RemoteFile(name: "bad", path: "/bad", size: 0, isDirectory: true, modifiedDate: nil, type: .directory),
        ]
        service.failingPaths = ["/bad"]

        let result = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false)
        )

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.prunedCount, 0)
        let remaining = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(remaining.count, 2)
    }

    func testScanPersistsCatalogURLWithoutCallingStreamURL() async throws {
        let connectionId = UUID()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let service = MockRemoteFileService(filesByDirectory: [
            "/": [
                mockVideo(path: "/movie.mkv", name: "Movie.2020.mkv", size: 500, modified: modified)
            ]
        ])

        let scanner = MediaScanner(modelContainer: container)
        let result = try await scanner.scanRemoteDirectory(
            service: service,
            path: "/",
            connectionId: connectionId,
            in: context,
            options: .forConnectionRoot(forceFullScan: false, connectionType: .webdav)
        )

        XCTAssertEqual(result.insertedItems.count, 1)
        XCTAssertEqual(service.streamURLCallCount, 0)
        XCTAssertTrue(PlaybackURLResolver.isPlaceholder(result.insertedItems[0].fileURL))
    }

    func testRemoteFileChangedDetectsContentVersion() {
        let item = MediaItem(title: "A", fileURL: URL(string: "file:///a.mkv")!, mediaType: .movie)
        item.originalFileName = "a.mkv"
        item.fileSize = 100
        item.remoteModifiedAt = Date(timeIntervalSince1970: 100)
        item.remoteContentVersion = "v1"

        let changed = RemoteFile(
            name: "a.mkv",
            path: "/a.mkv",
            size: 100,
            isDirectory: false,
            modifiedDate: Date(timeIntervalSince1970: 100),
            type: .video,
            contentVersion: "v2"
        )
        XCTAssertTrue(MediaItemFactory.remoteFileChanged(existing: item, file: changed, forceFullScan: false))
    }

    private func mockVideo(path: String, name: String, size: Int64, modified: Date) -> RemoteFile {
        RemoteFile(
            name: name,
            path: path,
            size: size,
            isDirectory: false,
            modifiedDate: modified,
            type: .video
        )
    }
}

private final class MockRemoteFileService: RemoteFileService {
    var type: ConnectionType = .webdav
    var isConnected = true
    var filesByDirectory: [String: [RemoteFile]]
    var failingPaths: Set<String> = []
    var streamURLCallCount = 0

    init(filesByDirectory: [String: [RemoteFile]], failingPaths: Set<String> = []) {
        self.filesByDirectory = filesByDirectory
        self.failingPaths = failingPaths
    }

    func connect(config: ConnectionConfig) async throws {
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        if failingPaths.contains(path) {
            throw NetworkError.transferFailed("mock list failure")
        }
        return filesByDirectory[path] ?? []
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        streamURLCallCount += 1
        return URL(string: "https://example.com\(file.path)")!
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        progress(1)
    }
}
