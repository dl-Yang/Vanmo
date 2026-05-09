import Foundation
import Network

struct PrefetchRegistration {
    let url: URL
    let token: String
}

/// 本地 HTTP 代理：将远程 URL 映射为 `http://127.0.0.1:<port>/stream/<token>`。
actor PrefetchProxy {
    static let shared = PrefetchProxy()

    private nonisolated static let listenerQueue = DispatchQueue(label: "com.vanmo.prefetch.listener")
    private nonisolated static let connectionQueue = DispatchQueue(label: "com.vanmo.prefetch.connections")

    private var sessions: [String: PrefetchSession] = [:]
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var listenerStartTask: Task<UInt16, Error>?

    private init() {}

    func register(originalURL: URL) async -> PrefetchRegistration? {
        let port: UInt16
        do {
            port = try await startListenerIfNeeded()
        } catch {
            VanmoLogger.prefetch.error("[Prefetch] listener start failed: \(error.localizedDescription)")
            return nil
        }

        let token = UUID().uuidString
        guard let session = try? PrefetchSession(token: token, originalURL: originalURL) else {
            return nil
        }

        sessions[token] = session

        var comp = URLComponents()
        comp.scheme = "http"
        comp.host = "127.0.0.1"
        comp.port = Int(port)
        comp.path = PrefetchConfig.streamPathPrefix + token

        guard let url = comp.url else {
            unregister(token: token)
            return nil
        }

        VanmoLogger.prefetch.info("[Prefetch] registered session token=\(token.prefix(8))… port=\(port)")
        return PrefetchRegistration(url: url, token: token)
    }

    func unregister(token: String) {
        sessions[token]?.cleanup()
        sessions[token] = nil
        VanmoLogger.prefetch.info("[Prefetch] unregistered token=\(token.prefix(8))…")
    }

    // MARK: - Listener

    private func startListenerIfNeeded() async throws -> UInt16 {
        if let boundPort {
            return boundPort
        }
        if let listenerStartTask {
            return try await listenerStartTask.value
        }

        let task = Task<UInt16, Error> {
            try await self.performStartListener()
        }
        listenerStartTask = task

        do {
            let port = try await task.value
            listenerStartTask = nil
            return port
        } catch {
            listenerStartTask = nil
            throw error
        }
    }

    private func performStartListener() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let nwListener: NWListener
            do {
                nwListener = try NWListener(using: parameters, on: NWEndpoint.Port.any)
            } catch {
                cont.resume(throwing: error)
                return
            }

            final class ResumeGate: @unchecked Sendable {
                var resumed = false
                let lock = NSLock()
                func tryResume(_ body: () -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    body()
                }
            }
            let gate = ResumeGate()

            nwListener.stateUpdateHandler = { [weak nwListener] state in
                guard let nwListener else { return }
                switch state {
                case .ready:
                    gate.tryResume {
                        guard let portValue = nwListener.port?.rawValue else {
                            cont.resume(throwing: PrefetchError.listenerFailed)
                            return
                        }
                        Task {
                            await self.storeListener(nwListener, port: portValue)
                            VanmoLogger.prefetch.info("[Prefetch] listener ready on port \(portValue)")
                            cont.resume(returning: portValue)
                        }
                    }
                case .failed(let error):
                    gate.tryResume {
                        cont.resume(throwing: error)
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { connection in
                connection.start(queue: Self.connectionQueue)
                Task {
                    await PrefetchProxy.shared.handleIncoming(connection)
                }
            }

            nwListener.start(queue: Self.listenerQueue)
        }
    }

    private func storeListener(_ nwListener: NWListener, port: UInt16) {
        listener = nwListener
        boundPort = port
    }

    // MARK: - Connections

    private func handleIncoming(_ connection: NWConnection) async {
        do {
            let headerOnly = try await Self.readHTTPHeader(on: connection)
            guard let parsed = HTTPProtocolHandler.parseRequest(headerOnly) else {
                try await Self.send(connection, HTTPProtocolHandler.build400())
                connection.cancel()
                return
            }

            guard parsed.method.uppercased() == "GET" else {
                try await Self.send(connection, HTTPProtocolHandler.build400())
                connection.cancel()
                return
            }

            guard let token = HTTPProtocolHandler.streamToken(from: parsed.path) else {
                try await Self.send(connection, HTTPProtocolHandler.build400())
                connection.cancel()
                return
            }

            let session = sessions[token]

            guard let session else {
                VanmoLogger.prefetch.error("[Prefetch] handleIncoming 404 session not found token=\(token.prefix(8)) path=\(parsed.path)")
                try await Self.send(connection, HTTPProtocolHandler.build404())
                connection.cancel()
                return
            }

            let rangeHeader = parsed.headers["range"]
            let (header, body) = try await session.makeResponse(rangeHeader: rangeHeader)

            try await Self.send(connection, header)

            for try await chunk in body {
                try await Self.send(connection, chunk)
            }

            connection.cancel()
        } catch {
            VanmoLogger.prefetch.error("[Prefetch] handleIncoming connection ended: \(error.localizedDescription)")
            connection.cancel()
        }
    }

    // MARK: - NW helpers

    private nonisolated static func readHTTPHeader(on connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await receiveOnce(on: connection)
            if chunk.isEmpty {
                throw PrefetchError.connectionClosed
            }
            buffer.append(chunk)
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                if let r = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    return Data(buffer[..<r.lowerBound])
                }
                return buffer
            }
            if buffer.count > 256 * 1024 {
                throw PrefetchError.badRequest
            }
        }
    }

    private nonisolated static func receiveOnce(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private nonisolated static func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }
}
