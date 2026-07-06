import Foundation
import SwiftData

/// 跨设备 CloudKit 同步的播放进度与收藏状态（不包含完整 MediaItem 元数据）。
@Model
public final class CloudMediaState {
    @Attribute(.unique) var mediaKey: String
    public var mediaItemID: UUID?
    public var sourceConnectionId: UUID?
    public var lastPlaybackPosition: TimeInterval = 0
    public var lastPlayedAt: Date?
    public var isWatched: Bool = false
    public var isFavorite: Bool = false
    public var progressUpdatedAt: Date?
    public var favoriteUpdatedAt: Date?
    public var syncUpdatedAt: Date?
    public var lastModifiedDeviceId: String?
    public var deletedAt: Date?

    public init(mediaKey: String, mediaItemID: UUID?, sourceConnectionId: UUID?) {
        self.mediaKey = mediaKey
        self.mediaItemID = mediaItemID
        self.sourceConnectionId = sourceConnectionId
        self.lastModifiedDeviceId = CloudSyncDevice.id
    }
}

public enum CloudMediaStateStore {
    public static func mediaKey(for item: MediaItem) -> String {
        item.fileURL.absoluteString
    }

    @MainActor
    public static func fetchOrCreate(for item: MediaItem, in context: ModelContext) -> CloudMediaState {
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
    public static func upsertProgress(for item: MediaItem, in context: ModelContext) {
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
    public static func upsertFavorite(for item: MediaItem, in context: ModelContext) {
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
    public static func applyCloudStates(in context: ModelContext) throws {
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
