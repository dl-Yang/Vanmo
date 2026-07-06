import Foundation

public struct MetadataCacheKey: Hashable, Codable, Sendable {
    public let cacheKey: String
    public let serverId: String?
    public let sourceConnectionId: UUID?
    public let fileURLString: String?
    public let tmdbID: Int?

    public static func from(_ item: MediaItem) -> MetadataCacheKey {
        let serverId = item.serverId?.isEmpty == false ? item.serverId : nil
        let connectionId = item.sourceConnectionId
        let fileURL = item.fileURL.absoluteString
        let tmdbID = item.tmdbID

        let cacheKey: String
        if let serverId {
            if let connectionId {
                cacheKey = "server:\(connectionId.uuidString):\(serverId)"
            } else {
                cacheKey = "server:\(serverId)"
            }
        } else {
            cacheKey = "file:\(fileURL)"
        }

        return MetadataCacheKey(
            cacheKey: cacheKey,
            serverId: serverId,
            sourceConnectionId: connectionId,
            fileURLString: fileURL,
            tmdbID: tmdbID
        )
    }
}
