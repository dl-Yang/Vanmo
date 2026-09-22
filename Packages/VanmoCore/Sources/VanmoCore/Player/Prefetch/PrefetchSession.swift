import Foundation

/// 单个远程资源的预缓存会话。
public final class PrefetchSession: @unchecked Sendable {
    public let token: String

    private let cache: RangeCache
    private let source: any PrefetchByteSource
    private let chunkSize: Int

    private enum Lifecycle {
        case open
        case closing
        case closed
    }

    private struct ProbeRecord {
        let identity: UInt64
        let generation: UInt64
        let task: Task<Int64, Error>
    }

    private struct DownloadRecord {
        let identity: UInt64
        let generation: UInt64
        let task: Task<Data, Error>
    }

    private enum CleanupAction {
        case alreadyClosed
        case waitForClose
        case perform(
            activeTasks: [Task<Void, Never>],
            downloadTasks: [Task<Data, Error>],
            probeTask: Task<Int64, Error>?
        )
    }

    private let stateLock = NSLock()
    private var lifecycle = Lifecycle.open
    private var workGeneration: UInt64 = 0
    private var nextIdentity: UInt64 = 0
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var totalSize: Int64?
    private var probeRecord: ProbeRecord?
    private var storedProbeIdentity: (identity: UInt64, generation: UInt64)?

    /// 同一 chunk 的下载共享同一个 Task，避免不同 GET 触发的多个 bodyStream 重复回源。
    /// 任一 task 完成后从 map 移除；移除时机使用 lock 同步保证可见性。
    private var inflight: [Int64: DownloadRecord] = [:]

    /// 当前活跃的 bodyStream tasks。新 GET 进来时主动取消旧的 bodyStream，避免
    /// 多个"幽灵 bodyStream"持续下载浪费带宽（FFmpeg 不再读老 connection，但
    /// AsyncThrowingStream 默认 unbounded buffer 不会反压 producer）。
    private var activeBodyTaskID: UInt64 = 0
    private var activeBodyTasks: [UInt64: Task<Void, Never>] = [:]

#if DEBUG
    private var performanceWindowStartedAt = CFAbsoluteTimeGetCurrent()
    private var performanceResponses = 0
    private var performanceBytes: Int64 = 0
    private var performanceElapsedMs = 0
    private var performanceCacheHits = 0
    private var performanceFetches = 0
#endif

    public convenience init(
        token: String,
        originalURL: URL,
        headerProvider: (() async -> [String: String])? = nil
    ) throws {
        let source: any PrefetchByteSource
        if originalURL.usesSMBScheme {
            source = SMBPrefetchByteSource(url: originalURL)
        } else if originalURL.usesFTPScheme {
            source = FTPPrefetchByteSource(url: originalURL)
        } else if originalURL.usesSFTPScheme {
            source = SFTPPrefetchByteSource(url: originalURL)
        } else {
            source = HTTPPrefetchByteSource(url: originalURL, headerProvider: headerProvider)
        }
        try self.init(token: token, source: source)
    }

    init(token: String, source: any PrefetchByteSource) throws {
        self.token = token
        self.cache = try RangeCache(sessionId: token)
        self.source = source
        self.chunkSize = PrefetchConfig.chunkSize
    }

    public func cleanup() async {
        let activeTasks: [Task<Void, Never>]
        let downloadTasks: [Task<Data, Error>]
        let probeTask: Task<Int64, Error>?
        switch beginCleanup() {
        case .alreadyClosed:
            return
        case .waitForClose:
            await waitUntilClosed()
            return
        case .perform(let active, let downloads, let probe):
            activeTasks = active
            downloadTasks = downloads
            probeTask = probe
        }

        activeTasks.forEach { $0.cancel() }
        downloadTasks.forEach { $0.cancel() }
        probeTask?.cancel()

        await source.close()
        for task in activeTasks {
            await task.value
        }
        for task in downloadTasks {
            _ = try? await task.value
        }
        _ = try? await probeTask?.value
        cache.removeAll()
        finishCleanup()
    }

    private func beginCleanup() -> CleanupAction {
        stateLock.lock()
        switch lifecycle {
        case .closed:
            stateLock.unlock()
            return .alreadyClosed
        case .closing:
            stateLock.unlock()
            return .waitForClose
        case .open:
            lifecycle = .closing
            workGeneration &+= 1
        }

        let activeTasks = Array(activeBodyTasks.values)
        activeBodyTasks.removeAll()
        let downloadTasks = inflight.values.map(\.task)
        inflight.removeAll()
        let probeTask = probeRecord?.task
        probeRecord = nil
        storedProbeIdentity = nil
        totalSize = nil
        stateLock.unlock()
        return .perform(
            activeTasks: activeTasks,
            downloadTasks: downloadTasks,
            probeTask: probeTask
        )
    }

