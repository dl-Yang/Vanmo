import SwiftData
import XCTest
@testable import VanmoCore

final class ConnectionVisibilityTests: XCTestCase {
    func testThisDeviceTombstoneHidesConnection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let connection = SavedConnection(name: "Emby", type: .emby, host: "emby.local")
        context.insert(connection)
        ConnectionVisibility.upsertTombstone(
            for: connection.id,
            in: context,
            deviceId: "device-a"
        )

        let hidden = ConnectionVisibility.hiddenConnectionIDs(in: context, deviceId: "device-a")
        XCTAssertEqual(hidden, [connection.id])
        XCTAssertFalse(ConnectionVisibility.isVisible(connection, hiddenIDs: hidden))
    }

    func testOtherDeviceTombstoneLeavesConnectionVisible() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let connection = SavedConnection(name: "Emby", type: .emby, host: "emby.local")
        context.insert(connection)
        ConnectionVisibility.upsertTombstone(
            for: connection.id,
            in: context,
            deviceId: "device-b"
        )

        let hidden = ConnectionVisibility.hiddenConnectionIDs(in: context, deviceId: "device-a")
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertTrue(ConnectionVisibility.isVisible(connection, hiddenIDs: hidden))
    }

    func testGlobalDeletedAtStillHidesConnection() throws {
        let connection = SavedConnection(name: "Gone", type: .smb, host: "gone.local")
        connection.deletedAt = Date()
        XCTAssertFalse(ConnectionVisibility.isVisible(connection, hiddenIDs: []))
    }

    func testUpsertTombstoneDoesNotDuplicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let connectionId = UUID()
        ConnectionVisibility.upsertTombstone(for: connectionId, in: context, deviceId: "device-a")
        ConnectionVisibility.upsertTombstone(for: connectionId, in: context, deviceId: "device-a")
        try context.save()

        let tombstones = try context.fetch(FetchDescriptor<ConnectionTombstone>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.connectionId, connectionId)
    }

    func testRemoveTombstoneUnhidesConnection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let connection = SavedConnection(name: "Emby", type: .emby, host: "emby.local")
        context.insert(connection)
        ConnectionVisibility.upsertTombstone(for: connection.id, in: context, deviceId: "device-a")
        ConnectionVisibility.removeTombstone(for: connection.id, in: context, deviceId: "device-a")

        let hidden = ConnectionVisibility.hiddenConnectionIDs(in: context, deviceId: "device-a")
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertTrue(ConnectionVisibility.isVisible(connection, hiddenIDs: hidden))
    }

    func testUnprocessedConnectionsSkipHiddenIDs() {
        let live = SavedConnection(name: "Live", type: .emby, host: "live.local")
        let hidden = SavedConnection(name: "Hidden", type: .emby, host: "hidden.local")
        let suiteName = "ConnectionVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let newcomers = CloudSyncedConnectionActivation.unprocessedConnections(
            from: [live, hidden],
            hiddenIDs: [hidden.id],
            defaults: defaults
        )

        XCTAssertEqual(newcomers.map(\.id), [live.id])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
    }
}

final class ConnectionLocalCleanupTests: XCTestCase {
    func testDeleteLocalMediaRemovesItemsAndPlaybackRecords() throws {
        let container = try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(container)
        let connectionId = UUID()
        let otherConnectionId = UUID()

        let kept = MediaItem(title: "Keep", fileURL: URL(fileURLWithPath: "/tmp/keep.mkv"), mediaType: .movie)
        kept.sourceConnectionId = otherConnectionId
        let removed = MediaItem(title: "Gone", fileURL: URL(fileURLWithPath: "/tmp/gone.mkv"), mediaType: .movie)
        removed.sourceConnectionId = connectionId
        context.insert(kept)
        context.insert(removed)
        context.insert(PlaybackRecord(mediaItemID: kept.id, position: 10, duration: 100))
        context.insert(PlaybackRecord(mediaItemID: removed.id, position: 20, duration: 100))
        try context.save()

        ConnectionLocalCleanup.deleteLocalMedia(for: connectionId, in: context)
        try context.save()

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.map(\.title), ["Keep"])
        let records = try context.fetch(FetchDescriptor<PlaybackRecord>())
        XCTAssertEqual(records.map(\.mediaItemID), [kept.id])
    }
}
