import Foundation

public enum OfficialPosterSource {
    public static func resolve(
        type: ConnectionType,
        connectionId: UUID,
        path: String,
        password: String?
    ) async -> ThumbnailOfficialPoster {
        guard type.usesOfficialDownloadLink else { return .useKeyframe }

        let service = BaiduNetdiskService()
        do {
            try await service.connect(
                config: ConnectionConfig(connectionId: connectionId, type: type, host: "", password: password)
            )
            defer { Task { await service.disconnect() } }
            if let data = try await service.officialThumbnailJPEG(forFilePath: path) {
                return .jpeg(data)
            }
            return .skipKeyframe
        } catch {
            LibraryScanDebugLog.thumbnail(
                "officialPosterFail file=\(LibraryScanDebugLog.leaf(path)) error=\(error.localizedDescription)"
            )
            return .skipKeyframe
        }
    }
}
