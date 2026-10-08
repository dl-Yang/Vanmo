import Foundation
import Network
import VanmoCore

/// 把 Emby 的 MPEG-TS 分段转到 `127.0.0.1`，并在音频时间戳偏离视频时对齐。
/// 自定义 `vanmo-hls` 地址只能改播放列表；分段走那个地址时 AVPlayer 会直接失败。
final class HlsSegmentFixServer {
    static let shared = HlsSegmentFixServer()

    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?
    private var sources: [String: URL] = [:]
    private var segmentBodies: [String: Data] = [:]
    private var segmentOrder: [String] = []
    private var segmentTasks: [String: Task<Data, Error>] = [:]
    private var startWaiters: [CheckedContinuation<UInt16, Error>] = []
    private let segmentCacheLimit = 4
    private let listenerQueue = DispatchQueue(label: "vanmo.hls.listener")
    private let connectionQueue = DispatchQueue(label: "vanmo.hls.connection")
    private let downloadGate = SegmentDownloadGate(limit: 2)
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func rewrite(playlist: String) async -> String {
        let lines = playlist.components(separatedBy: "\n")
        let hasSegment = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.contains(".ts")
        }
        guard hasSegment else { return playlist }
        let boundPort: UInt16
        do {
            boundPort = try await ensurePort()
        } catch {
            return playlist
        }
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  trimmed.lowercased().contains(".ts"),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return line
            }
            let id = UUID().uuidString
            lock.lock()
            sources[id] = url
            lock.unlock()
            return "http://127.0.0.1:\(boundPort)/s/\(id).ts"
        }.joined(separator: "\n")
    }

    private func ensurePort() async throws -> UInt16 {
        lock.lock()
        if let port {
            lock.unlock()
            return port
        }
        lock.unlock()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let port {
                lock.unlock()
                continuation.resume(returning: port)
                return
            }
            let isFirst = startWaiters.isEmpty
            startWaiters.append(continuation)
            lock.unlock()
            guard isFirst else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let nwListener = try NWListener(using: parameters, on: .any)
                nwListener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let readyPort = nwListener.port?.rawValue ?? 0
                        self.lock.lock()
                        self.listener = nwListener
                        self.port = readyPort
                        let waiters = self.startWaiters
                        self.startWaiters = []
                        self.lock.unlock()
                        self.resume(waiters, result: .success(readyPort))
                    case .failed(let error):
                        self.lock.lock()
                        let waiters = self.startWaiters
                        self.startWaiters = []
                        self.lock.unlock()
                        self.resume(waiters, result: .failure(error))
                    default:
                        break
                    }
                }
                nwListener.newConnectionHandler = { [weak self] connection in
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    connection.start(queue: self.connectionQueue)
                    self.connectionQueue.async {
                        self.serve(connection)
                    }
                }
                nwListener.start(queue: listenerQueue)
            } catch {
                lock.lock()
                let waiters = startWaiters
                startWaiters = []
                lock.unlock()
                waiters.forEach { $0.resume(throwing: error) }
            }
        }
    }

    /// 监听队列只负责接受状态。等待者在别的队列上继续，避免改写播放列表时占住 accept。
    private func resume(_ waiters: [CheckedContinuation<UInt16, Error>], result: Result<UInt16, Error>) {
        DispatchQueue.global(qos: .userInitiated).async {
            for waiter in waiters {
                switch result {
                case .success(let port):
                    waiter.resume(returning: port)
                case .failure(let error):
                    waiter.resume(throwing: error)
                }
            }
        }
    }

    private func serve(_ connection: NWConnection) {
        readRequest(connection, buffer: Data())
    }

    /// 第一包经常不是完整请求。读到头结束再响应，避免把半个请求掐掉后让播放器重试。
    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            buffer.append(data)
            let marker = Data("\r\n\r\n".utf8)
            guard let end = buffer.range(of: marker) else {
                if isComplete || buffer.count > 65_536 {
                    connection.cancel()
                    return
                }
                self.readRequest(connection, buffer: buffer)
                return
            }
            let headerData = Data(buffer[..<end.lowerBound])
            guard let header = String(data: headerData, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.handle(header: header, connection: connection)
        }
    }

    private func handle(header: String, connection: NWConnection) {
        let firstLine = header.split(separator: "\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let path = String(parts[1])
        let rangeLine = header
            .split(separator: "\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let id = path
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: ".ts", with: "") } ?? ""
        lock.lock()
        let source = sources[id]
        lock.unlock()
        guard let source else {
            send(connection, status: "404 Not Found", body: Data())
            return
        }
#if DEBUG
        let shortID = String(id.prefix(8))
        VanmoLogger.player.info("[Debug][Player] event=videoQualitySegmentRequest id=\(shortID, privacy: .public)")
#endif
        Task {
            do {
                let body = try await self.fixedBody(id: id, source: source)
                self.send(connection, status: "200 OK", body: body, range: rangeLine)
            } catch {
                self.send(connection, status: "502 Bad Gateway", body: Data())
            }
        }
    }

    /// 同一个分段只下载和对齐一次。播放器重试或并行请求都复用结果。
    private func fixedBody(id: String, source: URL) async throws -> Data {
        let task: Task<Data, Error>
        lock.lock()
        if let cached = segmentBodies[id] {
            lock.unlock()
            return cached
        }
        if let existing = segmentTasks[id] {
            lock.unlock()
            return try await existing.value
        }
        if let primed = HlsPrimedSegmentStore.data(for: source) {
            lock.unlock()
            let body = Self.aligned(primed)
            storeSegment(id: id, body: body)
            return body
        }
        task = Task { [weak self] () throws -> Data in
            guard let self else { throw URLError(.cancelled) }
            await self.downloadGate.acquire()
            defer { self.downloadGate.release() }
            var urlRequest = URLRequest(url: source)
            urlRequest.timeoutInterval = 45
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (payload, _) = try await self.session.data(for: urlRequest)
            return Self.aligned(payload)
        }
        segmentTasks[id] = task
        lock.unlock()

        do {
            let body = try await task.value
            storeSegment(id: id, body: body)
            return body
        } catch {
            lock.lock()
            segmentTasks[id] = nil
            lock.unlock()
            throw error
        }
    }

    private func storeSegment(id: String, body: Data) {
        lock.lock()
        segmentTasks[id] = nil
        if segmentBodies[id] == nil {
            segmentOrder.append(id)
        }
        segmentBodies[id] = body
        while segmentOrder.count > segmentCacheLimit, let oldest = segmentOrder.first {
            segmentOrder.removeFirst()
            if oldest != id {
                segmentBodies.removeValue(forKey: oldest)
            }
        }
        lock.unlock()
    }

    private func send(_ connection: NWConnection, status: String, body: Data, range: String? = nil) {
        var payload = body
        var statusLine = status
        var extra = ""
        let rangeValue = range.map { line -> String in
            guard let colon = line.firstIndex(of: ":") else { return line }
            return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        if status.hasPrefix("200"), let rangeValue, let spec = HTTPProtocolHandler.parseRangeHeader(rangeValue) {
            let total = Int64(body.count)
            let start: Int64
            let end: Int64
            switch spec {
            case .closed(let closed):
                start = closed.lowerBound
                end = min(closed.upperBound, total - 1)
            case .from(let fromStart):
                start = fromStart
                end = total - 1
            case .lastN(let count):
                start = max(0, total - count)
                end = total - 1
            }
            if start >= 0, end >= start, end < total {
                payload = body.subdata(in: Int(start)..<Int(end + 1))
                statusLine = "206 Partial Content"
                extra = "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
            }
        }
        var header = "HTTP/1.1 \(statusLine)\r\n"
        header += "Content-Type: video/MP2T\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += extra
        header += "Connection: close\r\n\r\n"
        var bytes = Data(header.utf8)
        bytes.append(payload)
#if DEBUG
        let sentStatus = statusLine
        let sentBytes = payload.count
        VanmoLogger.player.info("[Debug][Player] event=videoQualitySegmentSend status=\(sentStatus, privacy: .public) bytes=\(sentBytes, privacy: .public)")
#endif
        // cancel() 会发 RST，播放器收不齐 Content-Length 就会每 3 秒重试同一个分段。
        connection.send(content: bytes, isComplete: true, completion: .contentProcessed { error in
            guard error == nil else {
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                connection.cancel()
            }
        })
    }

    private static func aligned(_ payload: Data) -> Data {
        let aligned = MpegTsTiming.aligningAudioToVideo(payload)
        let body = aligned?.data ?? payload
#if DEBUG
        if let aligned {
            let action = aligned.action.rawValue
            let startLead = aligned.startLeadMilliseconds
            let overlapLead = aligned.overlapLeadMilliseconds.map(String.init) ?? "none"
            VanmoLogger.player.info("[Debug][Player] event=videoQualitySegmentFix action=\(action, privacy: .public) startLeadMs=\(startLead, privacy: .public) overlapLeadMs=\(overlapLead, privacy: .public) bytes=\(body.count, privacy: .public)")
        }
#endif
        return body
    }
}

/// 同时只下载两个分段。整片 VOD 列表不会一次把每个 `.ts` 拉进内存做对齐。
private final class SegmentDownloadGate: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        lock.lock()
        if inFlight < limit {
            inFlight += 1
            lock.unlock()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        if waiters.isEmpty {
            inFlight = max(0, inFlight - 1)
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.resume()
    }
}
