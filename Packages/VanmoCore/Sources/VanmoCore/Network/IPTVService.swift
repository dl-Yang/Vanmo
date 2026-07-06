import Foundation

public final class IPTVService: RemoteFileService {
    public let type: ConnectionType = .iptv
    public private(set) var isConnected = false

    private var channels: [RemoteFile] = []
    /// 播放列表头部声明的 EPG（XMLTV）源地址，来自 `#EXTM3U` 的 `url-tvg` / `x-tvg-url`。
    public private(set) var epgURL: URL?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(config: ConnectionConfig) async throws {
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

    public func disconnect() async {
        isConnected = false
        channels = []
        epgURL = nil
    }

    public func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw NetworkError.notConnected }
        return channels
    }

    public func streamURL(for file: RemoteFile) async throws -> URL {
        guard let url = URL(string: file.path) else {
            throw NetworkError.invalidURL
        }
        return url
    }

    public func download(file: RemoteFile, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        throw NetworkError.unsupportedProtocol
    }

    public func fetchEPGGuide() async -> EPGGuide {
        guard let epgURL else {
            return EPGGuide(programsByChannel: [:])
        }

        do {
            let (data, response) = try await session.data(from: epgURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                VanmoLogger.network.warning("[IPTV] EPG request failed: HTTP \(httpResponse.statusCode)")
                return EPGGuide(programsByChannel: [:])
            }
            return XMLTVParser().parse(data: data)
        } catch {
            VanmoLogger.network.warning("[IPTV] EPG request failed: \(error.localizedDescription)")
            return EPGGuide(programsByChannel: [:])
        }
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

// MARK: - EPG (XMLTV)

/// 单条 EPG 节目。
public struct EPGProgram {
    public let start: Date
    public let stop: Date
    public let title: String
}

/// 频道节目单：按 tvg-id 关联 channelId，提供「正在播放 / 下一档」查询。
public struct EPGGuide {
    /// channelId -> 按开始时间升序排序的节目列表。
    public let programsByChannel: [String: [EPGProgram]]

    public init(programsByChannel: [String: [EPGProgram]]) {
        self.programsByChannel = programsByChannel
    }

    public var isEmpty: Bool { programsByChannel.isEmpty }

    public func current(for channelId: String, at date: Date = Date()) -> EPGProgram? {
        programsByChannel[channelId]?.first { $0.start <= date && date < $0.stop }
    }

    public func next(for channelId: String, at date: Date = Date()) -> EPGProgram? {
        programsByChannel[channelId]?.first { $0.start > date }
    }
}

/// 轻量 XMLTV 解析器（SAX 流式），只提取 programme 的 channel/start/stop/title。
public final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programs: [String: [EPGProgram]] = [:]
    private var channel: String?
    private var start: Date?
    private var stop: Date?
    private var title = ""
    private var capturingTitle = false
    private var titleCaptured = false

    private static let formatters: [DateFormatter] = {
        ["yyyyMMddHHmmss Z", "yyyyMMddHHmmssZ", "yyyyMMddHHmmss"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    /// 解析 XMLTV 数据，返回节目单；解析失败或无内容时返回空 guide。
    public func parse(data: Data) -> EPGGuide {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        let sorted = programs.mapValues { $0.sorted { $0.start < $1.start } }
        return EPGGuide(programsByChannel: sorted)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "programme":
            channel = attributeDict["channel"]
            start = Self.parseDate(attributeDict["start"])
            stop = Self.parseDate(attributeDict["stop"])
            title = ""
            capturingTitle = false
            titleCaptured = false
        case "title":
            if !titleCaptured { capturingTitle = true }
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTitle { title += string }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "title":
            if capturingTitle {
                capturingTitle = false
                titleCaptured = true
            }
        case "programme":
            if let channel, let start, let stop {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                programs[channel, default: []].append(EPGProgram(start: start, stop: stop, title: trimmed))
            }
            channel = nil
            start = nil
            stop = nil
            title = ""
        default:
            break
        }
    }
}
