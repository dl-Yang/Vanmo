import Foundation

public struct OnlineSubtitleResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let language: String?
    public let format: SubtitleFormat
    public let downloadURL: URL
    public let provider: String
    public let fileName: String?
    public let downloadCount: Int?
    public let isTrusted: Bool?
    public let isMachineTranslated: Bool?

    public init(
        id: String,
        title: String,
        language: String?,
        format: SubtitleFormat,
        downloadURL: URL,
        provider: String,
        fileName: String? = nil,
        downloadCount: Int? = nil,
        isTrusted: Bool? = nil,
        isMachineTranslated: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.format = format
        self.downloadURL = downloadURL
        self.provider = provider
        self.fileName = fileName
        self.downloadCount = downloadCount
        self.isTrusted = isTrusted
        self.isMachineTranslated = isMachineTranslated
    }
}

public protocol OnlineSubtitleProvider: Sendable {
    var name: String { get }
    var isConfigured: Bool { get }
    func search(for item: MediaItem) async throws -> [OnlineSubtitleResult]
    func downloadURL(for result: OnlineSubtitleResult) async throws -> URL
}

public actor OnlineSubtitleService {
    public static let shared = OnlineSubtitleService()

    private var providers: [OnlineSubtitleProvider] = []

    public func register(_ provider: OnlineSubtitleProvider) {
        guard providers.contains(where: { $0.name == provider.name }) == false else { return }
        providers.append(provider)
    }

    public func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        guard providers.isEmpty == false else {
            throw OnlineSubtitleError.noProvidersRegistered
        }

        let configuredProviders = providers.filter(\.isConfigured)
        guard configuredProviders.isEmpty == false else {
            throw OnlineSubtitleError.noProvidersConfigured
        }

        var results: [OnlineSubtitleResult] = []
        var providerErrors: [String] = []
        for provider in configuredProviders {
            do {
                results.append(contentsOf: try await provider.search(for: item))
            } catch {
                providerErrors.append("\(provider.name): \(error.localizedDescription)")
            }
        }

        if results.isEmpty, providerErrors.isEmpty == false {
            throw OnlineSubtitleError.searchFailed(providerErrors.joined(separator: "\n"))
        }

        return results
            .filter { $0.format != .unknown }
            .sorted { lhs, rhs in
                lhs.provider == rhs.provider ? lhs.title < rhs.title : lhs.provider < rhs.provider
            }
    }

    public func download(_ result: OnlineSubtitleResult, for item: MediaItem) async throws -> URL {
        let downloadURL = try await resolvedDownloadURL(for: result)
        let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw OnlineSubtitleError.downloadFailed(httpResponse.statusCode)
        }

        let directory = try cacheDirectory()
        let localURL = directory.appendingPathComponent(cacheFileName(for: result, item: item))
        if FileManager.default.fileExists(atPath: localURL.path) {
            _ = try FileManager.default.replaceItemAt(localURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
        }
        return localURL
    }

    public func cachedSubtitleURLs(for item: MediaItem) throws -> [URL] {
        let directory = try cacheDirectory()
        let prefix = "\(item.id.uuidString)-"
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                guard url.lastPathComponent.hasPrefix(prefix),
                      Self.isLoadableCachedSubtitle(url) else {
                    return false
                }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public func cacheDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("OnlineSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cacheFileName(for result: OnlineSubtitleResult, item: MediaItem) -> String {
        let provider = Self.safeFileName(result.provider)
        let identifier = Self.safeFileName(result.id)
        let title = Self.safeFileName(result.fileName ?? result.title)
        return "\(item.id.uuidString)-\(provider)-\(identifier)-\(title).\(result.format.fileExtension)"
    }

    private func resolvedDownloadURL(for result: OnlineSubtitleResult) async throws -> URL {
        if let provider = providers.first(where: { $0.name == result.provider }) {
            return try await provider.downloadURL(for: result)
        }
        return result.downloadURL
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "subtitle" : String(collapsed.prefix(80))
    }

    private static func isLoadableCachedSubtitle(_ url: URL) -> Bool {
        switch SubtitleFormat.detect(from: url) {
        case .srt, .vtt, .ass:
            return true
        case .unknown:
            return false
        }
    }
}

