import SwiftData
import XCTest
@testable import VanmoCore

@MainActor
final class DirectLinkTests: XCTestCase {
    func testParseAcceptsHTTPAndHTTPSWithSurroundingWhitespace() throws {
        let url = try DirectLinkLibrary.parse("  https://larmoire.org/jellyfish/a b.mkv?x=1 \n").get()
        XCTAssertEqual(url.host, "larmoire.org")
        XCTAssertEqual(url.pathExtension, "mkv")
        XCTAssertEqual(try DirectLinkLibrary.parse("http://10.0.0.2:8080/v.mp4").get().port, 8080)
    }

    func testParseAllowsCleartextOnlyForLocalHostsUnderATS() throws {
        XCTAssertEqual(DirectLinkLibrary.parse("http://example.com/a.mp4").failure, .insecurePublicHost)
        XCTAssertEqual(DirectLinkLibrary.parse("HTTP://cdn.example.org/a.mp4").failure, .insecurePublicHost)
        XCTAssertEqual(DirectLinkLibrary.parse("http://1.2.3.4.example.com/a.mp4").failure, .insecurePublicHost)
        XCTAssertNoThrow(try DirectLinkLibrary.parse("http://192.168.1.20:8080/a.mp4").get())
        XCTAssertNoThrow(try DirectLinkLibrary.parse("http://nas.local/a.mkv").get())
        XCTAssertNoThrow(try DirectLinkLibrary.parse("http://nas/a.mkv").get())
        XCTAssertNoThrow(try DirectLinkLibrary.parse("http://[fe80::1]/a.mkv").get())
        XCTAssertNoThrow(try DirectLinkLibrary.parse("https://example.com/a.mp4").get())
    }

    func testParseNormalizesSchemeAndHostCase() throws {
        let url = try DirectLinkLibrary.parse("HTTPS://Example.COM/Path/A.mkv").get()
        XCTAssertEqual(url.absoluteString, "https://example.com/Path/A.mkv")
    }

    func testParseRejectsEmptyOtherSchemesMissingHostAndCredentials() {
        XCTAssertEqual(DirectLinkLibrary.parse("   ").failure, .empty)
        XCTAssertEqual(DirectLinkLibrary.parse("ftp://nas.local/movie.mkv").failure, .unsupportedScheme)
        XCTAssertEqual(DirectLinkLibrary.parse("smb://nas/movie.mkv").failure, .unsupportedScheme)
        XCTAssertEqual(DirectLinkLibrary.parse("larmoire.org/a.mkv").failure, .unsupportedScheme)
        XCTAssertEqual(DirectLinkLibrary.parse("https:///a.mkv").failure, .missingHost)
        XCTAssertEqual(DirectLinkLibrary.parse("https://admin:secret@nas.local/a.mkv").failure, .embeddedCredentials)
        XCTAssertEqual(DirectLinkLibrary.parse("https://admin@nas.local/a.mkv").failure, .embeddedCredentials)
    }

    func testFormatLabelAndStreamOnly() {
        XCTAssertEqual(DirectLinkLibrary.formatLabel(for: URL(string: "https://h/a.mkv")!), "MKV")
        XCTAssertEqual(DirectLinkLibrary.formatLabel(for: URL(string: "https://h/live/master.m3u8")!), "HLS")
        XCTAssertEqual(DirectLinkLibrary.formatLabel(for: URL(string: "https://h/watch?id=1")!), "URL")
        XCTAssertTrue(DirectLinkLibrary.isStreamOnly(URL(string: "https://h/live/master.m3u8")!))
        XCTAssertFalse(DirectLinkLibrary.isStreamOnly(URL(string: "https://h/a.mp4")!))
    }

