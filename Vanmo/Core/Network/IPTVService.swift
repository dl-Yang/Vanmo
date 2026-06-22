import Foundation

final class IPTVService: RemoteFileService {
    let type: ConnectionType = .iptv
    private(set) var isConnected = false

    private var channels: [RemoteFile] = []
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
            channels = try Self.parsePlaylist(data: data, baseURL: playlistURL)
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

    private static func parsePlaylist(data: Data, baseURL: URL) throws -> [RemoteFile] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw NetworkError.transferFailed("无法读取 IPTV 播放列表")
        }

        var result: [RemoteFile] = []
        var pendingTitle: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF") {
                pendingTitle = title(fromExtinf: line)
                continue
            }

            guard !line.hasPrefix("#"),
                  let streamURL = URL(string: line, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            let name = pendingTitle ?? streamURL.lastPathComponent.nonEmpty ?? "IPTV 频道 \(result.count + 1)"
            result.append(
                RemoteFile(
                    name: name,
                    path: streamURL.absoluteString,
                    size: 0,
                    isDirectory: false,
                    modifiedDate: nil,
                    type: .video
                )
            )
            pendingTitle = nil
        }

        return result
    }

    private static func title(fromExtinf line: String) -> String? {
        guard let comma = line.lastIndex(of: ",") else { return nil }
        let title = line[line.index(after: comma)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.nonEmpty
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
