import Foundation

/// 按 chunk 索引缓存字节：内存 + tmp 文件，内存超限时按 LRU spill 到磁盘。
///
/// 关键不变量：每个 chunk 维护已写入的 byte 范围（`writtenIndexSets`）。
/// `hasEntire`/`readEntire` 必须严格依赖 IndexSet 判定，禁止仅凭"chunk 在内存/磁盘"
/// 这一存在性判定（partial write 后内存里的 chunk 用 0 填充未写部分，会让消费者读到错误数据）。
/// 仅完整 chunk 才持久化到磁盘；partial chunk 仅留内存且不参与 LRU evict。
final class RangeCache {
    private let chunkSize: Int
    private let maxMemoryBytes: Int
    private let lock = NSLock()

    /// chunkIndex -> 内存中的 chunk 数据（partial 或 full，未写部分以 0 填充）
    private var memoryChunks: [Int: Data] = [:]
    /// chunkIndex -> 该 chunk 内已写入的 byte 索引（in [0, chunkSize)）
    private var writtenIndexSets: [Int: IndexSet] = [:]
    /// 完整写满整个 chunk 的索引（已持久化到磁盘）
    private var fullyWrittenChunks: Set<Int> = []
    private var lruKeys: [Int] = []
    private var memoryUsage: Int = 0

    private let diskDirectory: URL

    init(sessionId: String) throws {
        self.chunkSize = PrefetchConfig.chunkSize
        self.maxMemoryBytes = PrefetchConfig.maxMemoryCache

        let dir = PrefetchTemporaryStore.sessionDirectory(sessionId: sessionId)
        self.diskDirectory = dir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Public

    func chunkIndex(forGlobalOffset offset: Int64) -> Int {
        Int(offset / Int64(chunkSize))
    }

    func hasEntire(range: Range<Int64>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !range.isEmpty else { return true }
        var pos = range.lowerBound
        while pos < range.upperBound {
            let idx = Int(pos / Int64(chunkSize))
            let chunkBase = Int64(idx) * Int64(chunkSize)
            let nextPos = min(range.upperBound, chunkBase + Int64(chunkSize))
            let queryStart = Int(pos - chunkBase)
            let queryEnd = Int(nextPos - chunkBase)
            if !chunkContainsLocked(idx: idx, range: queryStart..<queryEnd) {
                return false
            }
            pos = nextPos
        }
        return true
    }

    /// 读取区间内字节；若未完全缓存则返回 nil。
    func readEntire(range: Range<Int64>) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !range.isEmpty else { return Data() }

        var out = Data()
        var pos = range.lowerBound
        while pos < range.upperBound {
            let idx = Int(pos / Int64(chunkSize))
            let chunkBase = Int64(idx) * Int64(chunkSize)
            let offsetInChunk = Int(pos - chunkBase)
            let bytesLeftInChunk = chunkSize - offsetInChunk
            let bytesLeftInRange = Int(range.upperBound - pos)
            let take = min(bytesLeftInChunk, bytesLeftInRange)
            guard take > 0 else { return nil }
            guard chunkContainsLocked(idx: idx, range: offsetInChunk..<(offsetInChunk + take)) else {
                return nil
            }
            guard let chunk = loadChunkNoSpillLocked(index: idx), chunk.count >= offsetInChunk + take else {
                return nil
            }
            out.append(chunk[offsetInChunk..<(offsetInChunk + take)])
            touchLRULocked(idx)
            pos += Int64(take)
        }
        return out
    }

