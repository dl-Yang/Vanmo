import Foundation
import SwiftData

/// 多设备 CloudKit 同步后的本地冲突合并规则。
public enum CloudSyncConflictResolver {
    private static let progressTieBreakInterval: TimeInterval = 2

    // MARK: - Field merge

    public static func mergeProgress(into item: MediaItem, position: TimeInterval, playedAt: Date) {
        guard item.isProgressCloudSynced else { return }

        let existingPlayedAt = item.lastPlayedAt ?? .distantPast
        let existingPosition = item.lastPlaybackPosition

        if playedAt > existingPlayedAt {
            item.lastPlaybackPosition = position
            item.lastPlayedAt = playedAt
        } else if abs(playedAt.timeIntervalSince(existingPlayedAt)) <= progressTieBreakInterval,
                  position > existingPosition {
            item.lastPlaybackPosition = position
            item.lastPlayedAt = playedAt
        }
    }

    public static func mergeFavorite(into item: MediaItem, isFavorite: Bool, updatedAt: Date) {
        guard item.isFavoriteCloudSynced else { return }
        _ = updatedAt
        item.isFavorite = isFavorite
    }

    public static func mergeWatched(into item: MediaItem, isWatched: Bool, updatedAt: Date) {
        guard item.isProgressCloudSynced else { return }
        _ = updatedAt
        if isWatched {
            item.isWatched = true
        }
    }

    public static func mergeConnection(_ local: SavedConnection, with remote: SavedConnection) {
        let localUpdatedAt = local.updatedAt
        let remoteUpdatedAt = remote.updatedAt

        if remoteUpdatedAt > localUpdatedAt {
            local.name = remote.name
            local.type = remote.type
            local.host = remote.host
            local.port = remote.port
            local.username = remote.username
            local.path = remote.path
            local.isFavorite = remote.isFavorite
            local.lastConnectedAt = remote.lastConnectedAt
            local.lastSyncedAt = remote.lastSyncedAt
            local.updatedAt = remoteUpdatedAt
            local.lastModifiedDeviceId = remote.lastModifiedDeviceId
        }
    }

    public static func mergeBookmark(_ local: FolderBookmark, with remote: FolderBookmark) {
        if remote.updatedAt >= local.updatedAt {
            local.title = remote.title
            local.connectionName = remote.connectionName
            local.updatedAt = remote.updatedAt
            local.lastModifiedDeviceId = remote.lastModifiedDeviceId
        }
    }

    // MARK: - Batch reconciliation

    @MainActor
    public static func mergePendingConflicts(in context: ModelContext) throws {
        try dedupeFolderBookmarks(in: context)
        try CloudMediaStateStore.applyCloudStates(in: context)
    }

    @MainActor
    private static func dedupeFolderBookmarks(in context: ModelContext) throws {
        let bookmarks = try context.fetch(
            FetchDescriptor<FolderBookmark>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
        )
        var winners: [String: FolderBookmark] = [:]

        for bookmark in bookmarks {
            let key = "\(bookmark.connectionId.uuidString)|\(bookmark.path)"
            if let existing = winners[key] {
                if bookmark.updatedAt >= existing.updatedAt {
                    context.delete(existing)
                    winners[key] = bookmark
                } else {
                    context.delete(bookmark)
                }
            } else {
                winners[key] = bookmark
            }
        }
    }
}

public enum CloudSyncMediaEligibility {
    @MainActor
    public static func isMediaServerItem(_ item: MediaItem, in context: ModelContext?) -> Bool {
        guard let context,
              let connectionId = item.sourceConnectionId else {
            return false
        }

        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? context.fetch(descriptor).first else {
            return false
        }
        return connection.type.isMediaServer
    }

    @MainActor
    public static func isMediaServerConnection(_ connectionId: UUID, in context: ModelContext?) -> Bool {
        guard let context else { return false }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? context.fetch(descriptor).first else {
            return false
        }
        return connection.type.isMediaServer
    }
}
