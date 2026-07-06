import Foundation

/// Emby/Jellyfin VirtualFolders 接口中的 `CollectionType` 白名单。
public enum EmbyCollectionType: String, Codable, Hashable, Sendable {
    case movies
    case tvshows
    case playlists

    public init?(raw: String?) {
        switch raw?.lowercased() {
        case "movies": self = .movies
        case "tvshows": self = .tvshows
        case "playlist", "playlists": self = .playlists
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .movies: return "电影"
        case .tvshows: return "电视剧"
        case .playlists: return "播放列表"
        }
    }

    public var icon: String {
        switch self {
        case .movies: return "film"
        case .tvshows: return "tv"
        case .playlists: return "music.note.list"
        }
    }
}

/// `/Library/VirtualFolders` 返回的媒体库根目录。
public struct CollectionFolder: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: EmbyCollectionType
    public let posterURL: URL?
    public let serverConnectionId: UUID
    public let serverConnectionName: String

    public init(id: String, name: String, collectionType: EmbyCollectionType, posterURL: URL?, serverConnectionId: UUID, serverConnectionName: String) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
        self.posterURL = posterURL
        self.serverConnectionId = serverConnectionId
        self.serverConnectionName = serverConnectionName
    }
}

/// 分页拉取 CollectionFolder 内媒体条目时的结果页。
public struct ServerItemsPage: Sendable {
    public let items: [ServerMediaItem]
    public let totalRecordCount: Int
    public var hasMore: Bool { items.count < totalRecordCount }
}
