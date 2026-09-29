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
    private var startWaiters: [CheckedContinuation<UInt16, Error>] = []
    private let queue = DispatchQueue(label: "vanmo.hls.segment")

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
        if let port { return port }
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
                        waiters.forEach { $0.resume(returning: readyPort) }
                    case .failed(let error):
                        self.lock.lock()
                        let waiters = self.startWaiters
                        self.startWaiters = []
                        self.lock.unlock()
                        waiters.forEach { $0.resume(throwing: error) }
                    default:
                        break
                    }
                }
                nwListener.newConnectionHandler = { [weak self] connection in
                    connection.start(queue: self?.queue ?? .global())
                    self?.serve(connection)
                }
                nwListener.start(queue: queue)
            } catch {
                lock.lock()
                let waiters = startWaiters
                startWaiters = []
                lock.unlock()
                waiters.forEach { $0.resume(throwing: error) }
            }
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, let data, error == nil,
                  let header = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
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
            self.lock.lock()
            let source = self.sources[id]
            self.lock.unlock()
            guard let source else {
                self.send(connection, status: "404 Not Found", body: Data())
                return
            }
            Task {
                var urlRequest = URLRequest(url: source)
                urlRequest.timeoutInterval = 45
                urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
                do {
                    let (payload, _) = try await URLSession.shared.data(for: urlRequest)
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
                    self.send(connection, status: "200 OK", body: body, range: rangeLine)
                } catch {
                    self.send(connection, status: "502 Bad Gateway", body: Data())
                }
            }
        }
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
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
