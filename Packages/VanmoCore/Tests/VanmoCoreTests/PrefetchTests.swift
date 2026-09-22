import Foundation
import XCTest
@testable import VanmoCore

final class PrefetchTests: XCTestCase {
    func testIsProxyURLMatchesLocalhostStreamPath() {
        XCTAssertTrue(
            PrefetchConfig.isProxyURL(URL(string: "http://127.0.0.1:53783/stream/token")!)
        )
        XCTAssertTrue(
            PrefetchConfig.isProxyURL(URL(string: "http://localhost:8080/stream/abc")!)
        )
        XCTAssertFalse(
            PrefetchConfig.isProxyURL(URL(string: "http://127.0.0.1:53783/other")!)
        )
        XCTAssertFalse(
            PrefetchConfig.isProxyURL(URL(string: "https://example.com/stream/token")!)
        )
        XCTAssertFalse(
            PrefetchConfig.isProxyURL(URL(fileURLWithPath: "/tmp/movie.mkv"))
        )
    }

    func testIsMediaServerStreamURLMatchesEmbyAndJellyfin() {
        XCTAssertTrue(
            PrefetchConfig.isMediaServerStreamURL(
                URL(string: "https://emby.example.com:443/emby/Videos/232355/stream")!
            )
        )
        XCTAssertTrue(
            PrefetchConfig.isMediaServerStreamURL(
                URL(string: "http://10.0.0.2:8096/Videos/12/stream?static=true")!
            )
        )
        XCTAssertFalse(
            PrefetchConfig.isMediaServerStreamURL(
                URL(string: "http://127.0.0.1:53784/stream/token")!
            )
        )
        XCTAssertFalse(
            PrefetchConfig.isMediaServerStreamURL(
                URL(string: "https://cdn.example.com/movie.mkv")!
            )
        )
        XCTAssertTrue(
            PrefetchConfig.shouldDisableSecondOpen(
                for: URL(string: "https://emby.example.com/emby/Videos/1/stream")!
            )
        )
        XCTAssertTrue(
            PrefetchConfig.shouldDisableSecondOpen(
                for: URL(string: "http://127.0.0.1:53784/stream/token")!
            )
        )
        XCTAssertFalse(
            PrefetchConfig.shouldDisableSecondOpen(
                for: URL(fileURLWithPath: "/tmp/movie.mkv")
            )
        )
    }

    func testFetchLimiterRemovesCancelledWaiter() async throws {
        let limiter = FetchLimiter(limit: 1)
        try await limiter.acquire()

        let waiter = Task {
            try await limiter.acquire()
        }
        try await waitUntil { await limiter.waitingCount == 1 }
        waiter.cancel()

        do {
            try await waiter.value
            XCTFail("Expected cancelled limiter waiter to throw")
        } catch is CancellationError {
            // Expected.
        }

        await limiter.release()
        let waitingCount = await limiter.waitingCount
        XCTAssertEqual(waitingCount, 0)
    }

