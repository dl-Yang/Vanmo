import Foundation
import FileProvider
import SWXMLHash

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

        let url = baseURL(for: config).appendingPathComponent("dav")
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
            VanmoLogger.network.error("[WebDAV] Auth failed, status: \(httpResponse.statusCode) \(httpResponse.description)")
        
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
            VanmoLogger.network.debug("[WebDAV] listDirectory response (\(data.count) bytes): \(body)")
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
        VanmoLogger.network.debug("video streamUrl: \(url)")
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
        var urlString = "\(scheme)://\(config.host):\(config.port)"
        return URL(string: urlString)!
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
        let xml = XMLHash.parse(data)
        var files: [RemoteFile] = []
        let dateFormatter = ISO8601DateFormatter()
        let rfc1123Formatter = DateFormatter()
        rfc1123Formatter.locale = Locale(identifier: "en_US_POSIX")
        rfc1123Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        guard let responses = xml["D:multistatus"]["D:response"].all as? [XMLIndexer] else {
            VanmoLogger.network.warning("[WebDAV] No D:response elements found, trying without namespace")
            return parseWebDAVResponseWithoutNamespace(xml, basePath: basePath)
        }

        for response in responses {
            guard let href = response["D:href"].element?.text else { continue }

            let decodedHref = href.removingPercentEncoding ?? href
            let name = extractFileName(from: decodedHref)

            guard !name.isEmpty else { continue }

            let normalizedBasePath = basePath.hasSuffix("/") ? basePath : basePath + "/"
            let normalizedHref = decodedHref.hasSuffix("/") ? decodedHref : decodedHref
            if normalizedHref == normalizedBasePath || decodedHref == "/" {
                continue
            }

            let propstat = response["D:propstat"]
            let prop = propstat["D:prop"]

            let isDirectory = prop["D:resourcetype"]["D:collection"].element != nil
            let sizeText = prop["D:getcontentlength"].element?.text
            let size = Int64(sizeText ?? "0") ?? 0
            let lastModifiedText = prop["D:getlastmodified"].element?.text
            let modifiedDate = lastModifiedText.flatMap { rfc1123Formatter.date(from: $0) }
                ?? lastModifiedText.flatMap { dateFormatter.date(from: $0) }

            let path = decodedHref
            let fileType: RemoteFileType = isDirectory ? .directory : RemoteFileType.from(filename: name)

            let remoteFile = RemoteFile(
                name: name,
                path: path,
                size: size,
                isDirectory: isDirectory,
                modifiedDate: modifiedDate,
                type: fileType
            )
            files.append(remoteFile)
        }

        return files
    }

    private func parseWebDAVResponseWithoutNamespace(
        _ xml: XMLIndexer,
        basePath: String
    ) -> [RemoteFile] {
        var files: [RemoteFile] = []
        let rfc1123Formatter = DateFormatter()
        rfc1123Formatter.locale = Locale(identifier: "en_US_POSIX")
        rfc1123Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let responses = xml["multistatus"]["response"].all

        for response in responses {
            guard let href = response["href"].element?.text else { continue }

            let decodedHref = href.removingPercentEncoding ?? href
            let name = extractFileName(from: decodedHref)
            guard !name.isEmpty else { continue }

            let normalizedBasePath = basePath.hasSuffix("/") ? basePath : basePath + "/"
            if decodedHref == normalizedBasePath || decodedHref == "/" {
                continue
            }

            let prop = response["propstat"]["prop"]
            let isDirectory = prop["resourcetype"]["collection"].element != nil
            let size = Int64(prop["getcontentlength"].element?.text ?? "0") ?? 0
            let lastModified = prop["getlastmodified"].element?.text
            let modifiedDate = lastModified.flatMap { rfc1123Formatter.date(from: $0) }

            let fileType: RemoteFileType = isDirectory ? .directory : RemoteFileType.from(filename: name)
            files.append(RemoteFile(
                name: name,
                path: decodedHref,
                size: size,
                isDirectory: isDirectory,
                modifiedDate: modifiedDate,
                type: fileType
            ))
        }

        return files
    }

    private func extractFileName(from href: String) -> String {
        let trimmed = href.hasSuffix("/") ? String(href.dropLast()) : href
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }
}
