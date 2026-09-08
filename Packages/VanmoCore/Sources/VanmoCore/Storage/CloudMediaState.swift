import Foundation
import SwiftData

/// 跨设备 CloudKit 同步的播放进度与收藏状态（不包含完整 MediaItem 元数据）。
@Model
public final class CloudMediaState {
    var mediaKey: String = ""
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
    /// Stable CloudKit identity: connection + server path.
    /// Never use a live `smb://user:pass@host/...` string; iOS stores
    /// `vanmo://playback/smb/...` while an older Mac row may still hold the SMB URL.
    public static func mediaKey(for item: MediaItem) -> String {
        groupingKey(
            connectionId: item.sourceConnectionId,
            serverPath: item.serverId,
            fileURL: item.fileURL
        )
    }

    public static func groupingKey(for state: CloudMediaState) -> String {
        if state.mediaKey.hasPrefix("conn:")
            || state.mediaKey.hasPrefix("path:")
            || state.mediaKey.hasPrefix("url:") {
            return state.mediaKey
        }
        if let url = URL(string: state.mediaKey) {
            return groupingKey(
                connectionId: state.sourceConnectionId,
                serverPath: nil,
                fileURL: url
            )
        }
        return state.mediaKey
    }

    public static func groupingKey(
        connectionId: UUID?,
        serverPath: String?,
        fileURL: URL
    ) -> String {
        let path = normalizedServerPath(serverPath: serverPath, fileURL: fileURL)
        if let connectionId, !path.isEmpty {
            return "conn:\(connectionId.uuidString.lowercased())|\(path)"
        }
        if !path.isEmpty {
            return "path:\(path)"
        }
        return "url:\(credentialFreeURLIdentity(fileURL))"
    }

    public static func normalizedServerPath(serverPath: String?, fileURL: URL) -> String {
        if let serverPath {
            let normalized = normalizePath(serverPath)
            if !normalized.isEmpty { return normalized }
        }
        return pathFromPlaybackOrRemoteURL(fileURL)
    }

    @MainActor
    public static func fetchOrCreate(for item: MediaItem, in context: ModelContext) -> CloudMediaState {
        let key = mediaKey(for: item)
        if let existing = fetchExact(key, in: context) {
            return existing
        }
        if let migrated = migrateLegacyRow(for: item, canonicalKey: key, in: context) {
            return migrated
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
        item.favoriteUpdatedAt = now
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
            let item = itemsByKey[groupingKey(for: state)] ?? state.mediaItemID.flatMap { itemsByID[$0] }
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

    @MainActor
    private static func fetchExact(_ key: String, in context: ModelContext) -> CloudMediaState? {
        let descriptor = FetchDescriptor<CloudMediaState>(
            predicate: #Predicate { $0.mediaKey == key && $0.deletedAt == nil }
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func migrateLegacyRow(
        for item: MediaItem,
        canonicalKey: String,
        in context: ModelContext
    ) -> CloudMediaState? {
        let rawURL = item.fileURL.absoluteString
        if rawURL != canonicalKey, let existing = fetchExact(rawURL, in: context) {
            existing.mediaKey = canonicalKey
            existing.sourceConnectionId = item.sourceConnectionId ?? existing.sourceConnectionId
            return existing
        }
        guard let connectionId = item.sourceConnectionId else { return nil }
        let path = normalizedServerPath(serverPath: item.serverId, fileURL: item.fileURL)
        guard !path.isEmpty else { return nil }
        let candidates = (try? context.fetch(FetchDescriptor<CloudMediaState>())) ?? []
        if let match = candidates.first(where: { state in
            state.deletedAt == nil
                && state.sourceConnectionId == connectionId
                && groupingKey(for: state) == canonicalKey
        }) {
            match.mediaKey = canonicalKey
            return match
        }
        return nil
    }

    static func pathFromPlaybackOrRemoteURL(_ url: URL) -> String {
        if url.scheme?.lowercased() == "vanmo", url.host?.lowercased() == "playback" {
            var parts = url.path.split(separator: "/").map(String.init)
            if let first = parts.first, ConnectionType(rawValue: first) != nil {
                parts.removeFirst()
            }
            return normalizePath(parts.joined(separator: "/"))
        }
        return normalizePath(url.path)
    }

    static func normalizePath(_ raw: String) -> String {
        var path = (raw.removingPercentEncoding ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return "" }
        if !path.hasPrefix("/") {
            path = "/\(path)"
        }
        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path.lowercased()
    }

    static func credentialFreeURLIdentity(_ url: URL) -> String {
        var parts = URLComponents()
        parts.scheme = url.scheme?.lowercased()
        parts.host = url.host?.lowercased()
        parts.port = url.port
        parts.path = normalizePath(url.path)
        return parts.string ?? normalizePath(url.path)
    }
}
