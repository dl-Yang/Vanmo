import Foundation

protocol PrefetchByteSource: AnyObject, Sendable {
    func probeTotalSize() async throws -> Int64
    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data
    func close() async
}

final class HTTPPrefetchByteSource: PrefetchByteSource, @unchecked Sendable {
    private let fetcher: RemoteFetcher

    init(url: URL, headerProvider: (() async -> [String: String])? = nil) {
        self.fetcher = RemoteFetcher(originalURL: url, headerProvider: headerProvider)
    }

    func probeTotalSize() async throws -> Int64 {
        try await fetcher.probeTotalSize()
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        let (data, response) = try await fetcher.data(forInclusiveRange: range)
        guard let http = response as? HTTPURLResponse else {
            throw PrefetchError.badResponse
        }
        if http.statusCode == 416 {
            throw PrefetchError.badRequest
        }
        guard (200...299).contains(http.statusCode) else {
            throw PrefetchError.upstream(http.statusCode)
        }
        return data
    }

    func close() async {}
}

actor SMBPrefetchByteSource: PrefetchByteSource {
    private let url: URL
    private var service: SMBService?
    private var path: String?
    private var readBusy = false
    private var readWaiters: [CheckedContinuation<Void, Never>] = []

    init(url: URL) {
        self.url = url
    }

    func probeTotalSize() async throws -> Int64 {
        await acquireRead()
        defer { releaseRead() }
        let (service, path) = try await ensureConnected()
        return try await service.fileSize(at: path)
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        await acquireRead()
        defer { releaseRead() }
        let (service, path) = try await ensureConnected()
        var offset = UInt64(range.lowerBound)
        let end = UInt64(range.upperBound) + 1
        var collected = Data()
        collected.reserveCapacity(Int(min(end - offset, 1_048_576)))
        while offset < end {
            let remaining = end - offset
            let chunk = UInt32(min(remaining, UInt64(PrefetchConfig.chunkSize)))
            let data = try await service.readRange(at: path, offset: offset, length: chunk)
            if data.isEmpty {
                throw PrefetchError.badResponse
            }
            collected.append(data)
            offset += UInt64(data.count)
        }
        return collected
    }

    func close() async {
        await service?.disconnect()
        service = nil
        path = nil
    }

    private func ensureConnected() async throws -> (SMBService, String) {
        if let service, let path, service.isConnected {
            return (service, path)
        }
        guard let target = SMBConnectionEndpoint.playbackTarget(from: url) else {
            throw NetworkError.invalidURL
        }
        let service = SMBService()
        try await service.connect(config: target.config)
        self.service = service
        self.path = target.path
        return (service, target.path)
    }

    private func acquireRead() async {
        if !readBusy {
            readBusy = true
            return
        }
        await withCheckedContinuation { readWaiters.append($0) }
    }

    private func releaseRead() {
        if let next = readWaiters.first {
            readWaiters.removeFirst()
            next.resume()
        } else {
            readBusy = false
        }
    }
}
