import Foundation

/// Jellyfin 媒体服务器协议实现。
///
/// Jellyfin 是 Emby 在 2018 年的开源 fork，端点和 JSON schema 与 Emby 几乎完全
/// 一致。唯一稳定的差异是 URL 前缀：
///
/// - Emby 使用 `/emby/...`
/// - Jellyfin 使用无前缀的 `/...`
///
/// 因此 `JellyfinService` 复用 `EmbyService` 的全部实现，仅切换 `type` 与
/// `apiPrefix` 参数。如果未来 Jellyfin 出现独有 endpoint，再在此薄包装中
/// override 对应方法即可，不必污染 `EmbyService`。
final class JellyfinService: MediaServerService {
    private let inner: EmbyService

    var type: ConnectionType { inner.type }
    var isConnected: Bool { inner.isConnected }

    init(session: URLSession = .shared) {
        self.inner = EmbyService(type: .jellyfin, apiPrefix: "", session: session)
    }

    func connect(config: ConnectionConfig) async throws {
        try await inner.connect(config: config)
    }

    func disconnect() async {
        await inner.disconnect()
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        try await inner.listDirectory(path: path)
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        try await inner.streamURL(for: file)
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        try await inner.download(file: file, to: localURL, progress: progress)
    }

    func streamMediaItems(
        since: Date?,
        pageSize: Int
    ) -> AsyncThrowingStream<[ServerMediaItem], Error> {
        inner.streamMediaItems(since: since, pageSize: pageSize)
    }
}