    /// 写入从 globalOffset 开始的连续字节。
    func write(globalOffset: Int64, data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var dataOffset = 0
        var globalPos = globalOffset

        while dataOffset < data.count {
            let idx = Int(globalPos / Int64(chunkSize))
            let chunkBase = Int64(idx) * Int64(chunkSize)
            let offsetInChunk = Int(globalPos - chunkBase)
            let spaceInChunk = chunkSize - offsetInChunk
            let take = min(spaceInChunk, data.count - dataOffset)

            var chunk = memoryChunks[idx]
                ?? loadChunkFromDiskNoLRULocked(index: idx)
                ?? Data(count: chunkSize)

            if chunk.count < chunkSize {
                chunk.append(Data(count: chunkSize - chunk.count))
            }
            let slice = data[dataOffset..<(dataOffset + take)]
            chunk.replaceSubrange(offsetInChunk..<(offsetInChunk + take), with: slice)

            var writtenSet = writtenIndexSets[idx] ?? IndexSet()
            writtenSet.insert(integersIn: offsetInChunk..<(offsetInChunk + take))
            let isFullyWritten = writtenSet.contains(integersIn: 0..<chunkSize)
            if isFullyWritten {
                writtenIndexSets.removeValue(forKey: idx)
                fullyWrittenChunks.insert(idx)
            } else {
                writtenIndexSets[idx] = writtenSet
            }

            installChunkLocked(index: idx, data: chunk, fullyWritten: isFullyWritten)

            dataOffset += take
            globalPos += Int64(take)
        }
    }

    func removeAll() {
        lock.lock()
        memoryChunks.removeAll()
        writtenIndexSets.removeAll()
        fullyWrittenChunks.removeAll()
        lruKeys.removeAll()
        memoryUsage = 0
        lock.unlock()

        try? FileManager.default.removeItem(at: diskDirectory)
    }

    // MARK: - Private

    private func chunkContainsLocked(idx: Int, range: Range<Int>) -> Bool {
        // 完整 chunk 命中（在内存或可从磁盘恢复）
        if fullyWrittenChunks.contains(idx) {
            return true
        }
        // partial chunk：必须严格按 IndexSet 判定
        if let set = writtenIndexSets[idx] {
            return set.contains(integersIn: range)
        }
        return false
    }

    private func loadChunkNoSpillLocked(index: Int) -> Data? {
        if let mem = memoryChunks[index] {
            return mem
        }
        return loadChunkFromDiskNoLRULocked(index: index)
    }

    private func loadChunkFromDiskNoLRULocked(index: Int) -> Data? {
        let url = diskURL(for: index)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let d = try Data(contentsOf: url)
            // 磁盘里只放完整 chunk，恢复时同步标记
            fullyWrittenChunks.insert(index)
            writtenIndexSets.removeValue(forKey: index)
            installChunkLocked(index: index, data: d, fullyWritten: true)
            return memoryChunks[index]
        } catch {
            VanmoLogger.prefetch.error("[Prefetch] read disk chunk \(index) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func diskURL(for index: Int) -> URL {
        diskDirectory.appendingPathComponent("\(index).bin", isDirectory: false)
    }

    private func installChunkLocked(index: Int, data: Data, fullyWritten: Bool) {
        if let old = memoryChunks[index] {
            memoryUsage -= old.count
        }
        memoryChunks[index] = data
        memoryUsage += data.count
        touchLRULocked(index)
        spillIfNeededLocked()

        // 仅完整 chunk 持久化到磁盘；partial chunk 留在内存即可。
        guard fullyWritten else { return }
        let url = diskURL(for: index)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            VanmoLogger.prefetch.error("[Prefetch] persist chunk failed index=\(index): \(error.localizedDescription)")
        }
    }

    private func touchLRULocked(_ index: Int) {
        if let i = lruKeys.firstIndex(of: index) {
            lruKeys.remove(at: i)
        }
        lruKeys.append(index)
    }

    private func spillIfNeededLocked() {
        // 仅 evict 完整 chunk（已持久化），partial chunk 必须留在内存
        // 否则 partial 数据丢失后再被 hasEntire 误判会回到 EBML 错误。
        var idx = 0
        while memoryUsage > maxMemoryBytes && idx < lruKeys.count {
            let candidate = lruKeys[idx]
            if fullyWrittenChunks.contains(candidate) {
                lruKeys.remove(at: idx)
                if let data = memoryChunks.removeValue(forKey: candidate) {
                    memoryUsage -= data.count
                }
            } else {
                idx += 1
            }
        }
    }
}