extension OnlineSubtitleProvider {
    var isConfigured: Bool { true }

    public func downloadURL(for result: OnlineSubtitleResult) async throws -> URL {
        result.downloadURL
    }
}

public enum OnlineSubtitleError: LocalizedError {
    case noProvidersRegistered
    case noProvidersConfigured
    case searchFailed(String)
    case downloadFailed(Int)
    case invalidEndpoint
    case missingCredentials(String)
    case authenticationFailed(String)
    case quotaExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .noProvidersRegistered:
            return "尚未注册在线字幕 Provider"
        case .noProvidersConfigured:
            return "尚未配置可用的在线字幕公开接口。请在设置中配置 Provider 的公开搜索端点后再试。"
        case .searchFailed(let message):
            return "在线字幕搜索失败：\(message)"
        case .downloadFailed(let statusCode):
            return "字幕下载失败，HTTP 状态码 \(statusCode)"
        case .invalidEndpoint:
            return "在线字幕 Provider 端点无效"
        case .missingCredentials(let message):
            return message
        case .authenticationFailed(let message):
            return "在线字幕登录失败：\(message)"
        case .quotaExceeded(let message):
            return message
        }
    }
}

public struct ConfigurableOnlineSubtitleProvider: OnlineSubtitleProvider {
    public let name: String
    public let endpoint: URL?

    public var isConfigured: Bool {
        endpoint != nil
    }

