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
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")

        if let username = config.username, let password = config.password {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue(
                    "Basic \(data.base64EncodedString())",
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            throw NetworkError.authenticationFailed
        }

        isConnected = true
        VanmoLogger.network.info("WebDAV connected to \(config.host)")
    }

    func disconnect() async {
        isConnected = false
        config = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let config else { throw NetworkError.notConnected }

        let url = baseURL(for: config).appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        addAuth(to: &request)

        let (data, _) = try await session.data(for: request)
        return parseWebDAVResponse(data, basePath: path)
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
