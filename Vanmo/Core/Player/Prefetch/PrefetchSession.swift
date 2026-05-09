import Foundation

/// 单个远程资源的预缓存会话。
final class PrefetchSession {
    let token: String

    private let cache: RangeCache
    private let fetcher: RemoteFetcher
    private let chunkSize: Int

    private var totalSize: Int64?

    /// 同一 chunk 的下载共享同一个 Task，避免不同 GET 触发的多个 bodyStream 重复回源。
    /// 任一 task 完成后从 map 移除；移除时机使用 lock 同步保证可见性。
    private var inflight: [Int64: Task<Data, Error>] = [:]
    private let inflightLock = NSLock()

    /// 当前活跃的 bodyStream tasks。新 GET 进来时主动取消旧的 bodyStream，避免
    /// 多个"幽灵 bodyStream"持续下载浪费带宽（FFmpeg 不再读老 connection，但
    /// AsyncThrowingStream 默认 unbounded buffer 不会反压 producer）。
    private var activeBodyTaskID: UInt64 = 0
    private var activeBodyTasks: [UInt64: Task<Void, Never>] = [:]
    private let activeBodyTasksLock = NSLock()

    init(token: String, originalURL: URL) throws {
        self.token = token
        self.cache = try RangeCache(sessionId: token)
        self.fetcher = RemoteFetcher(originalURL: originalURL)
        self.chunkSize = PrefetchConfig.chunkSize
    }

    func cleanup() {
        cache.removeAll()
        inflightLock.lock()
        for (_, t) in inflight { t.cancel() }
        inflight.removeAll()
        inflightLock.unlock()
        activeBodyTasksLock.lock()
        for (_, t) in activeBodyTasks { t.cancel() }
        activeBodyTasks.removeAll()
        activeBodyTasksLock.unlock()
    }

