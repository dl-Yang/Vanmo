import Foundation
import SwiftData

/// 跨设备 CloudKit 同步的播放进度与收藏状态（不包含完整 MediaItem 元数据）。
@Model
final class CloudMediaState {
    @Attribute(.unique) var mediaKey: String
    var mediaItemID: UUID?
    var sourceConnectionId: UUID?
    var lastPlaybackPosition: TimeInterval = 0
    var lastPlayedAt: Date?
    var isWatched: Bool = false
    var isFavorite: Bool = false
    var progressUpdatedAt: Date?
    var favoriteUpdatedAt: Date?
    var syncUpdatedAt: Date?
    var lastModifiedDeviceId: String?
    var deletedAt: Date?

    init(mediaKey: String, mediaItemID: UUID?, sourceConnectionId: UUID?) {
        self.mediaKey = mediaKey
        self.mediaItemID = mediaItemID
        self.sourceConnectionId = sourceConnectionId
        self.lastModifiedDeviceId = CloudSyncDevice.id
    }
}

enum CloudMediaStateStore {
    static func mediaKey(for item: MediaItem) -> String {
        item.fileURL.absoluteString
    }

    @MainActor
    static func fetchOrCreate(for item: MediaItem, in context: ModelContext) -> CloudMediaState {
        let key = mediaKey(for: item)
        let descriptor = FetchDescriptor<CloudMediaState>(
            predicate: #Predicate { $0.mediaKey == key && $0.deletedAt == nil }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let state = CloudMediaState(
            mediaKey: key,
            mediaItemID: item.id,
            sourceConnectionId: item.sourceConnectionId
        )
        context.insert(state)
        return state
    }

    @MainActor
    static func upsertProgress(for item: MediaItem, in context: ModelContext) {
        guard item.isProgressCloudSynced else { return }
        let state = fetchOrCreate(for: item, in: context)
        state.mediaItemID = item.id
        state.sourceConnectionId = item.sourceConnectionId
        state.lastPlaybackPosition = item.lastPlaybackPosition
        state.lastPlayedAt = item.lastPlayedAt
        state.isWatched = item.isWatched
        let now = Date()
        state.progressUpdatedAt = now
        state.syncUpdatedAt = now
        state.lastModifiedDeviceId = CloudSyncDevice.id
    }

    @MainActor
    static func upsertFavorite(for item: MediaItem, in context: ModelContext) {
        guard item.isFavoriteCloudSynced else { return }
        let state = fetchOrCreate(for: item, in: context)
        state.mediaItemID = item.id
        state.sourceConnectionId = item.sourceConnectionId
        state.isFavorite = item.isFavorite
        let now = Date()
        state.favoriteUpdatedAt = now
        state.syncUpdatedAt = now
        state.lastModifiedDeviceId = CloudSyncDevice.id
    }

    @MainActor
    static func applyCloudStates(in context: ModelContext) throws {
        let states = try context.fetch(FetchDescriptor<CloudMediaState>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        guard !states.isEmpty else { return }

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        var itemsByKey: [String: MediaItem] = [:]
        var itemsByID: [UUID: MediaItem] = [:]
        for item in items {
            itemsByKey[mediaKey(for: item)] = item
            itemsByID[item.id] = item
        }

        for state in states {
            let item = itemsByKey[state.mediaKey] ?? state.mediaItemID.flatMap { itemsByID[$0] }
            guard let item, item.isProgressCloudSynced || item.isFavoriteCloudSynced else { continue }

            if item.isProgressCloudSynced {
                CloudSyncConflictResolver.mergeProgress(
                    into: item,
                    position: state.lastPlaybackPosition,
                    playedAt: state.lastPlayedAt ?? state.progressUpdatedAt ?? .distantPast
                )
                if state.isWatched {
                    CloudSyncConflictResolver.mergeWatched(
                        into: item,
                        isWatched: true,
                        updatedAt: state.progressUpdatedAt ?? .distantPast
                    )
                }
            }

            if item.isFavoriteCloudSynced {
                CloudSyncConflictResolver.mergeFavorite(
                    into: item,
                    isFavorite: state.isFavorite,
                    updatedAt: state.favoriteUpdatedAt ?? .distantPast
                )
            }
        }
    }
}
