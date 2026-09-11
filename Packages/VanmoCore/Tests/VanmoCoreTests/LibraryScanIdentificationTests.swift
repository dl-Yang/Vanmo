import CoreGraphics
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import VanmoCore

final class LibraryScanTriggerTests: XCTestCase {
    func testManualTypeWithoutLocalItemsUsesShallowRoot() {
        let scope = LibraryScanTrigger.fileScanScope(
            type: .smb,
            scanPath: nil,
            isPartialScan: false,
            hasLocalMediaItems: false
        )
        XCTAssertEqual(scope, .shallowRoot)
        XCTAssertTrue(
            LibraryScanTrigger.shouldScanRemoteFiles(
                type: .smb,
                scanPath: nil,
                hasLocalMediaItems: false
            )
        )
    }

    func testManualTypeWithLocalItemsConnectsOnly() {
        XCTAssertNil(
            LibraryScanTrigger.fileScanScope(
                type: .smb,
                scanPath: nil,
                isPartialScan: false,
                hasLocalMediaItems: true
            )
        )
        XCTAssertFalse(
            LibraryScanTrigger.shouldScanRemoteFiles(
                type: .smb,
                scanPath: nil,
                hasLocalMediaItems: true
            )
        )
    }

    func testManualDirectorySyncKeepsPartialScope() {
        XCTAssertEqual(
            LibraryScanTrigger.fileScanScope(
                type: .webdav,
                scanPath: "/Movies",
                isPartialScan: true,
                hasLocalMediaItems: true
            ),
            .directory(path: "/Movies")
        )
    }

    func testMediaServerStillUsesConnectionRoot() {
        XCTAssertEqual(
            LibraryScanTrigger.fileScanScope(
                type: .plex,
                scanPath: nil,
                isPartialScan: false,
                hasLocalMediaItems: false
            ),
            .connectionRoot
        )
    }

    func testResumeCoversOnlyWhenLocalItemsMissPosters() {
        XCTAssertTrue(
            LibraryScanTrigger.shouldResumeCovers(
                hasLocalMediaItems: true,
                hasMissingPosters: true
            )
        )
        XCTAssertFalse(
            LibraryScanTrigger.shouldResumeCovers(
                hasLocalMediaItems: true,
                hasMissingPosters: false
            )
        )
        XCTAssertFalse(
            LibraryScanTrigger.shouldResumeCovers(
                hasLocalMediaItems: false,
                hasMissingPosters: true
            )
        )
        XCTAssertFalse(
            LibraryScanTrigger.shouldScanRemoteFiles(
                type: .smb,
                scanPath: nil,
                hasLocalMediaItems: true
            )
        )
    }
}

final class ScanItemPathKeyTests: XCTestCase {
    func testNormalizeUnifiesSlashSpellings() {
        let connectionId = UUID()
        XCTAssertEqual(ScanItemPathKey.normalize("/movie.mkv"), "/movie.mkv")
        XCTAssertEqual(ScanItemPathKey.normalize("movie.mkv"), "/movie.mkv")
        XCTAssertEqual(ScanItemPathKey.normalize("//movie.mkv"), "/movie.mkv")
        XCTAssertEqual(ScanItemPathKey.normalize("/movie.mkv/"), "/movie.mkv")
        XCTAssertEqual(ScanItemPathKey.normalize("\\share\\movie.mkv"), "/share/movie.mkv")
        XCTAssertEqual(
            ScanItemPathKey.make(serverId: "movie.mkv", connectionId: connectionId),
            ScanItemPathKey.make(serverId: "/movie.mkv", connectionId: connectionId)
        )
    }
}

final class RemoteScanOptionsShallowTests: XCTestCase {
    func testInitialShallowRootDoesNotPruneAndStopsAtDepthOne() {
        let options = RemoteScanOptions.forInitialShallowRoot(connectionType: .smb)
        XCTAssertEqual(options.maxDepth, 1)
        XCTAssertFalse(options.pruneMissing)
        XCTAssertTrue(options.isPartialScan)
    }