    func testReadGateCloseCancelsWaitersAndRejectsNewWork() async throws {
        let gate = CancellableReadGate()
        try await gate.acquire()

        let waiter = Task {
            try await gate.acquire()
        }
        try await waitUntil { await gate.waitingCount == 1 }

        let close = Task {
            await gate.beginClose()
            await gate.waitUntilClosed()
        }

        do {
            try await waiter.value
            XCTFail("Expected closing read gate to cancel queued work")
        } catch is CancellationError {
            // Expected.
        }

        await gate.release()
        await close.value
        let isClosed = await gate.isClosed
        XCTAssertTrue(isClosed)

        do {
            try await gate.acquire()
            XCTFail("Expected closed read gate to reject work")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testRangeCacheTracksPartialAndFullRangesAndRemovesStorage() throws {
        let sessionID = "range-cache-\(UUID().uuidString)"
        let cache = try RangeCache(sessionId: sessionID)
        let directory = PrefetchTemporaryStore.sessionDirectory(sessionId: sessionID)
        defer { cache.removeAll() }

        cache.write(globalOffset: 10, data: Data([1, 2, 3]))

        XCTAssertTrue(cache.hasEntire(range: 10..<13))
        XCTAssertEqual(cache.readEntire(range: 10..<13), Data([1, 2, 3]))
        XCTAssertFalse(cache.hasEntire(range: 9..<13))
        XCTAssertNil(cache.readEntire(range: 9..<13))

        let fullChunk = Data(repeating: 0xAB, count: PrefetchConfig.chunkSize)
        let fullChunkOffset = Int64(PrefetchConfig.chunkSize)
        cache.write(globalOffset: fullChunkOffset, data: fullChunk)

        XCTAssertTrue(cache.hasEntire(range: fullChunkOffset..<(fullChunkOffset + Int64(fullChunk.count))))
        XCTAssertEqual(
            cache.readEntire(range: fullChunkOffset..<(fullChunkOffset + Int64(fullChunk.count))),
            fullChunk
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("1.bin").path))

        cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(cache.hasEntire(range: 10..<13))
    }

    func testSessionCachesAndDeduplicatesConcurrentSizeProbe() async throws {
        let probeGate = TestAsyncGate()
        let source = FakePrefetchByteSource(
            totalSize: 1_024,
            pipelineDepth: 1,
            probeGate: probeGate
        )
        let session = try PrefetchSession(
            token: "probe-\(UUID().uuidString)",
            source: source
        )

        let first = Task {
            try await session.makeResponse(rangeHeader: "bytes=0-0")
        }
        let second = Task {
            try await session.makeResponse(rangeHeader: "bytes=1-1")
        }

        try await waitUntil { await source.probeCount == 1 }
        await probeGate.open()
        _ = try await first.value
        _ = try await second.value

        _ = try await session.makeResponse(rangeHeader: "bytes=2-2")
        let probeCount = await source.probeCount
        XCTAssertEqual(probeCount, 1)
        await session.cleanup()
    }

    func testSessionStartsANewProbeGenerationAfterFailureAndCachesOnlyTheRetry() async throws {
        let source = FakePrefetchByteSource(
            totalSize: 1_024,
            pipelineDepth: 1,
            probeFailuresBeforeSuccess: 1
        )
        let session = try PrefetchSession(
            token: "probe-retry-\(UUID().uuidString)",
            source: source
        )

        _ = try await session.makeResponse(rangeHeader: "bytes=0-0")
        _ = try await session.makeResponse(rangeHeader: "bytes=1-1")

        let probeCount = await source.probeCount
        XCTAssertEqual(probeCount, 2)
        await session.cleanup()
    }

    func testSessionDeduplicatesSameChunkAndCancelsOldBody() async throws {
        let fetchGate = TestAsyncGate()
        let source = FakePrefetchByteSource(
            totalSize: Int64(PrefetchConfig.chunkSize),
            pipelineDepth: 1,
            fetchGate: fetchGate
        )
        let session = try PrefetchSession(
            token: "dedupe-\(UUID().uuidString)",
            source: source
        )

        let (_, firstBody) = try await session.makeResponse(rangeHeader: "bytes=0-1023")
        let firstConsumer = Task { try await collect(firstBody) }
        try await waitUntil { await source.fetchCount == 1 }

        let (_, secondBody) = try await session.makeResponse(rangeHeader: "bytes=0-1023")
        let secondConsumer = Task { try await collect(secondBody) }
        await fetchGate.open()

        let firstData = try await firstConsumer.value
        let secondData = try await secondConsumer.value
        let fetchCount = await source.fetchCount
        XCTAssertTrue(firstData.isEmpty)
        XCTAssertEqual(secondData.count, 1_024)
        XCTAssertEqual(fetchCount, 1)
        await session.cleanup()
    }

    func testSessionHonorsSourcePipelineDepthWhileUsingMultipleChunks() async throws {
        let source = FakePrefetchByteSource(
            totalSize: Int64(PrefetchConfig.chunkSize * 4),
            pipelineDepth: 2,
            fetchDelayNanoseconds: 30_000_000
        )
        let session = try PrefetchSession(
            token: "pipeline-\(UUID().uuidString)",
            source: source
        )
        let lastByte = PrefetchConfig.chunkSize * 4 - 1

        let (_, body) = try await session.makeResponse(rangeHeader: "bytes=0-\(lastByte)")
        let data = try await collect(body)
        let maximumActiveFetches = await source.maximumActiveFetches

        XCTAssertEqual(data.count, PrefetchConfig.chunkSize * 4)
        XCTAssertEqual(maximumActiveFetches, 2)
        await session.cleanup()
    }

    func testSessionBodyAppliesBoundedBackpressure() async throws {
        let source = FakePrefetchByteSource(
            totalSize: Int64(PrefetchConfig.chunkSize * 4),
            pipelineDepth: 2
        )
        let session = try PrefetchSession(
            token: "backpressure-\(UUID().uuidString)",
            source: source
        )
        let lastByte = PrefetchConfig.chunkSize * 4 - 1

        let (_, body) = try await session.makeResponse(rangeHeader: "bytes=0-\(lastByte)")
        try await waitUntil { await source.fetchCount == 3 }
        try await Task.sleep(nanoseconds: 50_000_000)

        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 3)
        withExtendedLifetime(body) {}
        await session.cleanup()
    }