    public func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        guard let endpoint else {
            throw OnlineSubtitleError.noProvidersConfigured
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw OnlineSubtitleError.invalidEndpoint
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "title", value: item.title))
        queryItems.append(URLQueryItem(name: "filename", value: item.originalFileName ?? item.fileURL.lastPathComponent))
        if let year = item.year {
            queryItems.append(URLQueryItem(name: "year", value: String(year)))
        }
        if let tmdbID = item.tmdbID {
            queryItems.append(URLQueryItem(name: "tmdb_id", value: String(tmdbID)))
        }
        if let seasonNumber = item.seasonNumber {
            queryItems.append(URLQueryItem(name: "season", value: String(seasonNumber)))
        }
        if let episodeNumber = item.episodeNumber {
            queryItems.append(URLQueryItem(name: "episode", value: String(episodeNumber)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OnlineSubtitleError.invalidEndpoint
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw OnlineSubtitleError.downloadFailed(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OnlineSubtitleAPIResponse.self, from: data)
        return decoded.results.compactMap { item in
            guard let downloadURL = URL(string: item.downloadURL) else { return nil }
            let format = item.format.map(Self.subtitleFormat) ?? SubtitleFormat.detect(from: downloadURL)
            guard format != .unknown else { return nil }
            return OnlineSubtitleResult(
                id: item.id,
                title: item.title,
                language: item.language,
                format: format,
                downloadURL: downloadURL,
                provider: name
            )
        }
    }

    private static func subtitleFormat(from value: String) -> SubtitleFormat {
        switch value.lowercased() {
        case "srt": return .srt
        case "vtt", "webvtt": return .vtt
        case "ass", "ssa": return .ass
        default: return .unknown
        }
    }
}

public struct OpenSubtitlesProvider: OnlineSubtitleProvider {
    public init() {}
    public let name = "OpenSubtitles"

    public var isConfigured: Bool {
        OpenSubtitlesCredentialStore.isEnabled && OpenSubtitlesCredentialStore.apiKey?.isEmpty == false
    }

    public func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        guard isConfigured, let apiKey = OpenSubtitlesCredentialStore.apiKey else {
            throw OnlineSubtitleError.missingCredentials("请先在设置中启用并配置 OpenSubtitles API Key")
        }

        let baseURL = OpenSubtitlesCredentialStore.baseURL
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/subtitles"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems(for: item)

        guard let url = components.url else {
            throw OnlineSubtitleError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data, context: "搜索 OpenSubtitles")

        let decoded = try JSONDecoder().decode(OpenSubtitlesSearchResponse.self, from: data)
        return decoded.data.flatMap { subtitle -> [OnlineSubtitleResult] in
            subtitle.attributes.files.compactMap { file in
                guard let placeholderURL = URL(string: "opensubtitles://download/\(file.fileID)") else { return nil }
                let format = SubtitleFormat.detect(from: URL(fileURLWithPath: file.fileName))
                let resolvedFormat = format == .unknown ? .srt : format
                return OnlineSubtitleResult(
                    id: String(file.fileID),
                    title: file.fileName.isEmpty ? subtitle.attributes.release : file.fileName,
                    language: subtitle.attributes.language,
                    format: resolvedFormat,
                    downloadURL: placeholderURL,
                    provider: name,
                    fileName: file.fileName,
                    downloadCount: subtitle.attributes.downloadCount,
                    isTrusted: subtitle.attributes.fromTrusted,
                    isMachineTranslated: subtitle.attributes.machineTranslated ?? subtitle.attributes.aiTranslated
                )
            }
        }
        .sorted(by: resultSort)
    }

    public func downloadURL(for result: OnlineSubtitleResult) async throws -> URL {
        guard result.downloadURL.scheme == "opensubtitles" else { return result.downloadURL }
        guard let fileID = Int(result.id) else {
            throw OnlineSubtitleError.invalidEndpoint
        }
        guard let apiKey = OpenSubtitlesCredentialStore.apiKey else {
            throw OnlineSubtitleError.missingCredentials("请先在设置中配置 OpenSubtitles API Key")
        }
        let token = try await ensureToken(apiKey: apiKey)

        var request = URLRequest(url: OpenSubtitlesCredentialStore.baseURL.appendingPathComponent("api/v1/download"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenSubtitlesDownloadRequest(fileID: fileID))

        let (data, response) = try await URLSession.shared.data(for: request)
        do {
            try Self.validate(response: response, data: data, context: "下载 OpenSubtitles")
        } catch let error as OnlineSubtitleError {
            if case .authenticationFailed = error {
                OpenSubtitlesCredentialStore.clearToken()
            }
            throw error
        }

        let decoded = try JSONDecoder().decode(OpenSubtitlesDownloadResponse.self, from: data)
        guard let url = URL(string: decoded.link) else {
            throw OnlineSubtitleError.invalidEndpoint
        }
        return url
    }

    public static func testLogin() async throws -> OpenSubtitlesLoginResponse {
        guard let apiKey = OpenSubtitlesCredentialStore.apiKey,
              let username = OpenSubtitlesCredentialStore.username,
              let password = OpenSubtitlesCredentialStore.password,
              !apiKey.isEmpty,
              !username.isEmpty,
              !password.isEmpty else {
            throw OnlineSubtitleError.missingCredentials("请先填写 OpenSubtitles API Key、用户名和密码")
        }
        return try await login(apiKey: apiKey, username: username, password: password)
    }

    private func ensureToken(apiKey: String) async throws -> String {
        if let token = OpenSubtitlesCredentialStore.jwtToken, !token.isEmpty {
            return token
        }
        guard let username = OpenSubtitlesCredentialStore.username,
              let password = OpenSubtitlesCredentialStore.password,
              !username.isEmpty,
              !password.isEmpty else {
            throw OnlineSubtitleError.missingCredentials("OpenSubtitles 下载需要登录，请先在设置中填写用户名和密码")
        }
        return try await Self.login(apiKey: apiKey, username: username, password: password).token
    }

    private static func login(apiKey: String, username: String, password: String) async throws -> OpenSubtitlesLoginResponse {
        var request = URLRequest(url: OpenSubtitlesCredentialStore.baseURL.appendingPathComponent("api/v1/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenSubtitlesLoginRequest(username: username, password: password))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, context: "登录 OpenSubtitles")

        let decoded = try JSONDecoder().decode(OpenSubtitlesLoginResponse.self, from: data)
        OpenSubtitlesCredentialStore.saveSession(token: decoded.token, baseURLHost: decoded.baseURL)
        return decoded
    }

    private func queryItems(for item: MediaItem) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "languages", value: languages(for: OpenSubtitlesCredentialStore.preferredLanguage)),
            URLQueryItem(name: "order_by", value: "download_count"),
            URLQueryItem(name: "order_direction", value: "desc"),
        ]

        if let episodeNumber = item.episodeNumber {
            items.append(URLQueryItem(name: "episode_number", value: String(episodeNumber)))
            if let seasonNumber = item.seasonNumber {
                items.append(URLQueryItem(name: "season_number", value: String(seasonNumber)))
            }
        }

        if let tmdbID = item.tmdbID {
            items.append(URLQueryItem(name: "tmdb_id", value: String(tmdbID)))
        } else {
            items.append(URLQueryItem(name: "query", value: item.originalFileName ?? item.displayTitle))
        }

        if item.mediaType == .movie {
            items.append(URLQueryItem(name: "type", value: "movie"))
        } else if item.mediaType == .tvEpisode || item.mediaType == .tvShow {
            items.append(URLQueryItem(name: "type", value: "episode"))
        }

        return items.sorted { $0.name < $1.name }
    }

    private func languages(for preferredLanguage: String) -> String {
        switch preferredLanguage {
        case "zh": return "zh-cn,zh-tw,ze"
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        default: return preferredLanguage
        }
    }

    private func resultSort(_ lhs: OnlineSubtitleResult, _ rhs: OnlineSubtitleResult) -> Bool {
        let lhsTrusted = lhs.isTrusted == true ? 1 : 0
        let rhsTrusted = rhs.isTrusted == true ? 1 : 0
        if lhsTrusted != rhsTrusted { return lhsTrusted > rhsTrusted }
        let lhsMachine = lhs.isMachineTranslated == true ? 1 : 0
        let rhsMachine = rhs.isMachineTranslated == true ? 1 : 0
        if lhsMachine != rhsMachine { return lhsMachine < rhsMachine }
        return (lhs.downloadCount ?? 0) > (rhs.downloadCount ?? 0)
    }

    private static func validate(response: URLResponse, data: Data, context: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnlineSubtitleError.searchFailed("\(context): 无效响应")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OnlineSubtitleError.authenticationFailed(message)
            }
            if httpResponse.statusCode == 406 || message.contains("quota") || message.contains("allowed") {
                throw OnlineSubtitleError.quotaExceeded(message)
            }
            throw OnlineSubtitleError.searchFailed("\(context): \(message)")
        }
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OpenSubtitlesErrorResponse.self, from: data) {
            return decoded.message
        }
        return String(data: data, encoding: .utf8)
    }

    private static var userAgent: String {
        "Vanmo v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
    }
}

