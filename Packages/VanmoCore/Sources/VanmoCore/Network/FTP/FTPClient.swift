import Foundation
import Network

/// Minimal RFC 959 FTP client: PASV/EPSV, MLSD/LIST, SIZE, REST, RETR.
actor FTPClient {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String

    private var control: NWConnection?
    private var incoming = Data()
    private var isReady = false

    init(host: String, port: Int, username: String?, password: String?) {
        self.host = host
        self.port = port > 0 ? port : 21
        self.username = username?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "anonymous"
        self.password = password ?? ""
    }

    func login() async throws {
        if isReady { return }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 21,
            using: .tcp
        )
        try await start(connection)
        control = connection
        incoming = Data()

        let greeting = try await readResponse()
        guard greeting.code == 220 else {
            throw NetworkError.connectionFailed(greeting.message)
        }

        let userReply = try await send("USER \(username)")
        if userReply.code == 331 {
            let passReply = try await send("PASS \(password)")
            guard passReply.code == 230 else {
                throw NetworkError.authenticationFailed
            }
        } else if userReply.code != 230 {
            throw NetworkError.authenticationFailed
        }

        _ = try? await send("TYPE I")
        _ = try? await send("OPTS UTF8 ON")
        isReady = true
        let hasPassword = password.isEmpty ? "no" : "yes"
        VanmoLogger.network.info("[FTP] login ok host=\(self.host) port=\(self.port) user=\(self.username) hasPassword=\(hasPassword)")
    }

    func quit() async {
        if isReady {
            _ = try? await send("QUIT")
        }
        control?.cancel()
        control = nil
        incoming = Data()
        isReady = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        try await ensureReady()
        let normalized = FTPListingParser.normalizePath(path)
        try await changeDirectory(normalized)
        let listing: String
        do {
            listing = try await transferText(command: "MLSD")
        } catch {
            listing = try await transferText(command: "LIST")
        }
        let files = FTPListingParser.parseListing(listing, directoryPath: normalized)
        VanmoLogger.network.info("[FTP] listed \(files.count) entries under \(normalized)")
        return files
    }

    func fileSize(at path: String) async throws -> Int64 {
        try await ensureReady()
        let reply = try await send("SIZE \(ftpPath(path))")
        if reply.code == 213, let size = Self.parseSize(reply.message) {
            return size
        }
        let normalized = FTPListingParser.normalizePath(path)
        let parent = (normalized as NSString).deletingLastPathComponent
        let name = (normalized as NSString).lastPathComponent
        let listed = try await listDirectory(path: parent.isEmpty ? "/" : parent)
        if let match = listed.first(where: { $0.name == name && $0.size > 0 }) {
            return match.size
        }
        throw NetworkError.transferFailed(reply.message)
    }

    func readRange(path: String, offset: UInt64, length: UInt32) async throws -> Data {
        try await ensureReady()
        let dataConnection = try await beginRetrieve(path: path, offset: offset)
        let data = try await receiveData(from: dataConnection, limit: Int(length))
        dataConnection.cancel()
        _ = try? await readResponse()
        return data
    }

    func downloadResuming(
        path: String,
        to localURL: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        try await ensureReady()
        if !FileManager.default.fileExists(atPath: localURL.path) {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        var offset = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let total: Int64
        if expectedSize > 0 {
            total = expectedSize
        } else if let sized = try? await fileSize(at: path) {
            total = sized
        } else {
            total = 0
        }
        if total > 0, offset > total {
            let handle = try FileHandle(forWritingTo: localURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
            offset = 0
        }

        let dataConnection = try await beginRetrieve(path: path, offset: UInt64(offset))

        let destination = try FileHandle(forWritingTo: localURL)
        defer { try? destination.close() }
        try destination.seekToEnd()

        try await receiveData(from: dataConnection, timeoutSeconds: nil) { chunk in
            try destination.write(contentsOf: chunk)
            offset += Int64(chunk.count)
            progress(offset, total)
        }
        dataConnection.cancel()
        try destination.synchronize()
        _ = try? await readResponse()

        if total > 0, offset < total {
            throw NetworkError.transferFailed("FTP 下载提前结束")
        }
    }

    // MARK: - Control

    private func ensureReady() async throws {
        if isReady, control != nil { return }
        isReady = false
        control?.cancel()
        control = nil
        incoming = Data()
        try await login()
    }

    private func changeDirectory(_ path: String) async throws {
        let target = ftpPath(path)
        let reply = try await send("CWD \(target)")
        if reply.code == 250 { return }
        if target == "/" {
            VanmoLogger.network.info("[FTP] CWD / skipped (\(reply.code)); using login home")
            return
        }
        let relative = String(target.drop(while: { $0 == "/" }))
        if !relative.isEmpty {
            let retry = try await send("CWD \(relative)")
            if retry.code == 250 { return }
        }
        throw NetworkError.transferFailed(reply.message)
    }

    private func beginRetrieve(path: String, offset: UInt64) async throws -> NWConnection {
        let absolute = ftpPath(path)
        do {
            return try await openRetrieve(path: absolute, offset: offset)
        } catch {
            let name = (absolute as NSString).lastPathComponent
            let parent = (absolute as NSString).deletingLastPathComponent
            guard !name.isEmpty, name != absolute else { throw error }
            try await changeDirectory(parent.isEmpty ? "/" : parent)
            return try await openRetrieve(path: name, offset: offset)
        }
    }

    private func openRetrieve(path: String, offset: UInt64) async throws -> NWConnection {
        let endpoint = try await openPassive()
        let dataConnection = try await connectData(endpoint)
        if offset > 0 {
            let rest = try await send("REST \(offset)")
            guard rest.code == 350 || rest.code == 200 else {
                dataConnection.cancel()
                throw NetworkError.transferFailed(rest.message)
            }
        }
        let retr = try await send("RETR \(path)")
        guard (150...199).contains(retr.code) else {
            dataConnection.cancel()
            throw NetworkError.transferFailed(retr.message)
        }
        return dataConnection
    }

    private func send(_ command: String) async throws -> FTPReply {
        try ensureControl()
        let logged = command.hasPrefix("PASS ") ? "PASS <redacted>" : command
        VanmoLogger.network.info("[FTP] → \(logged)")
        let payload = Data("\(command)\r\n".utf8)
        try await sendControl(payload)
        let reply = try await readResponse()
        VanmoLogger.network.info("[FTP] ← \(reply.code) \(reply.message.prefix(80))")
        return reply
    }

    private func ensureControl() throws {
        guard control != nil else { throw NetworkError.notConnected }
    }

    private func openPassive() async throws -> FTPListingParser.PassiveEndpoint {
        if let epsv = try? await send("EPSV"), epsv.code == 229,
           let endpoint = FTPListingParser.parseEPSV(epsv.message, controlHost: host) {
            return endpoint
        }
        let pasv = try await send("PASV")
        guard pasv.code == 227, let endpoint = FTPListingParser.parsePASV(pasv.message, controlHost: host) else {
            throw NetworkError.transferFailed(pasv.message)
        }
        return endpoint
    }

    private func transferText(command: String) async throws -> String {
        let endpoint = try await openPassive()
        let dataConnection = try await connectData(endpoint)
        let reply = try await send(command)
        guard (150...199).contains(reply.code) else {
            dataConnection.cancel()
            throw NetworkError.transferFailed(reply.message)
        }
        let data = try await receiveData(from: dataConnection, limit: nil)
        dataConnection.cancel()
        _ = try? await readResponse()
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func ftpPath(_ path: String) -> String {
        FTPListingParser.normalizePath(path)
    }

    private static func parseSize(_ message: String) -> Int64? {
        let token = message.split(whereSeparator: { !$0.isNumber }).first
        guard let token, let size = Int64(token), size >= 0 else { return nil }
        return size
    }

    // MARK: - Network

    private func start(_ connection: NWConnection) async throws {
        try await withTimeout(seconds: 20) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var finished = false
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !finished else { return }
                        finished = true
                        cont.resume()
                    case .failed(let error):
                        guard !finished else { return }
                        finished = true
                        cont.resume(throwing: error)
                    case .cancelled:
                        guard !finished else { return }
                        finished = true
                        cont.resume(throwing: NetworkError.connectionFailed("连接已取消"))
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        }
    }

    private func connectData(_ endpoint: FTPListingParser.PassiveEndpoint) async throws -> NWConnection {
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: UInt16(endpoint.port)) ?? .any,
            using: .tcp
        )
        try await start(connection)
        return connection
    }

    private func sendControl(_ data: Data) async throws {
        guard let control else { throw NetworkError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            control.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func readResponse() async throws -> FTPReply {
        while true {
            if let reply = FTPReply.consume(from: &incoming) {
                return reply
            }
            let chunk = try await receiveControlChunk()
            if chunk.isEmpty {
                throw NetworkError.connectionFailed("控制连接已关闭")
            }
            incoming.append(chunk)
        }
    }

    private func receiveControlChunk() async throws -> Data {
        guard let control else { throw NetworkError.notConnected }
        return try await withTimeout(seconds: 20) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                control.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    if let data, !data.isEmpty {
                        cont.resume(returning: data)
                        return
                    }
                    if isComplete {
                        cont.resume(returning: Data())
                        return
                    }
                    cont.resume(returning: Data())
                }
            }
        }
    }

    private func receiveData(from connection: NWConnection, limit: Int?) async throws -> Data {
        var collected = Data()
        try await receiveData(from: connection, limit: limit, timeoutSeconds: 120) { chunk in
            collected.append(chunk)
        }
        if let limit {
            return Data(collected.prefix(limit))
        }
        return collected
    }

    private func receiveData(
        from connection: NWConnection,
        limit: Int? = nil,
        timeoutSeconds: TimeInterval? = 120,
        onChunk: @escaping (Data) throws -> Void
    ) async throws {
        let work: @Sendable () async throws -> Void = {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var finished = false
                var received = 0
                func finish(_ error: Error?) {
                    guard !finished else { return }
                    finished = true
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
                func loop() {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                        if let error {
                            finish(error)
                            return
                        }
                        do {
                            if let data, !data.isEmpty {
                                var chunk = data
                                if let limit {
                                    let remaining = limit - received
                                    if remaining <= 0 {
                                        connection.cancel()
                                        finish(nil)
                                        return
                                    }
                                    if chunk.count > remaining {
                                        chunk = chunk.prefix(remaining)
                                    }
                                }
                                received += chunk.count
                                try onChunk(chunk)
                                if let limit, received >= limit {
                                    connection.cancel()
                                    finish(nil)
                                    return
                                }
                            }
                            if isComplete {
                                finish(nil)
                            } else {
                                loop()
                            }
                        } catch {
                            finish(error)
                        }
                    }
                }
                loop()
            }
        }
        if let timeoutSeconds {
            try await withTimeout(seconds: timeoutSeconds, work)
        } else {
            try await work()
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkError.timeout
            }
            guard let result = try await group.next() else {
                throw NetworkError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

struct FTPReply {
    let code: Int
    let message: String

    static func consume(from buffer: inout Data) -> FTPReply? {
        var lines: [String] = []
        var offset = 0
        let count = buffer.count

        while offset < count {
            var lineEnd = offset
            var nextOffset = offset
            var foundTerminator = false
            while lineEnd < count {
                let byte = buffer[buffer.startIndex + lineEnd]
                if byte == 0x0A {
                    nextOffset = lineEnd + 1
                    foundTerminator = true
                    break
                }
                if byte == 0x0D {
                    nextOffset = lineEnd + 1
                    if nextOffset < count, buffer[buffer.startIndex + nextOffset] == 0x0A {
                        nextOffset += 1
                    }
                    foundTerminator = true
                    break
                }
                lineEnd += 1
            }
            guard foundTerminator else { return nil }

            let lineRange = (buffer.startIndex + offset)..<(buffer.startIndex + lineEnd)
            let line = String(data: buffer[lineRange], encoding: .utf8)
                ?? String(data: buffer[lineRange], encoding: .isoLatin1)
                ?? ""
            lines.append(line)
            offset = nextOffset

            guard line.count >= 3, let code = Int(line.prefix(3)) else { continue }
            if line.count == 3 || line[line.index(line.startIndex, offsetBy: 3)] == " " {
                let message = lines.map { entry in
                    entry.count >= 4 ? String(entry.dropFirst(4)) : ""
                }.joined(separator: "\n")
                buffer.removeFirst(offset)
                return FTPReply(code: code, message: message)
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
