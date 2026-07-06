import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.com.vanmo.app"

    public static let localSchema = Schema([
        MediaItem.self,
        PlaybackRecord.self,
    ])

    public static let cloudSchema = Schema([
        SavedConnection.self,
        FolderBookmark.self,
        CloudMediaState.self,
    ])

    public static let schema = Schema([
        MediaItem.self,
        SavedConnection.self,
        PlaybackRecord.self,
        FolderBookmark.self,
        CloudMediaState.self,
    ])

    /// 共享 SwiftData 容器：
    /// - 本地库：MediaItem / PlaybackRecord（不同步 CloudKit，避免媒体服务器条目污染）
    /// - 云库：SavedConnection / FolderBookmark / CloudMediaState
    ///
    /// Debug / 个人开发者账号构建不含 iCloud entitlement，CloudKit 仅在 Release + `CLOUDKIT_SYNC_ENABLED` 时启用。
    public static func makeSharedContainer() -> ModelContainer {
        let cloudKitDatabase = resolvedCloudKitDatabase()

        let localConfiguration = ModelConfiguration(
            "LocalStore",
            schema: localSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let cloudConfiguration = ModelConfiguration(
            "CloudStore",
            schema: cloudSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [localConfiguration, cloudConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    private static func resolvedCloudKitDatabase() -> ModelConfiguration.CloudKitDatabase {
        #if CLOUDKIT_SYNC_ENABLED
        guard CloudSyncPreferences.isEnabled else { return .none }
        return .private(cloudKitContainerIdentifier)
        #else
        return .none
        #endif
    }
}
