import XCTest
@testable import VanmoCore

@MainActor
final class MediaDetailProgressiveLoaderTests: XCTestCase {
    func testCachedRecordIsEmittedBeforeSlowNetwork() async {
        let cached = makeRecord(title: "Cached")
        let networkGate = AsyncGate()
        let loader = MediaDetailProgressiveLoader(
            loadCache: { _ in cached },
            loadMetadata: { _, _, _ in
                await networkGate.wait()
                return self.makeRecord(title: "Network")
            },
            loadSeasons: { _, _ in [] },
            loadCollections: { _, _ in [] },
            storeRecord: { $0 },
            scheduleArtwork: { _ in }
        )

        var iterator = loader.updates(
            for: makeItem(mediaType: .movie),
            connection: nil,
            autoDownloadMetadata: true,
            force: false
        ).makeAsyncIterator()

        guard case .cached(let record) = await iterator.next() else {
            return XCTFail("Expected cached metadata to be the first event")
        }
        XCTAssertEqual(record.title, "Cached")
        await networkGate.open()
    }

    func testIndependentRequestsStartTogetherAndPublishInCompletionOrder() async {
        let barrier = AsyncBarrier(target: 3)
        let loader = MediaDetailProgressiveLoader(
            loadCache: { _ in nil },
            loadMetadata: { _, _, _ in
                await barrier.arriveAndWait()
                try await Task.sleep(nanoseconds: 30_000_000)
                return self.makeRecord(title: "Detail")
            },
            loadSeasons: { _, _ in
                await barrier.arriveAndWait()
                try await Task.sleep(nanoseconds: 10_000_000)
                return [SeasonInfo(seasonNumber: 1)]
            },
            loadCollections: { _, _ in
                await barrier.arriveAndWait()
                try await Task.sleep(nanoseconds: 20_000_000)
                return [self.makeCollection()]
            },
            storeRecord: { $0 },
            scheduleArtwork: { _ in }
        )

        var order: [MediaDetailLoadComponent] = []
        for await event in loader.updates(
            for: makeItem(mediaType: .tvShow),
            connection: nil,
            autoDownloadMetadata: true,
            force: false
        ) {
            switch event {
            case .seasons:
                order.append(.seasons)
            case .collections:
                order.append(.collections)
            case .metadata:
                order.append(.metadata)
            default:
                break
            }
        }

        XCTAssertEqual(order, [.seasons, .collections, .metadata])
    }

    func testMetadataEventDoesNotWaitForArtworkScheduler() async {
        let artworkStarted = expectation(description: "Artwork scheduler started")
        let artworkGate = AsyncGate()
        let loader = MediaDetailProgressiveLoader(
            loadCache: { _ in nil },
            loadMetadata: { _, _, _ in self.makeRecord(title: "Detail") },
            loadSeasons: { _, _ in [] },
            loadCollections: { _, _ in [] },
            storeRecord: { $0 },
            scheduleArtwork: { _ in
                artworkStarted.fulfill()
                await artworkGate.wait()
            }
        )

        var iterator = loader.updates(
            for: makeItem(mediaType: .movie),
            connection: nil,
            autoDownloadMetadata: true,
            force: false
        ).makeAsyncIterator()

        guard case .metadata(let record) = await iterator.next() else {
            return XCTFail("Expected metadata before artwork completion")
        }
        XCTAssertEqual(record.title, "Detail")
        await fulfillment(of: [artworkStarted], timeout: 1)
        await artworkGate.open()
    }

    private func makeItem(mediaType: MediaType) -> MediaItem {
        let item = MediaItem(
            title: "Show",
            fileURL: URL(string: "vanmo://series/show")!,
            mediaType: mediaType
        )
        item.serverId = "show"
        return item
    }

    private func makeRecord(title: String) -> MetadataCacheRecord {
        MetadataCacheRecord(
            key: MetadataCacheKey.from(makeItem(mediaType: .movie)),
            title: title,
            source: .emby
        )
    }

    private func makeCollection() -> ServerMediaItem {
        ServerMediaItem(
            serverId: "collection",
            title: "Collection",
            mediaType: .boxSet,
            streamURL: URL(string: "vanmo://emby-container/collection")!
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

private actor AsyncBarrier {
    private let target: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(target: Int) {
        self.target = target
    }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == target {
            let current = waiters
            waiters.removeAll()
            current.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