    private func finishCleanup() {
        stateLock.lock()
        lifecycle = .closed
        let waiters = closeWaiters
        closeWaiters.removeAll()
        stateLock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func waitUntilClosed() async {
        await withCheckedContinuation { continuation in
            stateLock.lock()
            if lifecycle == .closed {
                stateLock.unlock()
                continuation.resume()
            } else {
                closeWaiters.append(continuation)
                stateLock.unlock()
            }
        }
    }

    private func cachedTotalSize() -> Int64? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return totalSize
    }

    private enum ProbeState {
        case cached(Int64)
        case pending(ProbeRecord)
    }

    private func currentProbeState() throws -> ProbeState {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard lifecycle == .open else {
            throw CancellationError()
        }
        if let totalSize {
            return .cached(totalSize)
        }
        if let probeRecord {
            return .pending(probeRecord)
        }
        let source = self.source
        let task = Task {
            try await source.probeTotalSize()
        }
        nextIdentity &+= 1
        let record = ProbeRecord(
            identity: nextIdentity,
            generation: workGeneration,
            task: task
        )
        probeRecord = record
        return .pending(record)
    }

    private func storeProbeResult(_ size: Int64, record: ProbeRecord) throws {
        stateLock.lock()
        guard lifecycle == .open, workGeneration == record.generation else {
            stateLock.unlock()
            throw CancellationError()
        }
        if probeRecord?.identity == record.identity,
           probeRecord?.generation == record.generation {
            totalSize = size
            storedProbeIdentity = (record.identity, record.generation)
            probeRecord = nil
        } else if storedProbeIdentity?.identity != record.identity
                    || storedProbeIdentity?.generation != record.generation {
            stateLock.unlock()
            throw CancellationError()
        }
        stateLock.unlock()
    }

    private func clearProbeTask(record: ProbeRecord) {
        stateLock.lock()
        if probeRecord?.identity == record.identity,
           probeRecord?.generation == record.generation {
            probeRecord = nil
        }
        stateLock.unlock()
    }

    private func loadTotalSize() async throws -> Int64 {
        let record: ProbeRecord
        switch try currentProbeState() {
        case .cached(let size):
            return size
        case .pending(let pending):
            record = pending
        }

        do {
            let size = try await record.task.value
            try storeProbeResult(size, record: record)
            return size
        } catch {
            clearProbeTask(record: record)
            throw error
        }
    }

