import Foundation
import SWXMLHash

/// WebDAV (RFC 4918) 客户端实现。
///
/// 路径模型：所有暴露给上层的 `RemoteFile.path` 都是 server 绝对路径
/// （以 `/` 起始，含 mount 前缀），可以直接和 `baseURL`（仅 scheme + host[:port]）
/// 拼接成完整 URL 用于 PROPFIND / GET / 流播放。
///
/// scheme 推断顺序：
/// 1. 若用户在 host 字段里写了 `http://` / `https://` 前缀，按其指定 scheme + host + port。
/// 2. 否则按端口推断：443 → https，其余 → http。
final class WebDAVService: RemoteFileService {
    let type: ConnectionType = .webdav
    private(set) var isConnected = false

    private var config: ConnectionConfig?
    private var resolvedBaseURL: URL?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(config: ConnectionConfig) async throws {
        self.config = config

        guard let base = makeBaseURL(for: config) else {
            throw NetworkError.invalidURL
        }
        self.resolvedBaseURL = base

        let probePath = normalizedPath(config.path ?? "/")
        let probeURL = appending(path: probePath, to: base)
        VanmoLogger.network.info("[WebDAV] PROPFIND probe: \(probeURL.absoluteString)")

        let request = makePropfindRequest(url: probeURL, depth: "0")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            VanmoLogger.network.error("[WebDAV] Probe failed: \(error.localizedDescription)")
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }

        VanmoLogger.network.info("[WebDAV] Probe status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 207:
            isConnected = true
        case 200, 204:
            isConnected = true
        case 401, 403:
            throw NetworkError.authenticationFailed
        case 404:
            throw NetworkError.connectionFailed("路径不存在: \(probePath)")
        default:
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.connectionFailed("PROPFIND 失败 (\(httpResponse.statusCode)): \(bodyPreview)")
        }