    func testConcreteSourcesDeclareConservativePipelineDepths() async {
        let http = HTTPPrefetchByteSource(url: URL(string: "https://example.com/video.mp4")!)
        let smb = SMBPrefetchByteSource(url: URL(string: "smb://example.com/share/video.mp4")!)
        let ftp = FTPPrefetchByteSource(url: URL(string: "ftp://example.com/video.mp4")!)
        let sftp = SFTPPrefetchByteSource(url: URL(string: "sftp://example.com/video.mp4")!)

        XCTAssertEqual(http.pipelineDepth, PrefetchConfig.httpPipelineDepth)
        XCTAssertEqual(smb.pipelineDepth, 1)
        XCTAssertEqual(ftp.pipelineDepth, 1)
        XCTAssertEqual(sftp.pipelineDepth, 1)
    }

    func testSessionCleanupWaitsForSourceClose() async throws {
        let closeGate = TestAsyncGate()
        let source = FakePrefetchByteSource(
            totalSize: 1,
            pipelineDepth: 1,
            closeGate: closeGate
        )
        let session = try PrefetchSession(
            token: "cleanup-\(UUID().uuidString)",
            source: source
        )

        let cleanup = Task {
            await session.cleanup()
        }
        try await waitUntil { await source.closeStarted }
        let isClosedBeforeRelease = await source.isClosed
        XCTAssertFalse(isClosedBeforeRelease)

        await closeGate.open()
        await cleanup.value

        let isClosedAfterCleanup = await source.isClosed
        XCTAssertTrue(isClosedAfterCleanup)
    }

