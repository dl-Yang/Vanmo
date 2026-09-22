import Foundation

protocol PrefetchByteSource: AnyObject, Sendable {
    var pipelineDepth: Int { get }

    func probeTotalSize() async throws -> Int64
    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data
    func close() async
}

final class HTTPPrefetchByteSource: PrefetchByteSource, @unchecked Sendable {
    let pipelineDepth = PrefetchConfig.httpPipelineDepth

    private let fetcher: RemoteFetcher

    init(url: URL, headerProvider: (() async -> [String: String])? = nil) {
        self.fetcher = RemoteFetcher(originalURL: url, headerProvider: headerProvider)
    }

    func probeTotalSize() async throws -> Int64 {
        try await fetcher.probeTotalSize()
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        let (data, response) = try await fetcher.data(forInclusiveRange: range)
        _ = try RemoteFetcher.validateRangeResponse(
            data: data,
            response: response,
            requestedRange: range
        )
        return data
    }

    func close() async {
        fetcher.close()
    }
}

actor SMBPrefetchByteSource: PrefetchByteSource {
    nonisolated let pipelineDepth = 1

    private let url: URL
    private let readGate = CancellableReadGate()
    private var service: SMBService?
    private var path: String?
    private var isClosed = false

    init(url: URL) {
        self.url = url
    }

    func probeTotalSize() async throws -> Int64 {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            let size = try await service.fileSize(at: path)
            try ensureOpen()
            await readGate.release()
            return size
        } catch {
            await readGate.release()
            throw error
        }
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            var offset = UInt64(range.lowerBound)
            let end = UInt64(range.upperBound) + 1
            var collected = Data()
            collected.reserveCapacity(Int(min(end - offset, 1_048_576)))
            while offset < end {
                try ensureOpen()
                let remaining = end - offset
                let chunk = UInt32(min(remaining, UInt64(PrefetchConfig.chunkSize)))
                let data = try await service.readRange(at: path, offset: offset, length: chunk)
                try ensureOpen()
                if data.isEmpty {
                    throw PrefetchError.badResponse
                }
                collected.append(data)
                offset += UInt64(data.count)
            }
            await readGate.release()
            return collected
        } catch {
            await readGate.release()
            throw error
        }
    }

    func close() async {
        isClosed = true
        await readGate.beginClose()
        await service?.disconnect()
        await readGate.waitUntilClosed()
        service = nil
        path = nil
    }

    private func ensureConnected() async throws -> (SMBService, String) {
        try ensureOpen()
        if let service, let path, service.isConnected {
            return (service, path)
        }
        guard let target = SMBConnectionEndpoint.playbackTarget(from: url) else {
            throw NetworkError.invalidURL
        }
        let service = SMBService()
        try await service.connect(config: target.config)
        do {
            try ensureOpen()
        } catch {
            await service.disconnect()
            throw error
        }
        self.service = service
        self.path = target.path
        return (service, target.path)
    }

    private func ensureOpen() throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
    }
}

actor FTPPrefetchByteSource: PrefetchByteSource {
    nonisolated let pipelineDepth = 1

    private let url: URL
    private let readGate = CancellableReadGate()
    private var service: FTPService?
    private var path: String?
    private var isClosed = false

    init(url: URL) {
        self.url = url
    }

    func probeTotalSize() async throws -> Int64 {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            let size = try await service.fileSize(at: path)
            try ensureOpen()
            await readGate.release()
            return size
        } catch {
            await readGate.release()
            throw error
        }
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            var offset = UInt64(range.lowerBound)
            let end = UInt64(range.upperBound) + 1
            var collected = Data()
            collected.reserveCapacity(Int(min(end - offset, 1_048_576)))
            while offset < end {
                try ensureOpen()
                let remaining = end - offset
                let chunk = UInt32(min(remaining, UInt64(PrefetchConfig.chunkSize)))
                let data = try await service.readRange(at: path, offset: offset, length: chunk)
                try ensureOpen()
                if data.isEmpty {
                    throw PrefetchError.badResponse
                }
                collected.append(data)
                offset += UInt64(data.count)
            }
            await readGate.release()
            return collected
        } catch {
            await readGate.release()
            throw error
        }
    }

    func close() async {
        isClosed = true
        await readGate.beginClose()
        await service?.disconnect()
        await readGate.waitUntilClosed()
        service = nil
        path = nil
    }

    private func ensureConnected() async throws -> (FTPService, String) {
        try ensureOpen()
        if let service, let path, service.isConnected {
            return (service, path)
        }
        guard let target = FTPService.playbackTarget(from: url) else {
            throw NetworkError.invalidURL
        }
        let service = FTPService()
        try await service.connect(config: target.config)
        do {
            try ensureOpen()
        } catch {
            await service.disconnect()
            throw error
        }
        self.service = service
        self.path = target.path
        return (service, target.path)
    }

    private func ensureOpen() throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
    }
}

actor SFTPPrefetchByteSource: PrefetchByteSource {
    nonisolated let pipelineDepth = 1

    private let url: URL
    private let readGate = CancellableReadGate()
    private var service: SFTPService?
    private var path: String?
    private var isClosed = false

    init(url: URL) {
        self.url = url
    }

    func probeTotalSize() async throws -> Int64 {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            let size = try await service.fileSize(at: path)
            try ensureOpen()
            await readGate.release()
            return size
        } catch {
            await readGate.release()
            throw error
        }
    }

    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> Data {
        try await readGate.acquire()
        do {
            try ensureOpen()
            let (service, path) = try await ensureConnected()
            var offset = UInt64(range.lowerBound)
            let end = UInt64(range.upperBound) + 1
            var collected = Data()
            collected.reserveCapacity(Int(min(end - offset, 1_048_576)))
            while offset < end {
                try ensureOpen()
                let remaining = end - offset
                let chunk = UInt32(min(remaining, UInt64(PrefetchConfig.chunkSize)))
                let data = try await service.readRange(at: path, offset: offset, length: chunk)
                try ensureOpen()
                if data.isEmpty {
                    throw PrefetchError.badResponse
                }
                collected.append(data)
                offset += UInt64(data.count)
            }
            await readGate.release()
            return collected
        } catch {
            await readGate.release()
            throw error
        }
    }

    func close() async {
        isClosed = true
        await readGate.beginClose()
        await service?.disconnect()
        await readGate.waitUntilClosed()
        service = nil
        path = nil
    }

    private func ensureConnected() async throws -> (SFTPService, String) {
        try ensureOpen()
        if let service, let path, service.isConnected {
            return (service, path)
        }
        guard let target = SFTPService.playbackTarget(from: url) else {
            throw NetworkError.invalidURL
        }
        let service = SFTPService()
        try await service.connect(config: target.config)
        do {
            try ensureOpen()
        } catch {
            await service.disconnect()
            throw error
        }
        self.service = service
        self.path = target.path
        return (service, target.path)
    }

    private func ensureOpen() throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
    }
}