    func testShallowRootScopeMapsToShallowOptions() {
        let options = RemoteScanOptions.forScope(.shallowRoot, forceFullScan: true, connectionType: .smb)
        XCTAssertEqual(options.maxDepth, 1)
        XCTAssertFalse(options.pruneMissing)
        XCTAssertTrue(ScanScope.shallowRoot.isPartialScan)
    }
}

final class EpisodeClusterPlannerTests: XCTestCase {
    func testClustersSameFolderChineseEpisodesAndShortensTitle() {
        let names = (1...5).map { String(format: "咒术回战第%02d集.mp4", $0) }
        var parsed: [String: ParsedFileName] = [:]
        var identifications: [String: MediaIdentificationResult] = [:]

        for name in names {
            parsed[name] = FileNameParser.parse(name)
            identifications[name] = MediaIdentificationPipeline.identify(
                fileName: name,
                directoryPath: "/share/咒术回战"
            )
        }

        let refined = EpisodeClusterPlanner.refine(
            identifications: identifications,
            parsedNames: parsed
        )

        XCTAssertEqual(refined.count, 5)
        XCTAssertEqual(refined["咒术回战第01集.mp4"]?.showTitle, "咒术回战")
        XCTAssertEqual(refined["咒术回战第01集.mp4"]?.title, LocalizedFormat.episodeLabel(1))
        XCTAssertEqual(refined["咒术回战第05集.mp4"]?.title, LocalizedFormat.episodeLabel(5))
        XCTAssertEqual(refined["咒术回战第03集.mp4"]?.mediaType, .tvEpisode)
        XCTAssertEqual(refined["咒术回战第03集.mp4"]?.episode, 3)
    }

    func testLeavesUnrelatedFilesOutOfTheCluster() {
        let names = [
            "咒术回战第01集.mp4",
            "咒术回战第02集.mp4",
            "花絮.mp4",
            "Movie.2020.mkv"
        ]
        var parsed: [String: ParsedFileName] = [:]
        var identifications: [String: MediaIdentificationResult] = [:]
        for name in names {
            parsed[name] = FileNameParser.parse(name)
            identifications[name] = MediaIdentificationPipeline.identify(
                fileName: name,
                directoryPath: "/share/咒术回战"
            )
        }

        let refined = EpisodeClusterPlanner.refine(
            identifications: identifications,
            parsedNames: parsed
        )

        XCTAssertEqual(refined["咒术回战第01集.mp4"]?.title, LocalizedFormat.episodeLabel(1))
        XCTAssertEqual(refined["花絮.mp4"]?.mediaType, .movie)
        XCTAssertNotEqual(refined["花絮.mp4"]?.title, LocalizedFormat.episodeLabel(1))
        XCTAssertEqual(refined["Movie.2020.mkv"]?.mediaType, .movie)
        XCTAssertEqual(refined["Movie.2020.mkv"]?.title, "Movie")
    }

    func testSingleMatchingEpisodeDoesNotCluster() {
        let name = "咒术回战第01集.mp4"
        let refined = EpisodeClusterPlanner.refine(
            identifications: [
                name: MediaIdentificationPipeline.identify(
                    fileName: name,
                    directoryPath: "/share/咒术回战"
                )!
            ],
            parsedNames: [name: FileNameParser.parse(name)]
        )
        XCTAssertEqual(refined[name]?.title, "咒术回战")
        XCTAssertNotEqual(refined[name]?.title, LocalizedFormat.episodeLabel(1))
    }
}

