import Foundation

final class IPTVService: RemoteFileService {
    let type: ConnectionType = .iptv
    private(set) var isConnected = false

    private var channels: [RemoteFile] = []
    /// 播放列表头部声明的 EPG（XMLTV）源地址，来自 `#EXTM3U` 的 `url-tvg` / `x-tvg-url`。
    private(set) var epgURL: URL?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(config: ConnectionConfig) async throws {
        guard let playlistURL = playlistURL(from: config) else {
            throw NetworkError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: playlistURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw NetworkError.connectionFailed("HTTP \(httpResponse.statusCode)")
            }
            let parsed = try Self.parsePlaylist(data: data, baseURL: playlistURL)
            channels = parsed.channels
            epgURL = parsed.epgURL
            isConnected = true
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async {
        isConnected = false
        channels = []
        epgURL = nil
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        return channels
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let url = URL(string: file.path) else {
            throw NetworkError.invalidURL
        }
        return url
    }

    func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        throw NetworkError.unsupportedProtocol
    }

    private func playlistURL(from config: ConnectionConfig) -> URL? {
        let raw = (config.path?.isEmpty == false ? config.path : config.host) ?? config.host
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        var components = URLComponents()
        components.scheme = config.port == 443 ? "https" : "http"
        components.host = config.host
        if config.port > 0 {
            components.port = config.port
        }
        components.path = config.path ?? "/"
        return components.url
    }

    private static func parsePlaylist(data: Data, baseURL: URL) throws -> (channels: [RemoteFile], epgURL: URL?) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw NetworkError.transferFailed("无法读取 IPTV 播放列表")
        }

        var result: [RemoteFile] = []
        var epgURL: URL?
        var pendingTitle: String?
        var pendingAttributes: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTM3U") {
                let attrs = attributes(from: line)
                if let tvg = attrs["url-tvg"] ?? attrs["x-tvg-url"],
                   let url = URL(string: tvg.trimmingCharacters(in: .whitespaces)) {
                    epgURL = url
                }
                continue
            }

            if line.hasPrefix("#EXTINF") {
                pendingTitle = title(fromExtinf: line)
                pendingAttributes = attributes(from: line)
                continue
            }

            guard !line.hasPrefix("#"),
                  let streamURL = URL(string: line, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            let name = pendingTitle
                ?? pendingAttributes["tvg-name"]
                ?? streamURL.lastPathComponent.nonEmpty
                ?? "IPTV 频道 \(result.count + 1)"
            let logoURL = pendingAttributes["tvg-logo"].flatMap { URL(string: $0) }
            result.append(
                RemoteFile(
                    name: name,
                    path: streamURL.absoluteString,
                    size: 0,
                    isDirectory: false,
                    modifiedDate: nil,
                    type: .video,
                    groupTitle: pendingAttributes["group-title"]?.nonEmpty,
                    logoURL: logoURL,
                    tvgId: pendingAttributes["tvg-id"]?.nonEmpty
                )
            )
            pendingTitle = nil
            pendingAttributes = [:]
        }

        return (result, epgURL)
    }

    private static func title(fromExtinf line: String) -> String? {
        guard let comma = line.lastIndex(of: ",") else { return nil }
        let title = line[line.index(after: comma)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.nonEmpty
    }

    /// 解析 EXTINF / EXTM3U 行中的 `key="value"` 属性对（键名小写）。
    private static func attributes(from line: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([\w-]+)=\"([^\"]*)\""#) else {
            return [:]
        }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var result: [String: String] = [:]
        for match in matches where match.numberOfRanges == 3 {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let value = ns.substring(with: match.range(at: 2))
            result[key] = value
        }
        return result
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
