import Foundation
import VanmoCore

enum MacLocalFilePlayback {
    private static var retainedSecurityScopedURLs: [URL] = []

    /// 规范化本地 file URL，并在可用时开启 security-scoped 访问（拖拽文件等场景）。
    static func prepareLocalFileURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        let normalized = URL(fileURLWithPath: url.path, isDirectory: false)
        if normalized.startAccessingSecurityScopedResource() {
            retainSecurityScopedAccess(for: normalized)
        }
        return normalized
    }

    static func verifyReadableFile(at url: URL) throws {
        guard url.isFileURL else { return }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw MacPlayerPlaybackError.fileNotAccessible("文件不存在：\(url.lastPathComponent)")
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw MacPlayerPlaybackError.fileNotAccessible(
                "无法读取文件（可能缺少文件夹访问权限）：\(url.lastPathComponent)"
            )
        }
    }

    @MainActor
    @discardableResult
    static func playDroppedURL(_ url: URL, via appState: MacAppState) -> Bool {
        guard let item = makeMediaItem(from: url) else { return false }

        let prepared = prepareLocalFileURL(url)
        item.fileURL = prepared

        appState.play(item)
        return true
    }

    static func makeMediaItem(from url: URL) -> MediaItem? {
        guard MediaFormatProbe.isVideo(url) else { return nil }

        let parsed = FileNameParser.parse(url.lastPathComponent)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let item = MediaItem(
            title: parsed.title,
            fileURL: url,
            mediaType: parsed.isTV ? .tvEpisode : .movie,
            fileSize: fileSize
        )
        item.year = parsed.year
        item.seasonNumber = parsed.season
        item.episodeNumber = parsed.episode
        item.showTitle = parsed.isTV ? parsed.title : nil
        item.originalFileName = url.lastPathComponent

        let ext = url.pathExtension
        item.container = ext.isEmpty ? nil : ext.lowercased()
        return item
    }

    private static func retainSecurityScopedAccess(for url: URL) {
        retainedSecurityScopedURLs.removeAll { $0 == url }
        retainedSecurityScopedURLs.append(url)
    }
}
