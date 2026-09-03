import CoreData
import SwiftData
import XCTest
@testable import VanmoCore

final class ModelContainerFactoryTests: XCTestCase {
    func testCloudStoreSchemaAcceptsCloudKitConfiguration() throws {
        let container = try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .private(ModelContainerFactory.cloudKitContainerIdentifier),
            isStoredInMemoryOnly: true
        )
        XCTAssertNotNil(container)
    }

    func testCloudKitConfiguredContainerCanInsertSavedConnection() {
        let container = ModelContainerFactory.makeContainer(
            cloudKitDatabase: .private(ModelContainerFactory.cloudKitContainerIdentifier),
            isStoredInMemoryOnly: true,
            fallbackToLocalOnFailure: true
        )
        XCTAssertNotNil(container)

        let context = ModelContext(container)
        let connection = SavedConnection(name: "Test", type: .smb, host: "example.local")
        context.insert(connection)
        XCTAssertNoThrow(try context.save())
    }

    func testLaunchPathCreatesOnDiskStoresWithoutCloudKit() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true
        )
        let context = ModelContext(container)
        context.insert(SavedConnection(name: "Launch", type: .smb, host: "example.local"))
        XCTAssertNoThrow(try context.save())

        let configurations = ModelContainerFactory.makeConfigurations(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: false,
            storeDirectory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: configurations.local.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configurations.cloud.url.path))
    }

    func testOnDiskPrivateFallsBackToLocalWhenNeeded() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .private(ModelContainerFactory.cloudKitContainerIdentifier),
            resetStoresOnFailure: true
        )
        let context = ModelContext(container)
        context.insert(SavedConnection(name: "Fallback", type: .smb, host: "example.local"))
        XCTAssertNoThrow(try context.save())
    }

    func testCorruptOnDiskStoresAreRemovedThenRecreated() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let localURL = directory.appending(path: "\(ModelContainerFactory.localStoreName).store")
        try Data("not-a-sqlite-store".utf8).write(to: localURL)

        let container = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true
        )
        let context = ModelContext(container)
        context.insert(SavedConnection(name: "Recovered", type: .webdav, host: "example.local"))
        XCTAssertNoThrow(try context.save())
    }

    func testUnsetCloudSyncPreferenceDefaultsToEnabled() {
        let defaults = UserDefaults.standard
        let key = CloudSyncPreferences.enabledKey
        let previous = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertTrue(CloudSyncPreferences.isEnabled)
    }

    func testRestoringSnapshotIntoFreshCloudStorePreservesIdentity() throws {
        let sourceDirectory = try makeTemporaryStoreDirectory()
        let destinationDirectory = try makeTemporaryStoreDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let originalID = try seedCloudStore(
            in: sourceDirectory,
            connectionName: "Adopt",
            host: "example.local",
            includeLocalJob: true
        )
        let snapshot = try ModelContainerFactory.captureCloudStoreSnapshot(
            storeDirectory: sourceDirectory,
            cloudStoreName: CloudStoreCloudKitAdoption.legacyStoreName
        )
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections.first?.id, originalID)

        let destination = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: destinationDirectory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true
        )
        XCTAssertTrue(ModelContainerFactory.restoreCloudStoreSnapshot(snapshot, into: destination))
        let restored = try ModelContext(destination).fetch(FetchDescriptor<SavedConnection>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, originalID)
        XCTAssertEqual(restored.first?.host, "example.local")
    }

    func testRemovingCloudStoreLeavesLocalScanJobs() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try seedCloudStore(
            in: directory,
            connectionName: "Adopt",
            host: "example.local",
            includeLocalJob: true
        )
        XCTAssertTrue(
            ModelContainerFactory.removeCloudStore(
                in: directory,
                cloudStoreName: CloudStoreCloudKitAdoption.legacyStoreName
            )
        )

        let opened = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true
        )
        let context = ModelContext(opened)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedConnection>()).isEmpty)
        let jobs = try context.fetch(FetchDescriptor<ScanJobRecord>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.connectionName, "Adopt")
    }

    func testAdoptionDoesNotMarkWhenOpenedWithoutPrivateCloudKit() throws {
        let defaults = UserDefaults.standard
        let generationKey = CloudStoreCloudKitAdoption.generationKey
        let enabledKey = CloudSyncPreferences.enabledKey
        let previousGeneration = defaults.object(forKey: generationKey)
        let previousEnabled = defaults.object(forKey: enabledKey)
        defaults.removeObject(forKey: generationKey)
        defaults.set(true, forKey: enabledKey)
        defer {
            CloudStoreCloudKitAdoption.restoreGeneration(previousGeneration)
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }
        }

        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try seedCloudStore(
            in: directory,
            connectionName: "Keep",
            host: "example.local",
            type: .webdav,
            includeLocalJob: false
        )

        let opened = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true,
            adoptPrivateCloudKitStore: true
        )
        let connections = try ModelContext(opened).fetch(FetchDescriptor<SavedConnection>())
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.name, "Keep")
        XCTAssertEqual(defaults.integer(forKey: generationKey), 0)
        XCTAssertTrue(CloudStoreCloudKitAdoption.needsAdoption)
    }

    func testCloudStoreManagedObjectModelMeetsCloudKitRules() throws {
        guard #available(iOS 18, macOS 15, *) else {
            throw XCTSkip("NSManagedObjectModel.makeManagedObjectModel requires iOS 18 / macOS 15")
        }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [
            SavedConnection.self,
            FolderBookmark.self,
            CloudMediaState.self,
        ]) else {
            XCTFail("CloudStore managed object model was not created")
            return
        }

        var problems: [String] = []
        var report: [String] = []
        for entity in model.entities.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            let uniqueness = entity.uniquenessConstraints
            if !uniqueness.isEmpty {
                problems.append("\(entity.name ?? "?"): unique \(uniqueness)")
            }
            for attribute in entity.attributesByName.values.sorted(by: { $0.name < $1.name }) {
                let defaultText = attribute.defaultValue.map { String(describing: $0) } ?? "nil"
                report.append(
                    "\(entity.name ?? "?").\(attribute.name) type=\(attribute.attributeType.rawValue) optional=\(attribute.isOptional) default=\(defaultText)"
                )
                if !attribute.isOptional && attribute.defaultValue == nil && !attribute.isTransient {
                    problems.append("\(entity.name ?? "?").\(attribute.name) missing default type=\(attribute.attributeType.rawValue)")
                }
                if attribute.attributeType == .transformableAttributeType {
                    problems.append("\(entity.name ?? "?").\(attribute.name) transformable")
                }
            }
            for relationship in entity.relationshipsByName.values {
                if !relationship.isOptional {
                    problems.append("\(entity.name ?? "?").\(relationship.name) required relationship")
                }
            }
        }
        print("[CloudKitModel] \(report.joined(separator: " | "))")
        XCTAssertFalse(
            report.contains("type=2100"),
            "CloudStore must not persist composite attributes: \(report)"
        )
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    func testSavedConnectionTypePersistsAsRawString() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalID = try seedCloudStore(
            in: directory,
            connectionName: "SMB",
            host: "example.local",
            type: .smb,
            includeLocalJob: false
        )
        let snapshot = try ModelContainerFactory.captureCloudStoreSnapshot(
            storeDirectory: directory,
            cloudStoreName: CloudStoreCloudKitAdoption.legacyStoreName
        )
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections.first?.id, originalID)
        XCTAssertEqual(snapshot.connections.first?.type, .smb)
    }

    func testCloudStoreNameFollowsGeneration() {
        XCTAssertEqual(CloudStoreCloudKitAdoption.storeName(forGeneration: 0), "CloudStore")
        XCTAssertEqual(CloudStoreCloudKitAdoption.storeName(forGeneration: 1), "CloudStore-ck1")
        XCTAssertEqual(CloudStoreCloudKitAdoption.storeName(forGeneration: 2), "CloudStore-ck2")
        XCTAssertEqual(CloudStoreCloudKitAdoption.storeName(forGeneration: 3), "CloudStore-ck3")
        XCTAssertEqual(CloudStoreCloudKitAdoption.adoptedStoreName, "CloudStore-ck3")
        XCTAssertEqual(
            CloudStoreCloudKitAdoption.previousStoreNames,
            ["CloudStore", "CloudStore-ck1", "CloudStore-ck2"]
        )
    }

    func testCaptureMissingCloudStoreDoesNotCreateEmptyFile() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(
            try ModelContainerFactory.captureCloudStoreSnapshot(
                storeDirectory: directory,
                cloudStoreName: CloudStoreCloudKitAdoption.legacyStoreName
            )
        )
        let storeURL = directory.appending(path: "CloudStore.store")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testDescribesNoneDoesNotTreatPrivateDatabaseAsNone() {
        let privateDatabase = ModelConfiguration.CloudKitDatabase.private(
            ModelContainerFactory.cloudKitContainerIdentifier
        )
        let noneDatabase: ModelConfiguration.CloudKitDatabase = .none
        XCTAssertTrue(String(describing: privateDatabase).contains(ModelContainerFactory.cloudKitContainerIdentifier))
        XCTAssertFalse(String(describing: noneDatabase).contains(ModelContainerFactory.cloudKitContainerIdentifier))
        XCTAssertFalse(ModelContainerFactory.describesNone(privateDatabase))
        XCTAssertTrue(ModelContainerFactory.describesPrivate(privateDatabase))
        XCTAssertTrue(ModelContainerFactory.describesNone(noneDatabase))
        XCTAssertFalse(ModelContainerFactory.describesPrivate(noneDatabase))
    }

    func testResolvedCloudKitDatabaseFollowsPreference() {
        let defaults = UserDefaults.standard
        let key = CloudSyncPreferences.enabledKey
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)
        XCTAssertFalse(ModelContainerFactory.shouldAttachPrivateCloudKit)

        defaults.set(true, forKey: key)
        XCTAssertTrue(ModelContainerFactory.shouldAttachPrivateCloudKit)
    }

    private func seedCloudStore(
        in directory: URL,
        connectionName: String,
        host: String,
        type: ConnectionType = .smb,
        includeLocalJob: Bool
    ) throws -> UUID {
        let seed = ModelContainerFactory.makeOnDiskContainer(
            storeDirectory: directory,
            cloudKitDatabase: .none,
            resetStoresOnFailure: true
        )
        let context = ModelContext(seed)
        let connection = SavedConnection(name: connectionName, type: type, host: host)
        let id = connection.id
        context.insert(connection)
        if includeLocalJob {
            context.insert(
                ScanJobRecord(
                    connectionId: id,
                    connectionName: connectionName,
                    rootPath: "/",
                    isPartialScan: false,
                    forceFullScan: false
                )
            )
        }
        try context.save()
        return id
    }

    private func makeTemporaryStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "VanmoModelContainerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