    /// 复用或创建 chunk 的下载 Task。多个 bodyStream pipeline 可共享同一 Task，避免重复回源。
    /// 注意：返回的 Task 不应被单个 bodyStream 取消（取消会影响所有等待者），
    /// 仅在 session cleanup 时一并取消。
    private func sharedDownload(
        chunkStart: Int64,
        chunkEnd: Int64
    ) throws -> Task<Data, Error> {
        stateLock.lock()
        guard lifecycle == .open else {
            stateLock.unlock()
            throw CancellationError()
        }
        if let existing = inflight[chunkStart] {
            stateLock.unlock()
            return existing.task
        }
        nextIdentity &+= 1
        let identity = nextIdentity
        let generation = workGeneration
        let task = Task<Data, Error>.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            try await FetchLimiter.shared.acquire()
            let data: Data
            do {
                try Task.checkCancellation()
                data = try await self.source.data(forInclusiveRange: chunkStart...chunkEnd)
            } catch {
                await FetchLimiter.shared.release()
                self.clearDownload(
                    chunkStart: chunkStart,
                    identity: identity,
                    generation: generation
                )
                throw error
            }
            await FetchLimiter.shared.release()
            try self.completeDownload(
                data,
                chunkStart: chunkStart,
                identity: identity,
                generation: generation
            )
            return data
        }
        inflight[chunkStart] = DownloadRecord(
            identity: identity,
            generation: generation,
            task: task
        )
        stateLock.unlock()
        return task
    }

    private func completeDownload(
        _ data: Data,
        chunkStart: Int64,
        identity: UInt64,
        generation: UInt64
    ) throws {
        stateLock.lock()
        guard lifecycle == .open,
              workGeneration == generation,
              inflight[chunkStart]?.identity == identity,
              inflight[chunkStart]?.generation == generation else {
            stateLock.unlock()
            throw CancellationError()
        }
        cache.write(globalOffset: chunkStart, data: data)
        inflight[chunkStart] = nil
        stateLock.unlock()
    }

    private func clearDownload(
        chunkStart: Int64,
        identity: UInt64,
        generation: UInt64
    ) {
        stateLock.lock()
        if inflight[chunkStart]?.identity == identity,
           inflight[chunkStart]?.generation == generation {
            inflight[chunkStart] = nil
        }
        stateLock.unlock()
    }

    /// 生成响应头与正文流；正文为请求的 Range（含端点）。
    public func makeResponse(rangeHeader: String?) async throws -> (Data, AsyncThrowingStream<Data, Error>) {
        do {
            _ = try await loadTotalSize()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Closed ranges can still be served when the source cannot report a total size.
        }

        let inclusive = try await resolveRange(rangeHeader: rangeHeader)
        let totalForHeader = cachedTotalSize()
        let span = inclusive.upperBound - inclusive.lowerBound + 1
        guard span > 0, span <= Int64(Int.max) else {
            throw PrefetchError.badRequest
        }
        let byteCount = Int(span)
        let header = HTTPProtocolHandler.build206(
            contentLength: byteCount,
            rangeStart: inclusive.lowerBound,
            rangeEnd: inclusive.upperBound,
            totalSize: totalForHeader
        )

        let stream = try bodyStream(inclusive: inclusive)
        return (header, stream)
    }

    // MARK: - Range

    private func resolveRange(rangeHeader: String?) async throws -> ClosedRange<Int64> {
        if let rh = rangeHeader, !rh.isEmpty, let spec = HTTPProtocolHandler.parseRangeHeader(rh) {
            switch spec {
            case .closed(let r):
                let size: Int64?
                if let cached = cachedTotalSize() {
                    size = cached
                } else {
                    size = try? await loadTotalSize()
                }
                if let sz = size {
                    let low = max(0, r.lowerBound)
                    let high = min(sz - 1, r.upperBound)
                    guard low <= high else { throw PrefetchError.badRequest }
                    return low...high
                }
                return r

            case .from(let start):
                let sz = try await loadTotalSize()
                guard sz > 0 else { throw PrefetchError.unknownSize }
                let low = max(0, start)
                guard low <= sz - 1 else { throw PrefetchError.badRequest }
                return low...(sz - 1)

            case .lastN(let n):
                let sz = try await loadTotalSize()
                guard sz > 0 else { throw PrefetchError.unknownSize }
                let start = max(0, sz - n)
                return start...(sz - 1)
            }
        }

        let sz = try await loadTotalSize()
        guard sz > 0 else { throw PrefetchError.unknownSize }
        return 0...(sz - 1)
    }

    // MARK: - Body stream

    private func bodyStream(
        inclusive: ClosedRange<Int64>
    ) throws -> AsyncThrowingStream<Data, Error> {
        let pair = AsyncThrowingStream<Data, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )

        stateLock.lock()
        guard lifecycle == .open else {
            stateLock.unlock()
            pair.continuation.finish(throwing: CancellationError())
            throw CancellationError()
        }

        // 取消旧 body 与注册新 body 必须处于同一临界区，cleanup 才不可能在两者之间
        // 截获空集合后让一个新 producer 逃逸。
        activeBodyTasks.values.forEach { $0.cancel() }
        activeBodyTasks.removeAll()
        activeBodyTaskID &+= 1
        let myID = activeBodyTaskID
        let task = Task { [weak self] in
            guard let self else {
                pair.continuation.finish(throwing: CancellationError())
                return
            }
            await self.produceBody(
                inclusive: inclusive,
                continuation: pair.continuation,
                bodyTaskID: myID
            )
        }
        activeBodyTasks[myID] = task
        stateLock.unlock()

        pair.continuation.onTermination = { [weak self] _ in
            self?.cancelBodyTask(identity: myID)
        }
        return pair.stream
    }

    private func produceBody(
        inclusive: ClosedRange<Int64>,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        bodyTaskID: UInt64
    ) async {
        let pipelineDepth = max(1, source.pipelineDepth)
        var pipeline: [(Int64, Int64, Task<Data, Error>)] = []
#if DEBUG
        let performanceStartedAt = CFAbsoluteTimeGetCurrent()
        var responseCacheHits = 0
        var responseFetches = 0
#endif

        defer {
            removeBodyTask(identity: bodyTaskID)
        }

        func cancelPending() {
            // 不取消共享下载 Task：它可能被其他 bodyStream 复用。
            // Task 跑完会自动写 cache，下次任何 bodyStream 都直接命中。
            pipeline.removeAll()
        }

        do {
            let last = inclusive.upperBound
            var yieldCursor = inclusive.lowerBound
            let firstChunkIdx = cache.chunkIndex(forGlobalOffset: inclusive.lowerBound)
            var enqueueCursor = Int64(firstChunkIdx) * Int64(chunkSize)

            func enqueueNext() throws {
                while pipeline.count < pipelineDepth && enqueueCursor <= last {
                    let chunkStart = enqueueCursor
                    let chunkEnd = min(last, chunkStart + Int64(chunkSize) - 1)
                    let byteRange = chunkStart..<(chunkEnd + 1)

                    if cache.hasEntire(range: byteRange),
                       let hit = cache.readEntire(range: byteRange) {
                        let cachedTask = Task<Data, Error> { hit }
                        pipeline.append((chunkStart, chunkEnd, cachedTask))
#if DEBUG
                        responseCacheHits += 1
#endif
                    } else {
                        let fetchTask = try sharedDownload(
                            chunkStart: chunkStart,
                            chunkEnd: chunkEnd
                        )
                        pipeline.append((chunkStart, chunkEnd, fetchTask))
#if DEBUG
                        responseFetches += 1
#endif
                    }
                    enqueueCursor = chunkEnd + 1
                }
            }

            while yieldCursor <= last {
                try Task.checkCancellation()
                try enqueueNext()
                guard !pipeline.isEmpty else { break }
                let (chunkStart, chunkEnd, task) = pipeline.removeFirst()
                let data = try await task.value
                try Task.checkCancellation()

                let sliceLow = max(yieldCursor, chunkStart)
                let sliceHigh = min(last, chunkEnd)
                let dataStart = Int(sliceLow - chunkStart)
                let dataEnd = Int(sliceHigh - chunkStart) + 1
                guard dataEnd > dataStart, dataEnd <= data.count else {
                    throw PrefetchError.badResponse
                }
                let slice = data.subdata(in: dataStart..<dataEnd)
                try await yieldWithBackpressure(slice, continuation: continuation)
                yieldCursor = sliceHigh + 1
            }

            continuation.finish()
#if DEBUG
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - performanceStartedAt) * 1_000)
            recordPerformance(
                elapsedMs: elapsedMs,
                byteCount: inclusive.upperBound - inclusive.lowerBound + 1,
                pipelineDepth: pipelineDepth,
                cacheHits: responseCacheHits,
                fetches: responseFetches
            )