    /// 复用或创建 chunk 的下载 Task。多个 bodyStream pipeline 可共享同一 Task，避免重复回源。
    /// 注意：返回的 Task 不应被单个 bodyStream 取消（取消会影响所有等待者），
    /// 仅在 session cleanup 时一并取消。
    private func sharedDownload(chunkStart: Int64, chunkEnd: Int64) -> Task<Data, Error> {
        inflightLock.lock()
        if let existing = inflight[chunkStart] {
            inflightLock.unlock()
            return existing
        }
        let task = Task<Data, Error>.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            await FetchLimiter.shared.acquire()
            let releaseAndCleanup: () -> Void = {
                Task { await FetchLimiter.shared.release() }
                self.inflightLock.lock()
                self.inflight[chunkStart] = nil
                self.inflightLock.unlock()
            }
            do {
                try Task.checkCancellation()
                let (data, response) = try await self.fetcher.data(forInclusiveRange: chunkStart...chunkEnd)
                guard let http = response as? HTTPURLResponse else {
                    releaseAndCleanup()
                    throw PrefetchError.badResponse
                }
                if http.statusCode == 416 {
                    releaseAndCleanup()
                    throw PrefetchError.badRequest
                }
                guard (200...299).contains(http.statusCode) else {
                    releaseAndCleanup()
                    throw PrefetchError.upstream(http.statusCode)
                }
                if self.totalSize == nil,
                   let crHeader = http.value(forHTTPHeaderField: "Content-Range"),
                   let t = RemoteFetcher.parseContentRangeTotal(crHeader) {
                    self.totalSize = t
                }
                self.cache.write(globalOffset: chunkStart, data: data)
                releaseAndCleanup()
                return data
            } catch {
                releaseAndCleanup()
                throw error
            }
        }
        inflight[chunkStart] = task
        inflightLock.unlock()
        return task
    }

    /// 生成响应头与正文流；正文为请求的 Range（含端点）。
    func makeResponse(rangeHeader: String?) async throws -> (Data, AsyncThrowingStream<Data, Error>) {
        if totalSize == nil {
            totalSize = try? await fetcher.probeTotalSize()
        }

        let inclusive = try await resolveRange(rangeHeader: rangeHeader)

        if totalSize == nil {
            totalSize = try? await fetcher.probeTotalSize()
        }

        let totalForHeader = totalSize
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

        let stream = bodyStream(inclusive: inclusive)
        return (header, stream)
    }

    // MARK: - Range

    private func resolveRange(rangeHeader: String?) async throws -> ClosedRange<Int64> {
        if let rh = rangeHeader, !rh.isEmpty, let spec = HTTPProtocolHandler.parseRangeHeader(rh) {
            switch spec {
            case .closed(let r):
                if totalSize == nil {
                    totalSize = try? await fetcher.probeTotalSize()
                }
                if let sz = totalSize {
                    let low = max(0, r.lowerBound)
                    let high = min(sz - 1, r.upperBound)
                    guard low <= high else { throw PrefetchError.badRequest }
                    return low...high
                }
                return r

            case .from(let start):
                if totalSize == nil {
                    totalSize = try await fetcher.probeTotalSize()
                }
                guard let sz = totalSize, sz > 0 else { throw PrefetchError.unknownSize }
                let low = max(0, start)
                guard low <= sz - 1 else { throw PrefetchError.badRequest }
                return low...(sz - 1)

            case .lastN(let n):
                if totalSize == nil {
                    totalSize = try await fetcher.probeTotalSize()
                }
                guard let sz = totalSize, sz > 0 else { throw PrefetchError.unknownSize }
                let start = max(0, sz - n)
                return start...(sz - 1)
            }
        }

        if totalSize == nil {
            totalSize = try await fetcher.probeTotalSize()
        }
        guard let sz = totalSize, sz > 0 else { throw PrefetchError.unknownSize }
        return 0...(sz - 1)
    }

    // MARK: - Body stream

    private func bodyStream(inclusive: ClosedRange<Int64>) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            // 先取消所有旧的 bodyStream task：FFmpeg 发新 GET 通常意味着旧 GET 已废弃，
            // 旧 stream 不主动 cancel 会持续浪费带宽（unbounded buffer 不反压）。
            activeBodyTasksLock.lock()
            activeBodyTaskID += 1
            let myID = activeBodyTaskID
            let toCancel = activeBodyTasks
            activeBodyTasks.removeAll()
            activeBodyTasksLock.unlock()
            for (_, t) in toCancel { t.cancel() }

            let task = Task {
                let pipelineDepth = PrefetchConfig.maxConcurrentFetches
                var pipeline: [(Int64, Int64, Task<Data, Error>)] = []

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

                    func enqueueNext() {
                        while pipeline.count < pipelineDepth && enqueueCursor <= last {
                            let chunkStart = enqueueCursor
                            let chunkEnd = min(last, chunkStart + Int64(chunkSize) - 1)
                            let byteRange = chunkStart..<(chunkEnd + 1)

                            if cache.hasEntire(range: byteRange),
                               let hit = cache.readEntire(range: byteRange) {
                                let cachedTask = Task<Data, Error> { hit }
                                pipeline.append((chunkStart, chunkEnd, cachedTask))
                            } else {
                                let fetchTask = self.sharedDownload(chunkStart: chunkStart, chunkEnd: chunkEnd)
                                pipeline.append((chunkStart, chunkEnd, fetchTask))
                            }
                            enqueueCursor = chunkEnd + 1
                        }
                    }

                    while yieldCursor <= last {
                        try Task.checkCancellation()
                        enqueueNext()
                        guard !pipeline.isEmpty else { break }
                        let (chunkStart, chunkEnd, t) = pipeline.removeFirst()
                        let data = try await t.value
                        try Task.checkCancellation()

                        let sliceLow = max(yieldCursor, chunkStart)
                        let sliceHigh = min(last, chunkEnd)
                        let dataStart = Int(sliceLow - chunkStart)
                        let dataEnd = Int(sliceHigh - chunkStart) + 1
                        if dataEnd > dataStart, dataEnd <= data.count {
                            let slice = data.subdata(in: dataStart..<dataEnd)
                            continuation.yield(slice)
                        }
                        yieldCursor = chunkEnd + 1
                    }

                    continuation.finish()
                } catch is CancellationError {
                    cancelPending()
                    continuation.finish()
                } catch {
                    VanmoLogger.prefetch.error("[Prefetch] bodyStream task threw: \(String(describing: error))")
                    cancelPending()
                    continuation.finish(throwing: error)
                }
            }
            activeBodyTasksLock.lock()
            activeBodyTasks[myID] = task
            activeBodyTasksLock.unlock()

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                guard let self else { return }
                self.activeBodyTasksLock.lock()
                self.activeBodyTasks[myID] = nil
                self.activeBodyTasksLock.unlock()
            }
        }
    }
}
