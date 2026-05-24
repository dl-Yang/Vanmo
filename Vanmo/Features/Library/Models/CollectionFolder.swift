import Foundation

/// Emby/Jellyfin VirtualFolders 接口中的 `CollectionType` 白名单。
enum EmbyCollectionType: String, Codable, Hashable, Sendable {
    case movies
    case tvshows
    case playlists

    init?(raw: String?) {
        switch raw?.lowercased() {
        case "movies": self = .movies
        case "tvshows": self = .tvshows
        case "playlist", "playlists": self = .playlists
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .movies: return "电影"
        case .tvshows: return "电视剧"
        case .playlists: return "播放列表"
        }
    }

    var icon: String {
        switch self {
        case .movies: return "film"
        case .tvshows: return "tv"
        case .playlists: return "music.note.list"
        }
    }
}

/// `/Library/VirtualFolders` 返回的媒体库根目录。
struct CollectionFolder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let collectionType: EmbyCollectionType
    let posterURL: URL?
    let serverConnectionId: UUID
    let serverConnectionName: String
}

/// 分页拉取 CollectionFolder 内媒体条目时的结果页。
struct ServerItemsPage: Sendable {
    let items: [ServerMediaItem]
    let totalRecordCount: Int
    var hasMore: Bool { items.count < totalRecordCount }
}