#endif
        } catch is CancellationError {
            cancelPending()
            continuation.finish()
        } catch {
            VanmoLogger.prefetch.error(
                "[Prefetch] bodyStream task threw: \(String(describing: error))"
            )
            cancelPending()
            continuation.finish(throwing: error)
        }
    }

    private func yieldWithBackpressure(
        _ data: Data,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async throws {
        while true {
            try Task.checkCancellation()
            switch continuation.yield(data) {
            case .enqueued:
                return
            case .dropped:
                try await Task.sleep(for: .milliseconds(10))
            case .terminated:
                throw CancellationError()
            @unknown default:
                throw CancellationError()
            }
        }
    }

    private func removeBodyTask(identity: UInt64) {
        stateLock.lock()
        activeBodyTasks[identity] = nil
        stateLock.unlock()
    }

    private func cancelBodyTask(identity: UInt64) {
        stateLock.lock()
        let task = activeBodyTasks.removeValue(forKey: identity)
        stateLock.unlock()
        task?.cancel()
    }

#if DEBUG
    private func recordPerformance(
        elapsedMs: Int,
        byteCount: Int64,
        pipelineDepth: Int,
        cacheHits: Int,
        fetches: Int
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        stateLock.lock()
        performanceResponses += 1
        performanceBytes += byteCount
        performanceElapsedMs += elapsedMs
        performanceCacheHits += cacheHits
        performanceFetches += fetches
        guard now - performanceWindowStartedAt >= 5 else {
            stateLock.unlock()
            return
        }
        let windowMs = Int((now - performanceWindowStartedAt) * 1_000)
        let summary = (
            performanceResponses,
            performanceBytes,
            performanceElapsedMs,
            performanceCacheHits,
            performanceFetches
        )
        performanceWindowStartedAt = now
        performanceResponses = 0
        performanceBytes = 0
        performanceElapsedMs = 0
        performanceCacheHits = 0
        performanceFetches = 0
        stateLock.unlock()

        VanmoLogger.prefetch.info("[Debug][PlaybackPerf] event=prefetchResponseSummary windowMs=\(windowMs, privacy: .public) responses=\(summary.0, privacy: .public) bytes=\(summary.1, privacy: .public) elapsedMs=\(summary.2, privacy: .public) depth=\(pipelineDepth, privacy: .public) cacheHits=\(summary.3, privacy: .public) fetches=\(summary.4, privacy: .public)")
    }
#endif
}