    func testUpsertCreatesLocalOnlyItemAndReusesSameURL() throws {
        let context = try makeContext()
        let url = URL(string: "https://larmoire.org/media/jelly%20fish.mkv")!

        let first = try DirectLinkLibrary.upsert(url: url, in: context)
        first.lastPlaybackPosition = 42
        let second = try DirectLinkLibrary.upsert(url: url, in: context)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.lastPlaybackPosition, 42)
        XCTAssertEqual(second.title, "jelly fish.mkv")
        XCTAssertEqual(second.originalFileName, "jelly fish.mkv")
        XCTAssertEqual(second.container, "mkv")
        XCTAssertNil(second.sourceConnectionId)
        XCTAssertFalse(second.isProgressCloudSynced)
        XCTAssertFalse(second.isFavoriteCloudSynced)
        XCTAssertEqual(DirectLinkLibrary.entries(in: context).count, 1)
    }

    func testEntriesExcludeLocalFilesAndConnectionItemsAndSortByRecency() throws {
        let context = try makeContext()
        let older = try DirectLinkLibrary.upsert(url: URL(string: "https://a.example/old.mp4")!, in: context)
        older.addedAt = Date(timeIntervalSince1970: 100)
        let played = try DirectLinkLibrary.upsert(url: URL(string: "https://b.example/played.mp4")!, in: context)
        played.addedAt = Date(timeIntervalSince1970: 50)
        played.lastPlayedAt = Date(timeIntervalSince1970: 200)

        context.insert(MediaItem(title: "local", fileURL: URL(fileURLWithPath: "/tmp/a.mp4")))
        let connected = MediaItem(title: "nas", fileURL: URL(string: "https://nas.local/dav/a.mp4")!)
        connected.sourceConnectionId = UUID()
        context.insert(connected)
        try context.save()

        let entries = DirectLinkLibrary.entries(in: context)
        XCTAssertEqual(entries.map(\.id), [played.id, older.id])
        XCTAssertFalse(DirectLinkLibrary.isDirectLink(connected))
    }

    func testRemoveDeletesOnlyDirectLinks() throws {
        let context = try makeContext()
        let link = try DirectLinkLibrary.upsert(url: URL(string: "https://a.example/a.mp4")!, in: context)
        let local = MediaItem(title: "local", fileURL: URL(fileURLWithPath: "/tmp/a.mp4"))
        context.insert(local)
        try context.save()

        try DirectLinkLibrary.remove(local, in: context)
        try DirectLinkLibrary.remove(link, in: context)

        XCTAssertTrue(DirectLinkLibrary.entries(in: context).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MediaItem>()).count, 1)
    }

    func testDirectLinkDownloadRequestUsesFullURLAsSourceKey() throws {
        let context = try makeContext()
        let a = try DirectLinkLibrary.upsert(url: URL(string: "https://a.example/v/movie.mkv")!, in: context)
        let b = try DirectLinkLibrary.upsert(url: URL(string: "https://b.example/v/movie.mkv")!, in: context)

        let requestA = try DownloadRequestFactory.make(from: a, connectionType: nil)
        let requestB = try DownloadRequestFactory.make(from: b, connectionType: nil)

        XCTAssertNil(requestA.sourceConnectionId)
        XCTAssertEqual(requestA.sourceFileURL, a.fileURL)
        XCTAssertEqual(requestA.fileName, "movie.mkv")
        XCTAssertEqual(requestA.sourceKey, "https://a.example/v/movie.mkv")
        XCTAssertNotEqual(requestA.sourceKey, requestB.sourceKey)
    }

    func testDownloadTaskLookupMatchesOnlyConnectionlessSameURL() throws {
        let context = try makeContext()
        let link = try DirectLinkLibrary.upsert(url: URL(string: "https://a.example/v/movie.mkv")!, in: context)
        let request = try DownloadRequestFactory.make(from: link, connectionType: nil)
        let task = DownloadTaskSnapshot(request: request, destination: DownloadDestination(rootPath: "/tmp"))
        let connected = DownloadTaskSnapshot(
            request: DownloadRequest(
                sourceConnectionId: UUID(),
                connectionType: .webdav,
                remotePath: "/v/movie.mkv",
                sourceFileURL: link.fileURL,
                fileName: "movie.mkv",
                displayTitle: "movie",
                mediaType: .movie
            ),
            destination: DownloadDestination(rootPath: "/tmp")
        )

        XCTAssertEqual(DirectLinkLibrary.downloadTask(for: link.fileURL, in: [connected, task])?.id, task.id)
        XCTAssertNil(DirectLinkLibrary.downloadTask(for: URL(string: "https://b.example/x.mkv")!, in: [task]))
    }

    func testLocalFileSourceKeyStaysPathBased() {
        let request = DownloadRequest(
            sourceConnectionId: nil,
            connectionType: nil,
            remotePath: "/tmp/a.mkv",
            sourceFileURL: URL(fileURLWithPath: "/tmp/./a.mkv"),
            fileName: "a.mkv",
            displayTitle: "a",
            mediaType: .movie
        )
        XCTAssertEqual(request.sourceKey, "/tmp/a.mkv")
    }

    func testHLSDirectLinkIsNotDownloadable() throws {
        let context = try makeContext()
        let hls = try DirectLinkLibrary.upsert(url: URL(string: "https://live.example.tv/master.m3u8")!, in: context)
        XCTAssertFalse(DownloadEligibility.isEligible(item: hls, connectionType: nil))
        XCTAssertThrowsError(try DownloadRequestFactory.make(from: hls, connectionType: nil))
    }

    func testListModelValidatesInputAndStoresLink() throws {
        let model = DirectLinkListModel()
        model.configure(modelContext: try makeContext())

        model.input = "ftp://nas.local/a.mkv"
        XCTAssertNil(model.addInput())
        XCTAssertNotNil(model.inputError)
        model.input = " https://a.example/a.mp4 "
        XCTAssertNil(model.inputError)

        let item = try XCTUnwrap(model.addInput())
        XCTAssertEqual(model.input, "")
        XCTAssertEqual(model.entries.map(\.id), [item.id])

        model.remove(item)
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testListModelRefusesToDownloadHLS() async throws {
        let model = DirectLinkListModel()
        model.configure(modelContext: try makeContext())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VanmoDirectLinkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DownloadManager(storeRootDirectory: root)

        model.input = "https://live.example.tv/master.m3u8"
        await model.downloadInput(using: manager)

        XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(model.entries.count, 1)
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return ModelContext(container)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
