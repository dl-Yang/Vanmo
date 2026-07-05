import Foundation

/// 历史占位：KVS 快照同步已替换为 CloudKit-backed SwiftData。
/// 保留类型别名，避免旧引用编译失败。
typealias ICloudSyncService = CloudSyncCoordinator

struct iCloudSyncSnapshot: Codable, Equatable {
    var connectionIDs: [UUID]
    var favoriteItemIDs: [UUID]
    var playbackPositions: [UUID: TimeInterval]
    var folderBookmarkIDs: [UUID]
}
