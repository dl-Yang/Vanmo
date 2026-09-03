import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.com.vanmo.app"
    public static let localStoreName = "LocalStore"
    public static let cloudStoreName = "CloudStore"

    /// True only when this process opened CloudStore with `.private` and did not fall back.
    static var openedCloudStoreWithPrivateCloudKit = false

    public static let localSchema = Schema([
        MediaItem.self,
        PlaybackRecord.self,
        ScanJobRecord.self,
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
        ScanJobRecord.self,
    ])

    /// 共享 SwiftData 容器：
    /// - 本地库：MediaItem / PlaybackRecord / ScanJobRecord，永不启用 CloudKit
    /// - 云库：SavedConnection / FolderBookmark / CloudMediaState
    ///
    /// 用户打开 iCloud 同步时 CloudStore 使用 `.private(iCloud.com.vanmo.app)`。
    /// 创建抛错时回退 `.none`，必要时删除损坏的 store 后再建本地容器。
    public static func makeSharedContainer() -> ModelContainer {
        let database = resolvedCloudKitDatabase()
        #if DEBUG
        CloudStoreCloudKitAdoption.startMirroringLogs()
        print("[Debug][CloudKit] launch enabled=\(CloudSyncPreferences.isEnabled) requestPrivate=\(shouldAttachPrivateCloudKit) needsAdoption=\(CloudStoreCloudKitAdoption.needsAdoption) generation=\(UserDefaults.standard.integer(forKey: CloudStoreCloudKitAdoption.generationKey)) store=\(CloudStoreCloudKitAdoption.activeStoreName) db=\(String(describing: database)) container=\(cloudKitContainerIdentifier)")
        #endif
        return makeOnDiskContainer(
            storeDirectory: nil,
            cloudKitDatabase: database,
            resetStoresOnFailure: true,
            adoptPrivateCloudKitStore: CloudStoreCloudKitAdoption.needsAdoption
        )
    }

    static func makeOnDiskContainer(
        storeDirectory: URL?,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        resetStoresOnFailure: Bool,
        adoptPrivateCloudKitStore: Bool = false
    ) -> ModelContainer {
        let wantsPrivate = describesPrivate(cloudKitDatabase)
        var snapshot = CloudStoreSnapshot()
        var adoptionPrepared = false
        var snapshotFailed = false
        if adoptPrivateCloudKitStore, wantsPrivate {
            do {
                snapshot = try captureAdoptionSnapshot(storeDirectory: storeDirectory)
                adoptionPrepared = true
            } catch {
                snapshotFailed = true
            }
            if adoptionPrepared {
                #if DEBUG
                print("[Debug][CloudKit] reset CloudStore to adopt private CloudKit connections=\(snapshot.connections.count) bookmarks=\(snapshot.bookmarks.count) mediaStates=\(snapshot.mediaStates.count)")
                #endif
            } else {
                VanmoLogger.storage.error("CloudStore snapshot failed; keeping existing CloudStore")
                #if DEBUG
                print("[Debug][CloudKit] snapshot failed; opening legacy CloudStore without private CloudKit")
                #endif
            }
        }
        let destinationName = adoptionPrepared
            ? CloudStoreCloudKitAdoption.adoptedStoreName
            : CloudStoreCloudKitAdoption.activeStoreName
        let requestedDatabase = snapshotFailed ? .none : cloudKitDatabase
        do {
            let container = try makeContainerThrowing(
                cloudKitDatabase: requestedDatabase,
                isStoredInMemoryOnly: false,
                storeDirectory: storeDirectory,
                cloudStoreName: destinationName
            )
            openedCloudStoreWithPrivateCloudKit = wantsPrivate && !snapshotFailed
            if adoptionPrepared {
                switch finishAdoptionIfNeeded(
                    snapshot,
                    into: container,
                    storeDirectory: storeDirectory,
                    markAdopted: true
                ) {
                case .adopted, .skipped:
                    break
                case .restoreFailed:
                    openedCloudStoreWithPrivateCloudKit = false
                    _ = removeCloudStore(
                        in: storeDirectory,
                        cloudStoreName: CloudStoreCloudKitAdoption.adoptedStoreName
                    )
                    return openLocalCloudStore(
                        storeDirectory: storeDirectory,
                        resetStoresOnFailure: false
                    )
                }
            }
            #if DEBUG
            print("[Debug][CloudKit] ModelContainer opened attachedPrivate=\(openedCloudStoreWithPrivateCloudKit) store=\(destinationName) wantsPrivate=\(wantsPrivate)")
            logCloudStoreCounts(container)
            #endif
            return container
        } catch {
            openedCloudStoreWithPrivateCloudKit = false
            VanmoLogger.storage.error(
                "CloudKit ModelContainer failed: \(error.localizedDescription, privacy: .public); retrying local CloudStore"
            )
            #if DEBUG
            print("[Debug][CloudKit] create threw \(error.localizedDescription); retrying cloudKitDatabase=none")
            #endif
            if adoptionPrepared {
                _ = removeCloudStore(
                    in: storeDirectory,
                    cloudStoreName: CloudStoreCloudKitAdoption.adoptedStoreName
                )
            }
            return openLocalCloudStore(
                storeDirectory: storeDirectory,
                resetStoresOnFailure: resetStoresOnFailure && !adoptionPrepared
            )
        }
    }

    static func makeContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        isStoredInMemoryOnly: Bool,
        fallbackToLocalOnFailure: Bool
    ) -> ModelContainer {
        do {
            return try makeContainerThrowing(
                cloudKitDatabase: cloudKitDatabase,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        } catch {
            guard fallbackToLocalOnFailure else {
                fatalError("Could not create ModelContainer: \(error)")
            }
            VanmoLogger.storage.error(
                "CloudKit ModelContainer failed: \(error.localizedDescription, privacy: .public); falling back to local CloudStore"
            )
            do {
                return try makeContainerThrowing(
                    cloudKitDatabase: .none,
                    isStoredInMemoryOnly: isStoredInMemoryOnly
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    static func makeContainerThrowing(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        isStoredInMemoryOnly: Bool,
        storeDirectory: URL? = nil,
        cloudStoreName: String = CloudStoreCloudKitAdoption.activeStoreName
    ) throws -> ModelContainer {
        let configurations = makeConfigurations(
            cloudKitDatabase: cloudKitDatabase,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            storeDirectory: storeDirectory,
            cloudStoreName: cloudStoreName
        )
        return try ModelContainer(
            for: schema,
            configurations: [configurations.local, configurations.cloud]
        )
    }

    static func makeConfigurations(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        isStoredInMemoryOnly: Bool,
        storeDirectory: URL? = nil,
        cloudStoreName: String = CloudStoreCloudKitAdoption.activeStoreName
    ) -> (local: ModelConfiguration, cloud: ModelConfiguration) {
        if let storeDirectory {
            return (
                ModelConfiguration(
                    localStoreName,
                    schema: localSchema,
                    url: storeDirectory.appending(path: "\(localStoreName).store"),
                    cloudKitDatabase: .none
                ),
                ModelConfiguration(
                    cloudStoreName,
                    schema: cloudSchema,
                    url: storeDirectory.appending(path: "\(cloudStoreName).store"),
                    cloudKitDatabase: cloudKitDatabase
                )
            )
        }
        return (
            ModelConfiguration(
                localStoreName,
                schema: localSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            ),
            ModelConfiguration(
                cloudStoreName,
                schema: cloudSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: cloudKitDatabase
            )
        )
    }

    static func resolvedCloudKitDatabase() -> ModelConfiguration.CloudKitDatabase {
        shouldAttachPrivateCloudKit ? .private(cloudKitContainerIdentifier) : .none
    }

    static func describesPrivate(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
        String(describing: database).contains(cloudKitContainerIdentifier)
    }

    static func describesNone(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
        !describesPrivate(database)
    }

    static var shouldAttachPrivateCloudKit: Bool {
        #if CLOUDKIT_SYNC_ENABLED
        CloudSyncPreferences.isEnabled
        #else
        false
        #endif
    }

    private enum AdoptionFinish {
        case adopted
        case restoreFailed
        case skipped
    }

    private static func openLocalCloudStore(
        storeDirectory: URL?,
        resetStoresOnFailure: Bool
    ) -> ModelContainer {
        do {
            return try makeContainerThrowing(
                cloudKitDatabase: .none,
                isStoredInMemoryOnly: false,
                storeDirectory: storeDirectory,
                cloudStoreName: CloudStoreCloudKitAdoption.activeStoreName
            )
        } catch {
            guard resetStoresOnFailure else {
                fatalError("Could not create ModelContainer: \(error)")
            }
            VanmoLogger.storage.error(
                "Local ModelContainer failed: \(error.localizedDescription, privacy: .public); removing LocalStore and CloudStore"
            )
            removeNamedStores(in: storeDirectory)
            do {
                return try makeContainerThrowing(
                    cloudKitDatabase: .none,
                    isStoredInMemoryOnly: false,
                    storeDirectory: storeDirectory,
                    cloudStoreName: CloudStoreCloudKitAdoption.activeStoreName
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    private static func finishAdoptionIfNeeded(
        _ snapshot: CloudStoreSnapshot,
        into container: ModelContainer,
        storeDirectory: URL?,
        markAdopted: Bool
    ) -> AdoptionFinish {
        let restored = restoreCloudStoreSnapshot(snapshot, into: container)
        guard markAdopted, openedCloudStoreWithPrivateCloudKit, restored else {
            #if DEBUG
            if markAdopted {
                print("[Debug][CloudKit] adoption not marked attachedPrivate=\(openedCloudStoreWithPrivateCloudKit) restored=\(restored)")
            }
            #endif
            return restored ? .skipped : .restoreFailed
        }
        CloudStoreCloudKitAdoption.markAdopted()
        for name in CloudStoreCloudKitAdoption.previousStoreNames {
            _ = removeCloudStore(in: storeDirectory, cloudStoreName: name)
        }
        #if DEBUG
        print("[Debug][CloudKit] adopted \(CloudStoreCloudKitAdoption.adoptedStoreName) generation=\(CloudStoreCloudKitAdoption.currentGeneration)")
        #endif
        return .adopted
    }

    private static func captureAdoptionSnapshot(storeDirectory: URL?) throws -> CloudStoreSnapshot {
        let generation = UserDefaults.standard.integer(forKey: CloudStoreCloudKitAdoption.generationKey)
        var lastError: Error = CloudStoreCloudKitAdoption.SnapshotError.storeMissing(
            CloudStoreCloudKitAdoption.sourceStoreNameForAdoption
        )
        for candidate in stride(from: max(generation, 0), through: 0, by: -1) {
            let name = CloudStoreCloudKitAdoption.storeName(forGeneration: candidate)
            do {
                return try captureCloudStoreSnapshot(
                    storeDirectory: storeDirectory,
                    cloudStoreName: name
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func captureCloudStoreSnapshot(
        storeDirectory: URL?,
        cloudStoreName: String = CloudStoreCloudKitAdoption.legacyStoreName
    ) throws -> CloudStoreSnapshot {
        let storeURL = makeConfigurations(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: false,
            storeDirectory: storeDirectory,
            cloudStoreName: cloudStoreName
        ).cloud.url
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw CloudStoreCloudKitAdoption.SnapshotError.storeMissing(cloudStoreName)
        }
        let snapshot: CloudStoreSnapshot
        do {
            let container = try makeContainerThrowing(
                cloudKitDatabase: .none,
                isStoredInMemoryOnly: false,
                storeDirectory: storeDirectory,
                cloudStoreName: cloudStoreName
            )
            let context = ModelContext(container)
            snapshot = CloudStoreSnapshot(
                connections: try context.fetch(FetchDescriptor<SavedConnection>()).map(SavedConnectionDraft.init),
                bookmarks: try context.fetch(FetchDescriptor<FolderBookmark>()).map(FolderBookmarkDraft.init),
                mediaStates: try context.fetch(FetchDescriptor<CloudMediaState>()).map(CloudMediaStateDraft.init)
            )
        }
        var overlaid = snapshot
        overlayLegacyConnectionTypes(onto: &overlaid, storeURL: storeURL)
        return overlaid
    }

    #if DEBUG
    private static func logCloudStoreCounts(_ container: ModelContainer) {
        let context = ModelContext(container)
        let connections = (try? context.fetch(FetchDescriptor<SavedConnection>())) ?? []
        let types = connections.map(\.type.rawValue).sorted().joined(separator: ",")
        let bookmarks = (try? context.fetch(FetchDescriptor<FolderBookmark>()))?.count ?? 0
        let states = (try? context.fetch(FetchDescriptor<CloudMediaState>()))?.count ?? 0
        print("[Debug][CloudKit] cloudCounts connections=\(connections.count) types=\(types) bookmarks=\(bookmarks) mediaStates=\(states)")
    }
    #endif

    private static func overlayLegacyConnectionTypes(
        onto snapshot: inout CloudStoreSnapshot,
        storeURL: URL
    ) {
        let rawTypes = CloudStoreSQLiteTypeOverlay.rawTypesByConnectionID(storeURL: storeURL)
        guard !rawTypes.isEmpty else { return }
        for index in snapshot.connections.indices {
            let id = snapshot.connections[index].id
            if let raw = rawTypes[id], let type = ConnectionType(rawValue: raw) {
                snapshot.connections[index].type = type
            }
        }
    }

    @discardableResult
    static func restoreCloudStoreSnapshot(_ snapshot: CloudStoreSnapshot, into container: ModelContainer) -> Bool {
        guard !snapshot.isEmpty else { return true }
        let context = ModelContext(container)
        for draft in snapshot.connections {
            context.insert(SavedConnection(draft: draft))
        }
        for draft in snapshot.bookmarks {
            context.insert(FolderBookmark(draft: draft))
        }
        for draft in snapshot.mediaStates {
            context.insert(CloudMediaState(draft: draft))
        }
        do {
            try context.save()
            return true
        } catch {
            VanmoLogger.storage.error(
                "CloudStore restore failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    static func removeCloudStore(
        in storeDirectory: URL?,
        cloudStoreName: String = CloudStoreCloudKitAdoption.legacyStoreName
    ) -> Bool {
        let configurations = makeConfigurations(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: false,
            storeDirectory: storeDirectory,
            cloudStoreName: cloudStoreName
        )
        removeStoreFiles(at: configurations.cloud.url)
        return !FileManager.default.fileExists(atPath: configurations.cloud.url.path)
    }

    static func removeNamedStores(in storeDirectory: URL?) {
        let configurations = makeConfigurations(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: false,
            storeDirectory: storeDirectory,
            cloudStoreName: CloudStoreCloudKitAdoption.legacyStoreName
        )
        removeStoreFiles(at: configurations.local.url)
        for name in CloudStoreCloudKitAdoption.previousStoreNames + [CloudStoreCloudKitAdoption.adoptedStoreName] {
            _ = removeCloudStore(in: storeDirectory, cloudStoreName: name)
        }
    }

    static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal", "-journal"] {
            let path = url.path + suffix
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.removeItem(atPath: path)
        }
        let storeName = url.lastPathComponent
        let directory = url.deletingLastPathComponent()
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for item in items where item.lastPathComponent.hasPrefix(storeName) {
            try? fileManager.removeItem(at: item)
        }
    }
}