final class ScannedShowGroupingTests: XCTestCase {
    func testDoesNotMergeSameShowTitleAcrossFolders() {
        let connectionId = UUID()
        let left = makeEpisode(
            connectionId: connectionId,
            path: "/A/咒术回战/ep1.mp4",
            showTitle: "咒术回战",
            episode: 1
        )
        let right = makeEpisode(
            connectionId: connectionId,
            path: "/B/咒术回战/ep1.mp4",
            showTitle: "咒术回战",
            episode: 1
        )

        let summaries = ScannedShowGrouping.summaries(from: [left, right])
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(Set(summaries.map(\.parentDirectory)), ["/A/咒术回战", "/B/咒术回战"])
    }

    func testUsesFirstEpisodePosterForShow() {
        let connectionId = UUID()
        let firstPoster = URL(fileURLWithPath: "/tmp/ep1.jpg")
        let ep1 = makeEpisode(
            connectionId: connectionId,
            path: "/TV/Show/e1.mp4",
            showTitle: "Show",
            episode: 1,
            posterURL: firstPoster
        )
        let ep2 = makeEpisode(
            connectionId: connectionId,
            path: "/TV/Show/e2.mp4",
            showTitle: "Show",
            episode: 2,
            posterURL: URL(fileURLWithPath: "/tmp/ep2.jpg")
        )

        let summary = ScannedShowGrouping.summaries(from: [ep2, ep1]).first
        XCTAssertEqual(summary?.posterURL, firstPoster)
        XCTAssertEqual(summary?.episodeCount, 2)
    }

    private func makeEpisode(
        connectionId: UUID,
        path: String,
        showTitle: String,
        episode: Int,
        posterURL: URL? = nil
    ) -> MediaItem {
        let item = MediaItem(
            title: LocalizedFormat.episodeLabel(episode),
            fileURL: URL(fileURLWithPath: path),
            mediaType: .tvEpisode,
            fileSize: 10
        )
        item.sourceConnectionId = connectionId
        item.serverId = path
        item.showTitle = showTitle
        item.episodeNumber = episode
        item.posterURL = posterURL
        return item
    }
}

private actor OverlapProbe {
    private var current = 0
    private(set) var maxSeen = 0

    func enter() {
        current += 1
        maxSeen = max(maxSeen, current)
    }

    func leave() {
        current -= 1
    }
}

private struct StubThumbnailExtractor: VideoThumbnailExtracting {
    let data: Data
    var extractCount = 0

    func extractJPEG(from url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data {
        data
    }
}

private final class RecordingThumbnailExtractor: VideoThumbnailExtracting, @unchecked Sendable {
    let data: Data
    private let lock = NSLock()
    private var recordedURL: URL?

    init(data: Data) {
        self.data = data
    }

    var lastURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return recordedURL
    }

