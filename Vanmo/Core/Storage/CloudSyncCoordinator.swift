import Foundation
import SwiftData
import Combine

@MainActor
final class CloudSyncCoordinator: ObservableObject {
    static let shared = CloudSyncCoordinator()

    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var statusMessage: String?

    private var debounceTask: Task<Void, Never>?

    private init() {
        lastSyncAt = CloudSyncPreferences.lastSyncAt
    }

    var isEnabled: Bool {
        CloudSyncPreferences.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        CloudSyncPreferences.isEnabled = enabled
        statusMessage = enabled ? "iCloud 同步已开启，重启 App 后生效" : "iCloud 同步已关闭，重启 App 后生效"
    }

    func requestSync(reason: String, context: ModelContext?) {
        guard isEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSync(reason: reason, context: context)
        }
    }

    func performSync(reason: String, context: ModelContext?) async {
        guard isEnabled, let context else { return }

        do {
            try CloudSyncConflictResolver.mergePendingConflicts(in: context)
            try context.save()
            let now = Date()
            lastSyncAt = now
            CloudSyncPreferences.lastSyncAt = now
            statusMessage = "已同步 (\(reason))"
            #if DEBUG
            print("[Debug][CloudSync] merge complete reason=\(reason)")
            #endif
        } catch {
            statusMessage = "同步失败：\(error.localizedDescription)"
            #if DEBUG
            print("[Debug][CloudSync] merge failed reason=\(reason) error=\(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Change markers

    func markConnectionChanged(_ connection: SavedConnection) {
        connection.updatedAt = Date()
        connection.lastModifiedDeviceId = CloudSyncDevice.id
    }

    func markMediaProgressChanged(_ item: MediaItem, in context: ModelContext) {
        CloudMediaStateStore.upsertProgress(for: item, in: context)
    }

    func markMediaFavoriteChanged(_ item: MediaItem, in context: ModelContext) {
        CloudMediaStateStore.upsertFavorite(for: item, in: context)
    }

    func markFolderBookmarkChanged(_ bookmark: FolderBookmark) {
        bookmark.updatedAt = Date()
        bookmark.lastModifiedDeviceId = CloudSyncDevice.id
    }
}
