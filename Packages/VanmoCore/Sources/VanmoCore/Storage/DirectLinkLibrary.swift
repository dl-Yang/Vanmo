import Foundation
import SwiftData

public enum DirectLinkError: LocalizedError, Equatable {
    case empty
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case insecurePublicHost

    public var errorDescription: String? {
        switch self {
        case .empty:
            return L10n.tr("请输入视频链接")
        case .unsupportedScheme, .missingHost:
            return L10n.tr("仅支持 http:// 或 https:// 链接")
        case .embeddedCredentials:
            return L10n.tr("不支持包含账号密码的链接，请改用 WebDAV 连接")
        case .insecurePublicHost:
            return L10n.tr("公网链接请使用 https://")
        }
    }
}

/// 用户粘贴的 http(s) 视频直链。条目直接存为本地库（LocalStore）中无连接的 `MediaItem`：
/// `sourceConnectionId == nil` 且 `fileURL` 为 http(s)。续播进度与「继续观看」复用播放器既有写回，
/// 进度与收藏不写入 `CloudMediaState`，也不参与 iCloud 同步。
public enum DirectLinkLibrary {
    public static func parse(_ input: String) -> Result<URL, DirectLinkError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = components.host, !host.isEmpty else {
            return .failure(.missingHost)
        }
        guard components.user == nil, components.password == nil else {
            return .failure(.embeddedCredentials)
        }
        guard scheme == "https" || allowsCleartext(host: host) else {
            return .failure(.insecurePublicHost)
        }
        components.scheme = scheme
        components.percentEncodedHost = components.percentEncodedHost?.lowercased()
        guard let url = components.url else { return .failure(.unsupportedScheme) }
        return .success(url)
    }

    /// ATS 只开了 `NSAllowsLocalNetworking`：明文 http 仅放行 IP 字面量、无点主机名与 `.local`。
    static func allowsCleartext(host: String) -> Bool {
        let host = host.lowercased()
        if host.contains(":") || !host.contains(".") || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
    }

    public static func isDirectLink(_ item: MediaItem) -> Bool {
        item.sourceConnectionId == nil && isHTTP(item.fileURL)
    }

    /// 列表行的格式徽标：HLS 播放列表显示 `HLS`，无扩展名显示 `URL`。
    public static func formatLabel(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if MediaFormatProbe.playlistExtensions.contains(ext) { return "HLS" }
        return ext.isEmpty ? "URL" : ext.uppercased()
    }

    public static func isStreamOnly(_ url: URL) -> Bool {
        MediaFormatProbe.playlistExtensions.contains(url.pathExtension.lowercased())
    }

    public static func downloadTask(
        for url: URL,
        in tasks: [DownloadTaskSnapshot]
    ) -> DownloadTaskSnapshot? {
        tasks.first { $0.request.sourceConnectionId == nil && $0.request.sourceFileURL == url }
    }

    @MainActor
    public static func entries(in context: ModelContext) -> [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.sourceConnectionId == nil }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items
            .filter { isHTTP($0.fileURL) }
            .sorted { ($0.lastPlayedAt ?? $0.addedAt) > ($1.lastPlayedAt ?? $1.addedAt) }
    }

    /// 同一 URL 复用已有条目（保留进度），否则插入新条目。
    @MainActor
    @discardableResult
    public static func upsert(url: URL, in context: ModelContext) throws -> MediaItem {
        if let existing = entries(in: context).first(where: { $0.fileURL.absoluteString == url.absoluteString }) {
            existing.addedAt = Date()
            try context.save()
            return existing
        }
        let fileName = displayFileName(for: url)
        let item = MediaItem(title: fileName, fileURL: url, mediaType: .movie)
        item.originalFileName = fileName
        let ext = url.pathExtension.lowercased()
        item.container = ext.isEmpty ? nil : ext
        item.isProgressCloudSynced = false
        item.isFavoriteCloudSynced = false
        context.insert(item)
        try context.save()
        return item
    }

    @MainActor
    public static func remove(_ item: MediaItem, in context: ModelContext) throws {
        guard isDirectLink(item) else { return }
        context.delete(item)
        try context.save()
    }

    static func displayFileName(for url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/" {
            return last.removingPercentEncoding ?? last
        }
        return url.host ?? url.absoluteString
    }

    private static func isHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