    func extractJPEG(from url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data {
        lock.lock()
        recordedURL = url
        lock.unlock()
        return data
    }
}

final class VideoThumbnailCacheTests: XCTestCase {
    func testCacheKeyChangesWithSizeAndModifiedDate() {
        let id = UUID()
        let first = VideoThumbnailCacheKey.make(
            connectionId: id,
            path: "/a.mp4",
            fileSize: 10,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let second = VideoThumbnailCacheKey.make(
            connectionId: id,
            path: "/a.mp4",
            fileSize: 11,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let third = VideoThumbnailCacheKey.make(
            connectionId: id,
            path: "/a.mp4",
            fileSize: 10,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(
            first,
            VideoThumbnailCacheKey.make(
                connectionId: id,
                path: "/a.mp4",
                fileSize: 10,
                modifiedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    func testQueueSkipsItemsThatAlreadyHavePoster() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "https://example.com/movie.mp4")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/movie.mp4"
        item.posterURL = URL(string: "https://example.com/poster.jpg")
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = VideoThumbnailQueue(
            extractor: StubThumbnailExtractor(data: Data([0x01])),
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.enqueue(items: [item], in: context)
        XCTAssertEqual(item.posterURL?.absoluteString, "https://example.com/poster.jpg")
    }

    func testStoreRoundTripWritesJPEGFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = VideoThumbnailStore(directory: directory)
        let url = try store.save(Data([0xFF, 0xD8, 0xFF]), for: "abc123")
        XCTAssertEqual(store.existingURL(for: "abc123"), url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testJPEGDoesNotScaleWhenMaxPixelSizeIsZero() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 16,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        XCTAssertNotNil(context)
        context?.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
        let image = try XCTUnwrap(context?.makeImage())
        let scaled = VideoThumbnailJPEG.scale(image, maxPixelSize: 0)
        XCTAssertEqual(scaled.width, 16)
        XCTAssertEqual(scaled.height, 8)
        XCTAssertEqual(VideoThumbnailQueue.defaultMaxPixelSize, 0)
    }

    func testJPEGEncodeWritesJFIFMagic() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        XCTAssertNotNil(context)
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context?.makeImage())
        let data = try VideoThumbnailJPEG.encode(image, maxPixelSize: 320)
        XCTAssertGreaterThan(data.count, 20)
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
    }

    func testThumbnailContentTypeUsesPathExtension() {
        XCTAssertEqual(
            VideoThumbnailContentType.identifier(forPath: "/a/Jinx.mp4"),
            UTType.mpeg4Movie.identifier
        )
        XCTAssertEqual(
            VideoThumbnailContentType.identifier(forPath: "/a/clip.MOV"),
            UTType.quickTimeMovie.identifier
        )
        XCTAssertEqual(VideoThumbnailContentType.pathExtension(forPath: "/a/foo.MP4"), "MP4")
        XCTAssertEqual(VideoThumbnailContentType.pathExtension(forPath: "/a/foo"), "mp4")
    }

    func testLibavformatGateFlagsSMBAndFTP() {
        XCTAssertTrue(LibavformatOpenGate.needsExclusiveOpen(URL(string: "smb://host/share/a.mp4")!))
        XCTAssertTrue(LibavformatOpenGate.needsExclusiveOpen(URL(string: "ftp://host/a.mp4")!))
        XCTAssertTrue(LibavformatOpenGate.needsExclusiveOpen(URL(string: "sftp://host/a.mp4")!))
        XCTAssertFalse(LibavformatOpenGate.needsExclusiveOpen(URL(string: "https://host/a.mp4")!))
        XCTAssertFalse(LibavformatOpenGate.needsExclusiveOpen(URL(fileURLWithPath: "/tmp/a.mp4")))
    }

    func testLibavformatGateExclusiveDoesNotOverlap() async {
        let gate = LibavformatOpenGate()
        let probe = OverlapProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 4 {
                group.addTask {
                    try? await gate.exclusive {
                        await probe.enter()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await probe.leave()
                    }
                }
            }
        }

        let maxSeen = await probe.maxSeen
        XCTAssertEqual(maxSeen, 1)
    }

    func testLibavformatGateAcquireReleaseDoesNotOverlap() async {
        let gate = LibavformatOpenGate()
        let probe = OverlapProbe()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await gate.acquire()
                await probe.enter()
                try? await Task.sleep(nanoseconds: 20_000_000)
                await probe.leave()
                await gate.release()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000)
                await gate.acquire()
                await probe.enter()
                await probe.leave()
                await gate.release()
            }
        }

        let maxSeen = await probe.maxSeen
        XCTAssertEqual(maxSeen, 1)
    }