public enum OpenSubtitlesCredentialStore {
    public static let enabledKey = "subtitle.opensubtitles.enabled"
    public static let preferredLanguageKey = "subtitle.preferredLanguage"

    private static let apiKeyAccount = "subtitle.opensubtitles.apiKey"
    private static let usernameAccount = "subtitle.opensubtitles.username"
    private static let passwordAccount = "subtitle.opensubtitles.password"
    private static let tokenAccount = "subtitle.opensubtitles.jwtToken"
    private static let baseURLHostKey = "subtitle.opensubtitles.baseURLHost"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    public static var preferredLanguage: String {
        UserDefaults.standard.string(forKey: preferredLanguageKey) ?? "zh"
    }

    public static var apiKey: String? {
        try? KeychainManager.shared.loadString(for: apiKeyAccount)
    }

    public static var username: String? {
        try? KeychainManager.shared.loadString(for: usernameAccount)
    }

    public static var password: String? {
        try? KeychainManager.shared.loadString(for: passwordAccount)
    }

    public static var jwtToken: String? {
        try? KeychainManager.shared.loadString(for: tokenAccount)
    }

    public static var baseURL: URL {
        let host = UserDefaults.standard.string(forKey: baseURLHostKey) ?? "api.opensubtitles.com"
        guard let safeHost = sanitizedOpenSubtitlesHost(host) else {
            return URL(string: "https://api.opensubtitles.com")!
        }
        return URL(string: "https://\(safeHost)")!
    }

    public static func saveCredentials(apiKey: String, username: String, password: String) throws {
        try KeychainManager.shared.save(apiKey, for: apiKeyAccount)
        try KeychainManager.shared.save(username, for: usernameAccount)
        try KeychainManager.shared.save(password, for: passwordAccount)
        clearToken()
    }

    public static func saveSession(token: String, baseURLHost: String) {
        try? KeychainManager.shared.save(token, for: tokenAccount)
        if let safeHost = sanitizedOpenSubtitlesHost(baseURLHost) {
            UserDefaults.standard.set(safeHost, forKey: baseURLHostKey)
        }
    }

