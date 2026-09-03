import Foundation
import SwiftData
import Combine

@MainActor
public final class CloudSyncCoordinator: ObservableObject {
    public static let shared = CloudSyncCoordinator()

    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var statusMessage: String?

    private var debounceTask: Task<Void, Never>?

    private init() {
        lastSyncAt = CloudSyncPreferences.lastSyncAt
    }

    public var isEnabled: Bool {
        CloudSyncPreferences.isEnabled
    }

    public func setEnabled(_ enabled: Bool) {
        CloudSyncPreferences.isEnabled = enabled
        statusMessage = enabled ? "iCloud 同步已开启，重启 App 后生效" : "iCloud 同步已关闭，重启 App 后生效"
    }

    public func requestSync(reason: String, context: ModelContext?) {
        guard isEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSync(reason: reason, context: context)
        }
    }

    public func performSync(reason: String, context: ModelContext?) async {
        guard isEnabled, let context else { return }

        do {
            try CloudSyncConflictResolver.mergePendingConflicts(in: context)
            try context.save()
            let now = Date()
            lastSyncAt = now
            CloudSyncPreferences.lastSyncAt = now
            statusMessage = "已同步 (\(reason))"
            #if DEBUG
            let connections = (try? context.fetch(FetchDescriptor<SavedConnection>())) ?? []
            let types = connections.map(\.type.rawValue).sorted().joined(separator: ",")
            print("[Debug][CloudKit] local save reason=\(reason) preferenceOn=\(CloudSyncPreferences.isEnabled) attachedPrivate=\(ModelContainerFactory.openedCloudStoreWithPrivateCloudKit) connections=\(connections.count) types=\(types)")
            #endif
        } catch {
            statusMessage = "同步失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Change markers

    public func markConnectionChanged(_ connection: SavedConnection) {
        connection.updatedAt = Date()
        connection.lastModifiedDeviceId = CloudSyncDevice.id
    }

    public func markMediaProgressChanged(_ item: MediaItem, in context: ModelContext) {
        CloudMediaStateStore.upsertProgress(for: item, in: context)
    }

    public func markMediaFavoriteChanged(_ item: MediaItem, in context: ModelContext) {
        CloudMediaStateStore.upsertFavorite(for: item, in: context)
    }

    public func markFolderBookmarkChanged(_ bookmark: FolderBookmark) {
        bookmark.updatedAt = Date()
        bookmark.lastModifiedDeviceId = CloudSyncDevice.id
    }
}