        VanmoLogger.network.info("[WebDAV] Connected to \(base.absoluteString) at \(probePath)")
    }

    func disconnect() async {
        isConnected = false
        config = nil
        resolvedBaseURL = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let base = resolvedBaseURL, let config else {
            throw NetworkError.notConnected
        }

        let normalized = normalizedPath(path.isEmpty ? (config.path ?? "/") : path)
        let url = appending(path: normalized, to: base)
        VanmoLogger.network.info("[WebDAV] PROPFIND list: \(url.absoluteString)")

        let request = makePropfindRequest(url: url, depth: "1")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }

        guard httpResponse.statusCode == 207 else {
            VanmoLogger.network.error("[WebDAV] list status \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw NetworkError.authenticationFailed
            }
            throw NetworkError.transferFailed("PROPFIND \(httpResponse.statusCode)")
        }

        let files = parseMultistatus(data, requestedPath: normalized)
        VanmoLogger.network.info("[WebDAV] Found \(files.count) entries under \(normalized)")
        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let config, let base = resolvedBaseURL else { throw NetworkError.notConnected }

        let url = appending(path: normalizedPath(file.path), to: base)
        guard !url.absoluteString.isEmpty else { throw NetworkError.invalidURL }

        // 与 SMB 一致：把凭据嵌入 URL 让 KSPlayer/ffmpeg 直接消费 (Basic Auth)。
        // 已知 trade-off：密码会落到 MediaItem.fileURL，后续可由 PrefetchProxy 消除。
        if let user = config.username, !user.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.user = user
            components.password = config.password
            if let authedURL = components.url {
                return authedURL
            }
        }
        return url
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected, let base = resolvedBaseURL else { throw NetworkError.notConnected }

        let url = appending(path: normalizedPath(file.path), to: base)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        addAuth(to: &request)

        do {
            let (tempURL, response) = try await session.download(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw NetworkError.transferFailed("HTTP \(httpResponse.statusCode)")
            }

            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            progress(1.0)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }
    }

    // MARK: - URL composition

    /// 将 host 字段（可含/不含 scheme）+ port 解析成 `scheme://host[:port]` 的 baseURL，
    /// 不附带任何 path。
    private func makeBaseURL(for config: ConnectionConfig) -> URL? {
        let trimmedHost = config.host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return nil }

        let scheme: String
        let bareHost: String
        let explicitPort: Int?

        if let userComponents = URLComponents(string: trimmedHost),
           let s = userComponents.scheme,
           let h = userComponents.host,
           !h.isEmpty {
            scheme = s.lowercased()
            bareHost = h
            explicitPort = userComponents.port
        } else {
            scheme = config.port == 443 ? "https" : "http"
            bareHost = trimmedHost
            explicitPort = nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = bareHost

        let port: Int? = explicitPort ?? (config.port > 0 ? config.port : nil)
        if let port {
            let isDefault = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
            if !isDefault {
                components.port = port
            }
        }

        return components.url
    }

    /// 把 server 绝对 path 拼到 baseURL 上，path 中的特殊字符会被正确 percent-encode。
    private func appending(path: String, to base: URL) -> URL {
        let normalized = normalizedPath(path)
        if normalized == "/" {
            return base
        }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { encodePathSegment(String($0)) }
            .joined(separator: "/")
            .prefixedWithSlash
        return components?.url ?? base
    }

    private func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// 让 path 始终以 `/` 起始，并去掉重复斜杠。
    private func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        var result = path
        if !result.hasPrefix("/") { result = "/" + result }
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        return result
    }

    // MARK: - Requests

    private func makePropfindRequest(url: URL, depth: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Vanmo/WebDAV", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = Self.allpropBody
        addAuth(to: &request)
        return request
    }

    private func addAuth(to request: inout URLRequest) {
        guard let config,
              let username = config.username,
              !username.isEmpty else { return }
        let password = config.password ?? ""
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return }
        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
    }

    private static let allpropBody: Data = {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:resourcetype/>
                <D:getcontentlength/>
                <D:getlastmodified/>
                <D:getcontenttype/>
            </D:prop>
        </D:propfind>
        """
        return Data(xml.utf8)
    }()

    // MARK: - Multistatus parsing

    private func parseMultistatus(_ data: Data, requestedPath: String) -> [RemoteFile] {
        let xml = XMLHash.parse(data)

        let responses = collectResponses(in: xml)
        guard !responses.isEmpty else {
            VanmoLogger.network.warning("[WebDAV] No <response> elements found")
            return []
        }

        let rfc1123: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            df.timeZone = TimeZone(identifier: "GMT")
            return df
        }()
        let iso8601 = ISO8601DateFormatter()

        var files: [RemoteFile] = []
        files.reserveCapacity(responses.count)

        for response in responses {
            guard let rawHref = pickElementText(response, candidates: ["D:href", "d:href", "href"]) else {
                continue
            }

            let serverPath = serverAbsolutePath(from: rawHref)
            guard !serverPath.isEmpty else { continue }

            // 跳过自身（PROPFIND Depth=1 也会包含被请求目录自己一行）
            if pathsEqualIgnoringTrailingSlash(serverPath, requestedPath) {
                continue
            }

            let prop = pickProp(response)
            let isDirectory = prop?["D:resourcetype"]["D:collection"].element != nil
                || prop?["d:resourcetype"]["d:collection"].element != nil
                || prop?["resourcetype"]["collection"].element != nil

            let sizeText = pickElementText(prop, candidates: ["D:getcontentlength", "d:getcontentlength", "getcontentlength"])
            let size = Int64(sizeText ?? "") ?? 0

            let modifiedText = pickElementText(prop, candidates: ["D:getlastmodified", "d:getlastmodified", "getlastmodified"])
            let modified = modifiedText.flatMap { rfc1123.date(from: $0) }
                ?? modifiedText.flatMap { iso8601.date(from: $0) }

            let displayName = pickElementText(prop, candidates: ["D:displayname", "d:displayname", "displayname"])

            let fallbackName = serverPath
                .split(separator: "/", omittingEmptySubsequences: true)
                .last
                .map(String.init) ?? ""
            let name = (displayName?.isEmpty == false) ? displayName! : fallbackName
            guard !name.isEmpty else { continue }

            let fileType: RemoteFileType = isDirectory ? .directory : .from(filename: name)

            files.append(
                RemoteFile(
                    name: name,
                    path: serverPath,
                    size: size,
                    isDirectory: isDirectory,
                    modifiedDate: modified,
                    type: fileType
                )
            )
        }

        return files
    }

    private func collectResponses(in xml: XMLIndexer) -> [XMLIndexer] {
        let candidates: [[String]] = [
            ["D:multistatus", "D:response"],
            ["d:multistatus", "d:response"],
            ["multistatus", "response"],
        ]
        for path in candidates {
            var node = xml
            for key in path { node = node[key] }
            let all = node.all
            if !all.isEmpty { return all }
        }
        return []
    }

    private func pickProp(_ response: XMLIndexer) -> XMLIndexer? {
        for propstatKey in ["D:propstat", "d:propstat", "propstat"] {
            for propKey in ["D:prop", "d:prop", "prop"] {
                let propstats = response[propstatKey].all
                for propstat in propstats {
                    let prop = propstat[propKey]
                    if prop.element != nil {
                        return prop
                    }
                }
            }
        }
        return nil
    }

    private func pickElementText(_ indexer: XMLIndexer?, candidates: [String]) -> String? {
        guard let indexer else { return nil }
        for key in candidates {
            if let text = indexer[key].element?.text, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// `<D:href>` 可能是相对路径 (`/dav/Movies/`) 或完整 URL
    /// (`http://host/dav/Movies/`)；这里统一规整成 server 绝对路径。
    private func serverAbsolutePath(from href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href

        if let url = URL(string: decoded), url.scheme != nil {
            return normalizedPath(url.path)
        }
        return normalizedPath(decoded)
    }

    private func pathsEqualIgnoringTrailingSlash(_ a: String, _ b: String) -> Bool {
        let trim: (String) -> String = { s in
            s.hasSuffix("/") && s.count > 1 ? String(s.dropLast()) : s
        }
        return trim(a) == trim(b)
    }
}

// MARK: - Helpers

private extension String {
    var prefixedWithSlash: String {
        hasPrefix("/") ? self : "/" + self
    }
}
