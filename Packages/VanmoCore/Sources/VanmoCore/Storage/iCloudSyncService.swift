import Foundation

/// 历史占位：KVS 快照同步已替换为 CloudKit-backed SwiftData。
/// 保留类型别名，避免旧引用编译失败。
typealias ICloudSyncService = CloudSyncCoordinator

public struct iCloudSyncSnapshot: Codable, Equatable {
    public var connectionIDs: [UUID]
    public var favoriteItemIDs: [UUID]
    public var playbackPositions: [UUID: TimeInterval]
    public var folderBookmarkIDs: [UUID]
}
