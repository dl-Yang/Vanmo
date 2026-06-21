import Foundation

struct MetadataCacheKey: Hashable, Codable, Sendable {
    let cacheKey: String
    let serverId: String?
    let sourceConnectionId: UUID?
    let fileURLString: String?
    let tmdbID: Int?

    static func from(_ item: MediaItem) -> MetadataCacheKey {
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
