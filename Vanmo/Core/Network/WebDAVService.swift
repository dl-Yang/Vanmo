import Foundation

final class WebDAVService: RemoteFileService {
    let type: ConnectionType = .webdav
    private(set) var isConnected = false
    private var config: ConnectionConfig?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(config: ConnectionConfig) async throws {
        self.config = config

        let url = baseURL(for: config)
        VanmoLogger.network.info("[WebDAV] Connecting to \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.timeoutInterval = 15

        if let username = config.username, let password = config.password {
            VanmoLogger.network.debug("[WebDAV] Using Basic Auth, user: \(username)")
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue(
                    "Basic \(data.base64EncodedString())",
                    forHTTPHeaderField: "Authorization"
                )
            }
        } else {
            VanmoLogger.network.debug("[WebDAV] No credentials provided, connecting anonymously")
        }

        VanmoLogger.network.debug("[WebDAV] Sending PROPFIND request (Depth: 0)...")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            VanmoLogger.network.error("[WebDAV] Request failed: \(error.localizedDescription)")
            VanmoLogger.network.error("[WebDAV] Error details: \(String(describing: error))")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            VanmoLogger.network.error("[WebDAV] Response is not HTTPURLResponse")
            throw NetworkError.connectionFailed("Invalid response type")
        }

        VanmoLogger.network.info("[WebDAV] Response status: \(httpResponse.statusCode)")
        VanmoLogger.network.debug("[WebDAV] Response headers: \(httpResponse.allHeaderFields)")

        if let body = String(data: data, encoding: .utf8) {
            VanmoLogger.network.debug("[WebDAV] Response body (\(data.count) bytes): \(body.prefix(500))")
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            VanmoLogger.network.error("[WebDAV] Auth failed, status: \(httpResponse.statusCode)")
            throw NetworkError.authenticationFailed
        }

        isConnected = true
        VanmoLogger.network.info("[WebDAV] Successfully connected to \(config.host)")
    }

    func disconnect() async {
        isConnected = false
        config = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let config else {
            VanmoLogger.network.error("[WebDAV] listDirectory failed: not connected")
            throw NetworkError.notConnected
        }

        let url = baseURL(for: config).appendingPathComponent(path)
        VanmoLogger.network.info("[WebDAV] Listing directory: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.timeoutInterval = 15
        addAuth(to: &request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            VanmoLogger.network.error("[WebDAV] listDirectory request failed: \(error.localizedDescription)")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            VanmoLogger.network.debug("[WebDAV] listDirectory status: \(httpResponse.statusCode)")
        }

        if let body = String(data: data, encoding: .utf8) {
            VanmoLogger.network.debug("[WebDAV] listDirectory response (\(data.count) bytes): \(body.prefix(1000))")
        }

        let files = parseWebDAVResponse(data, basePath: path)
        VanmoLogger.network.info("[WebDAV] Found \(files.count) items in \(path)")
        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let config else { throw NetworkError.notConnected }
        var url = baseURL(for: config).appendingPathComponent(file.path)

        if let username = config.username, let password = config.password {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.user = username
            components?.password = password
            if let authedURL = components?.url {
                url = authedURL
            }
        }

        return url
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected, let config else { throw NetworkError.notConnected }

        let url = baseURL(for: config).appendingPathComponent(file.path)
        var request = URLRequest(url: url)
        addAuth(to: &request)

        let (tempURL, _) = try await session.download(for: request)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        progress(1.0)
    }

    // MARK: - Private

    private func baseURL(for config: ConnectionConfig) -> URL {
        let scheme = config.port == 443 ? "https" : "http"
        return URL(string: "\(scheme)://\(config.host):\(config.port)")!
    }

    private func addAuth(to request: inout URLRequest) {
        guard let config,
              let username = config.username,
              let password = config.password else { return }
        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            request.setValue(
                "Basic \(data.base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }
    }

    private func parseWebDAVResponse(_ data: Data, basePath: String) -> [RemoteFile] {
        // Simplified WebDAV XML response parsing
        // Full implementation would use XMLParser
        return []
    }
}