    func testSessionCleanupRejectsLateProbeBodyAndDownloadWork() async throws {
        let probeGate = TestAsyncGate()
        let closeGate = TestAsyncGate()
        let source = FakePrefetchByteSource(
            totalSize: 1_024,
            pipelineDepth: 1,
            probeGate: probeGate,
            closeGate: closeGate
        )
        let token = "closing-\(UUID().uuidString)"
        let session = try PrefetchSession(token: token, source: source)
        let directory = PrefetchTemporaryStore.sessionDirectory(sessionId: token)

        let response = Task {
            try await session.makeResponse(rangeHeader: "bytes=0-127")
        }
        try await waitUntil { await source.probeCount == 1 }

        let cleanup = Task {
            await session.cleanup()
        }
        try await waitUntil { await source.closeStarted }

        do {
            _ = try await session.makeResponse(rangeHeader: "bytes=128-255")
            XCTFail("Expected a closing session to reject a new response")
        } catch is CancellationError {
            // Expected.
        }

        await probeGate.open()
        do {
            _ = try await response.value
            XCTFail("Expected the stale probe result to be rejected")
        } catch is CancellationError {
            // Expected.
        }

        await closeGate.open()
        await cleanup.value

        do {
            _ = try await session.makeResponse(rangeHeader: "bytes=256-511")
            XCTFail("Expected a closed session to reject a new response")
        } catch is CancellationError {
            // Expected.
        }

        let probeCount = await source.probeCount
        let fetchCount = await source.fetchCount
        XCTAssertEqual(probeCount, 1)
        XCTAssertEqual(fetchCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRangeResponseRejects200AndRequiresMatching206ContentRange() throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let requestedRange: ClosedRange<Int64> = 10...19
        let data = Data(repeating: 0x01, count: 10)
        let fullResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "100"]
            )
        )

        XCTAssertThrowsError(
            try RemoteFetcher.validateRangeResponse(
                data: Data(repeating: 0x01, count: 100),
                response: fullResponse,
                requestedRange: requestedRange
            )
        ) { error in
            guard case PrefetchError.badResponse = error else {
                return XCTFail("Expected badResponse, got \(error)")
            }
        }

        let validPartialResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Range": "bytes 10-19/100"]
            )
        )
        XCTAssertEqual(
            try RemoteFetcher.validateRangeResponse(
                data: data,
                response: validPartialResponse,
                requestedRange: requestedRange
            ),
            100
        )

        let mismatchedPartialResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Range": "bytes 0-9/100"]
            )
        )
        XCTAssertThrowsError(
            try RemoteFetcher.validateRangeResponse(
                data: data,
                response: mismatchedPartialResponse,
                requestedRange: requestedRange
            )
        ) { error in
            guard case PrefetchError.badResponse = error else {
                return XCTFail("Expected badResponse, got \(error)")
            }
        }
    }

    func testProbeRangeAcceptsAValidResponseClampedAtEndOfFile() throws {
        let url = URL(string: "https://example.com/video.mp4")!
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Range": "bytes 0-99/100"]
            )
        )

        XCTAssertEqual(
            try RemoteFetcher.validateProbeRangeResponse(
                data: Data(repeating: 0x01, count: 100),
                response: response,
                requestedRange: 0...1_023
            ),
            100
        )
    }

    func testHeaderFirstRangeReadCancelsIgnoredRangeBeforeCollectingBody() async throws {
        let state = StreamingURLProtocolState()
        StreamingURLProtocol.state = state
        defer { StreamingURLProtocol.state = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let fetcher = RemoteFetcher(
            originalURL: URL(string: "https://example.com/video.mp4")!,
            sessionConfiguration: configuration
        )

        do {
            _ = try await fetcher.data(forInclusiveRange: 0...255)
            XCTFail("Expected a 200 response to be rejected")
        } catch PrefetchError.badResponse {
            // Expected.
        }

        try await waitUntil { state.isStopped }
        XCTAssertLessThanOrEqual(state.deliveredByteCount, 1_024)
    }

    func testHeaderFirstRangeReadRejectsBodyBeyondRequestedLength() async throws {
        let state = StreamingURLProtocolState(statusCode: 206, contentRange: "bytes 0-255/1024")
        StreamingURLProtocol.state = state
        defer { StreamingURLProtocol.state = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let fetcher = RemoteFetcher(
            originalURL: URL(string: "https://example.com/video.mp4")!,
            sessionConfiguration: configuration
        )

        do {
            _ = try await fetcher.data(forInclusiveRange: 0...255)
            XCTFail("Expected an oversized Range body to be rejected")
        } catch PrefetchError.badResponse {
            // Expected.
        }

        try await waitUntil { state.isStopped }
        XCTAssertLessThanOrEqual(state.deliveredByteCount, 512)
    }

    private func collect(
        _ stream: AsyncThrowingStream<Data, Error>
    ) async throws -> Data {
        var result = Data()
        for try await chunk in stream {
            result.append(chunk)
        }
        return result
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while !(await condition()) {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                XCTFail("Timed out waiting for asynchronous condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private actor FakePrefetchByteSource: PrefetchByteSource {
    nonisolated let pipelineDepth: Int

    private let totalSize: Int64
    private let probeGate: TestAsyncGate?
    private let fetchGate: TestAsyncGate?
    private let closeGate: TestAsyncGate?
    private let fetchDelayNanoseconds: UInt64
    private var probeFailuresRemaining: Int

    private(set) var probeCount = 0
    private(set) var fetchCount = 0
    private(set) var maximumActiveFetches = 0
    private(set) var closeStarted = false
    private(set) var isClosed = false
    private var activeFetches = 0

    init(
        totalSize: Int64,
        pipelineDepth: Int,
        probeGate: TestAsyncGate? = nil,
        fetchGate: TestAsyncGate? = nil,
        closeGate: TestAsyncGate? = nil,
        fetchDelayNanoseconds: UInt64 = 0,
        probeFailuresBeforeSuccess: Int = 0
    ) {
        self.totalSize = totalSize
        self.pipelineDepth = pipelineDepth
        self.probeGate = probeGate
        self.fetchGate = fetchGate
        self.closeGate = closeGate
        self.fetchDelayNanoseconds = fetchDelayNanoseconds
        self.probeFailuresRemaining = probeFailuresBeforeSuccess
    }

    func probeTotalSize() async throws -> Int64 {
        probeCount += 1
        if let probeGate {
            await probeGate.wait()
        }
        if probeFailuresRemaining > 0 {
            probeFailuresRemaining -= 1
            throw PrefetchError.unknownSize
        }
        return totalSize
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        fetchCount += 1
        activeFetches += 1
        maximumActiveFetches = max(maximumActiveFetches, activeFetches)
        defer { activeFetches -= 1 }

        if let fetchGate {
            await fetchGate.wait()
        }
        if fetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        try Task.checkCancellation()

        let count = Int(range.upperBound - range.lowerBound + 1)
        return Data(repeating: UInt8(truncatingIfNeeded: range.lowerBound), count: count)
    }

    func close() async {
        closeStarted = true
        if let closeGate {
            await closeGate.wait()
        }
        isClosed = true
    }
}

private actor TestAsyncGate {
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

private final class StreamingURLProtocolState: @unchecked Sendable {
    let statusCode: Int
    let contentRange: String?

    private let lock = NSLock()
    private var stopped = false
    private var byteCount = 0

    init(statusCode: Int = 200, contentRange: String? = nil) {
        self.statusCode = statusCode
        self.contentRange = contentRange
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    var deliveredByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return byteCount
    }

    func markStopped() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func recordDelivery(count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return false }
        byteCount += count
        return true
    }
}

private final class StreamingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var state: StreamingURLProtocolState?

    private let queue = DispatchQueue(label: "com.vanmo.tests.streaming-url-protocol")

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let state = Self.state,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: state.statusCode,
                  httpVersion: nil,
                  headerFields: state.contentRange.map { ["Content-Range": $0] }
              ) else {
            client?.urlProtocol(self, didFailWithError: PrefetchError.badResponse)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        queue.async { [weak self] in
            guard let self else { return }
            for _ in 0..<1_024 {
                guard state.recordDelivery(count: 256) else { return }
                self.client?.urlProtocol(self, didLoad: Data(repeating: 0xAB, count: 256))
                Thread.sleep(forTimeInterval: 0.001)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.state?.markStopped()
    }
}