    func testQueueExtractsRemoteURLThroughExtractor() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "smb://host/share/movie.mp4")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/movie.mp4"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = VideoThumbnailQueue(
            extractor: StubThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9])),
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.enqueue(items: [item], in: context)
        XCTAssertEqual(item.posterURL?.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.posterURL?.path ?? ""))
    }

    func testQueueUsesPrefetchURLWhenHeaderResolverReturnsProvider() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let original = URL(string: "https://www.googleapis.com/drive/v3/files/abc?alt=media")!
        let proxied = URL(string: "http://127.0.0.1:9/stream/token")!
        let item = MediaItem(
            title: "Movie",
            fileURL: original,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/item/abc"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractor = RecordingThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let queue = VideoThumbnailQueue(
            extractor: extractor,
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.setHeaderResolver { _ in
            { ["User-Agent": BaiduNetdiskService.requiredUserAgent] }
        }
        await queue.setPrefetchRegistrar { url, _ in
            XCTAssertEqual(url, original)
            return proxied
        }
        await queue.enqueue(items: [item], in: context)
        XCTAssertEqual(extractor.lastURL, proxied)
        XCTAssertEqual(item.posterURL?.pathExtension, "jpg")
    }

    func testQueueSkipsWhenStreamingHeadersAreEmpty() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "https://www.googleapis.com/drive/v3/files/abc?alt=media")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/item/abc"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractor = RecordingThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let queue = VideoThumbnailQueue(
            extractor: extractor,
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.setHeaderResolver { _ in { [:] } }
        await queue.setPrefetchRegistrar { _, _ in
            XCTFail("empty headers must not register prefetch")
            return URL(string: "http://127.0.0.1:9/stream/token")
        }
        await queue.enqueue(items: [item], in: context)
        XCTAssertNil(extractor.lastURL)
        XCTAssertNil(item.posterURL)
    }

    func testQueueUsesOfficialPosterAndSkipsExtractor() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: ConnectionType.baiduNetdisk.catalogPlaybackURL(serverPath: "/file/123"),
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/file/123"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractor = RecordingThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let queue = VideoThumbnailQueue(
            extractor: extractor,
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.setOfficialPosterResolver { _, _ in
            .jpeg(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        }
        await queue.setPrefetchRegistrar { _, _ in
            XCTFail("official poster must not register prefetch")
            return URL(string: "http://127.0.0.1:9/stream/token")
        }
        await queue.enqueue(items: [item], in: context)
        XCTAssertNil(extractor.lastURL)
        XCTAssertEqual(item.posterURL?.pathExtension, "jpg")
    }

    func testQueueSkipsKeyframeWhenOfficialPosterUnavailable() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "https://d.pcs.baidu.com/file/abc")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/file/123"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractor = RecordingThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let queue = VideoThumbnailQueue(
            extractor: extractor,
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.setOfficialPosterResolver { _, _ in .skipKeyframe }
        await queue.setHeaderResolver { _ in
            { ["User-Agent": BaiduNetdiskService.requiredUserAgent] }
        }
        await queue.setPrefetchRegistrar { _, _ in
            XCTFail("skipKeyframe must not register prefetch")
            return URL(string: "http://127.0.0.1:9/stream/token")
        }
        await queue.enqueue(items: [item], in: context)
        XCTAssertNil(extractor.lastURL)
        XCTAssertNil(item.posterURL)
    }

    func testQueueSkipsWhenPrefetchRegistrarFails() async throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "https://www.googleapis.com/drive/v3/files/abc?alt=media")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "/item/abc"
        context.insert(item)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractor = RecordingThumbnailExtractor(data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let queue = VideoThumbnailQueue(
            extractor: extractor,
            store: VideoThumbnailStore(directory: directory)
        )
        await queue.setHeaderResolver { _ in
            { ["User-Agent": BaiduNetdiskService.requiredUserAgent] }
        }
        await queue.setPrefetchRegistrar { _, _ in nil }
        await queue.enqueue(items: [item], in: context)
        XCTAssertNil(extractor.lastURL)
        XCTAssertNil(item.posterURL)
    }

    func testAVFoundationRejectsSMBURL() async {
        let extractor = AVFoundationVideoThumbnailExtractor()
        do {
            _ = try await extractor.extractJPEG(
                from: URL(string: "smb://host/share/movie.mp4")!,
                maxPixelSize: 320,
                timeout: 1
            )
            XCTFail("SMB URLs should not use AVFoundation")
        } catch let error as VideoThumbnailError {
            XCTAssertEqual(error, .unsupportedURL)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}
