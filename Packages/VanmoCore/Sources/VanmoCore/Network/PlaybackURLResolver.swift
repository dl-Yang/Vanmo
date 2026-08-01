import Foundation

public enum PlaybackURLResolver {
    public static func isPlaceholder(_ url: URL) -> Bool {
        url.scheme == "vanmo" && url.host == "playback"
    }

    public static func catalogURL(for file: RemoteFile, connectionType: ConnectionType) -> URL {
        connectionType.catalogPlaybackURL(serverPath: file.path)
    }

    public static func catalogURL(serverPath: String, connectionType: ConnectionType) -> URL {
        connectionType.catalogPlaybackURL(serverPath: serverPath)
    }

    public static func storageURL(
        for file: RemoteFile,
        service: RemoteFileService
    ) -> URL {
        if service.type.requiresLazyPlaybackURL {
            return catalogURL(for: file, connectionType: service.type)
        }
        // 扫描阶段仍返回占位，调用方在需要播放/下载时再 resolvePlaybackURL。
        return catalogURL(for: file, connectionType: service.type)
    }

    public static func resolvePlaybackURL(
        item: MediaItem,
        service: RemoteFileService
    ) async throws -> URL {
        if isPlaceholder(item.fileURL) {
            guard let serverPath = item.serverId else {
                throw NetworkError.invalidURL
            }
            let file = RemoteFile(
                name: item.originalFileName ?? (serverPath as NSString).lastPathComponent,
                path: serverPath,
                size: item.fileSize,
                isDirectory: false,
                modifiedDate: item.remoteModifiedAt,
                type: .video
            )
            return try await service.streamURL(for: file)
        }
        return item.fileURL
    }

    public static func resolvePlaybackURL(
        serverPath: String,
        fileName: String,
        fileSize: Int64,
        modifiedDate: Date?,
        service: RemoteFileService
    ) async throws -> URL {
        let file = RemoteFile(
            name: fileName,
            path: serverPath,
            size: fileSize,
            isDirectory: false,
            modifiedDate: modifiedDate,
            type: .video
        )
        return try await service.streamURL(for: file)
    }
}