    public static func clearToken() {
        try? KeychainManager.shared.delete(for: tokenAccount)
    }

    public static func clearAll() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: baseURLHostKey)
        try? KeychainManager.shared.delete(for: apiKeyAccount)
        try? KeychainManager.shared.delete(for: usernameAccount)
        try? KeychainManager.shared.delete(for: passwordAccount)
        clearToken()
    }

    private static func sanitizedOpenSubtitlesHost(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        guard let host = url?.host?.lowercased(),
              host == "opensubtitles.com" || host.hasSuffix(".opensubtitles.com") else {
            return nil
        }
        return host
    }
}

private struct OpenSubtitlesLoginRequest: Encodable {
    let username: String
    let password: String
}

public struct OpenSubtitlesLoginResponse: Decodable, Sendable {
    public let token: String
    public let baseURL: String
    public let user: OpenSubtitlesUser

    enum CodingKeys: String, CodingKey {
        case token
        case baseURL = "base_url"
        case user
    }
}

public struct OpenSubtitlesUser: Decodable, Sendable {
    public let allowedDownloads: Int?
    public let level: String?

    enum CodingKeys: String, CodingKey {
        case allowedDownloads = "allowed_downloads"
        case level
    }
}

private struct OpenSubtitlesSearchResponse: Decodable {
    let data: [OpenSubtitlesSubtitle]
}

private struct OpenSubtitlesSubtitle: Decodable {
    let attributes: OpenSubtitlesSubtitleAttributes
}

private struct OpenSubtitlesSubtitleAttributes: Decodable {
    let language: String?
    let downloadCount: Int?
    let fromTrusted: Bool?
    let aiTranslated: Bool?
    let machineTranslated: Bool?
    let release: String
    let files: [OpenSubtitlesSubtitleFile]

    enum CodingKeys: String, CodingKey {
        case language
        case downloadCount = "download_count"
        case fromTrusted = "from_trusted"
        case aiTranslated = "ai_translated"
        case machineTranslated = "machine_translated"
        case release
        case files
    }
}

private struct OpenSubtitlesSubtitleFile: Decodable {
    let fileID: Int
    let fileName: String

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
    }
}

private struct OpenSubtitlesDownloadRequest: Encodable {
    let fileID: Int

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
    }
}

private struct OpenSubtitlesDownloadResponse: Decodable {
    let link: String
    let fileName: String?
    let remaining: Int?
    let resetTimeUTC: String?

    enum CodingKeys: String, CodingKey {
        case link
        case fileName = "file_name"
        case remaining
        case resetTimeUTC = "reset_time_utc"
    }
}

private struct OpenSubtitlesErrorResponse: Decodable {
    let message: String?
}

public struct ShooterSubtitleProvider: OnlineSubtitleProvider {
    private let provider: ConfigurableOnlineSubtitleProvider

    public init(endpoint: URL? = UserDefaults.standard.url(forKey: "subtitle.provider.shooter.searchEndpoint")) {
        self.provider = ConfigurableOnlineSubtitleProvider(name: "Shooter", endpoint: endpoint)
    }

    public var name: String { provider.name }
    public var isConfigured: Bool { provider.isConfigured }

    public func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        try await provider.search(for: item)
    }
}

public struct SubhdSubtitleProvider: OnlineSubtitleProvider {
    private let provider: ConfigurableOnlineSubtitleProvider

    public init(endpoint: URL? = UserDefaults.standard.url(forKey: "subtitle.provider.subhd.searchEndpoint")) {
        self.provider = ConfigurableOnlineSubtitleProvider(name: "Subhd", endpoint: endpoint)
    }

    public var name: String { provider.name }
    public var isConfigured: Bool { provider.isConfigured }

    public func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        try await provider.search(for: item)
    }
}

private struct OnlineSubtitleAPIResponse: Decodable {
    let results: [OnlineSubtitleAPIResult]
}

private struct OnlineSubtitleAPIResult: Decodable {
    let id: String
    let title: String
    let language: String?
    let format: String?
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case language
        case format
        case downloadURL = "download_url"
    }
}

extension SubtitleFormat {
    public var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .ass: return "ass"
        case .unknown: return "txt"
        }
    }
}
