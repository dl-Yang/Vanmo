import SwiftData
import XCTest
@testable import VanmoCore

@MainActor
final class CloudMediaStateKeyTests: XCTestCase {
    func testPlaceholderAndSMBStreamURLShareConnectionPathKey() {
        let connectionId = UUID()
        let path = "/MacShare/movie.mp4"
        let placeholder = MediaItem(
            title: "Movie",
            fileURL: ConnectionType.smb.catalogPlaybackURL(serverPath: path)
        )
        placeholder.serverId = path
        placeholder.sourceConnectionId = connectionId

        let stream = MediaItem(
            title: "Movie",
            fileURL: URL(string: "smb://user@192.168.1.67/MacShare/movie.mp4")!
        )
        stream.serverId = path
        stream.sourceConnectionId = connectionId

        let placeholderKey = CloudMediaStateStore.mediaKey(for: placeholder)
        let streamKey = CloudMediaStateStore.mediaKey(for: stream)
        XCTAssertEqual(placeholderKey, streamKey)
        XCTAssertTrue(placeholderKey.hasPrefix("conn:\(connectionId.uuidString.lowercased())|"))
        XCTAssertFalse(placeholderKey.contains("smb://"))
        XCTAssertFalse(placeholderKey.contains("@"))
        XCTAssertTrue(placeholderKey.contains("/macshare/"))
    }

    func testLegacySMBStateGroupsWithPlaceholderItem() {
        let connectionId = UUID()
        let path = "/MacShare/movie.mp4"
        let item = MediaItem(
            title: "Movie",
            fileURL: ConnectionType.smb.catalogPlaybackURL(serverPath: path)
        )
        item.serverId = path
        item.sourceConnectionId = connectionId

        let legacy = CloudMediaState(
            mediaKey: "smb://user:secret@192.168.1.67/MacShare/movie.mp4",
            mediaItemID: UUID(),
            sourceConnectionId: connectionId
        )
        XCTAssertEqual(
            CloudMediaStateStore.groupingKey(for: legacy),
            CloudMediaStateStore.mediaKey(for: item)
        )
        XCTAssertFalse(CloudMediaStateStore.groupingKey(for: legacy).contains("secret"))
    }

    func testFetchOrCreateMigratesLegacySMBKey() throws {
        let container = try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(container)
        let connectionId = UUID()
        let path = "/MacShare/movie.mp4"
        let item = MediaItem(
            title: "Movie",
            fileURL: ConnectionType.smb.catalogPlaybackURL(serverPath: path)
        )
        item.serverId = path
        item.sourceConnectionId = connectionId
        context.insert(item)

        let legacy = CloudMediaState(
            mediaKey: "smb://user@host/MacShare/movie.mp4",
            mediaItemID: item.id,
            sourceConnectionId: connectionId
        )
        legacy.lastPlaybackPosition = 42
        legacy.lastPlayedAt = Date(timeIntervalSince1970: 9)
        context.insert(legacy)
        try context.save()

        let state = CloudMediaStateStore.fetchOrCreate(for: item, in: context)
        XCTAssertEqual(state.mediaKey, CloudMediaStateStore.mediaKey(for: item))
        XCTAssertEqual(state.lastPlaybackPosition, 42)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CloudMediaState>()).count, 1)
    }

    func testDedupeMergesPlaceholderAndSMBRowsThenApplies() throws {
        let container = try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(container)
        let connectionId = UUID()
        let path = "/MacShare/movie.mp4"
        let item = MediaItem(
            title: "Movie",
            fileURL: ConnectionType.smb.catalogPlaybackURL(serverPath: path)
        )
        item.serverId = path
        item.sourceConnectionId = connectionId
        item.lastPlaybackPosition = 5
        item.lastPlayedAt = Date(timeIntervalSince1970: 1)
        context.insert(item)

        let placeholderState = CloudMediaState(
            mediaKey: ConnectionType.smb.catalogPlaybackURL(serverPath: path).absoluteString,
            mediaItemID: item.id,
            sourceConnectionId: connectionId
        )
        placeholderState.lastPlaybackPosition = 20
        placeholderState.lastPlayedAt = Date(timeIntervalSince1970: 2)
        placeholderState.syncUpdatedAt = Date(timeIntervalSince1970: 2)

        let smbState = CloudMediaState(
            mediaKey: "smb://user@192.168.1.67/MacShare/movie.mp4",
            mediaItemID: UUID(),
            sourceConnectionId: connectionId
        )
        smbState.lastPlaybackPosition = 80
        smbState.lastPlayedAt = Date(timeIntervalSince1970: 4)
        smbState.syncUpdatedAt = Date(timeIntervalSince1970: 4)

        context.insert(placeholderState)
        context.insert(smbState)
        try context.save()

        try CloudSyncConflictResolver.mergePendingConflicts(in: context)
        try context.save()

        let leftover = try context.fetch(FetchDescriptor<CloudMediaState>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(leftover.count, 1)
        XCTAssertEqual(leftover.first?.mediaKey, CloudMediaStateStore.mediaKey(for: item))
        XCTAssertEqual(leftover.first?.lastPlaybackPosition, 80)
        XCTAssertEqual(item.lastPlaybackPosition, 80)
        XCTAssertFalse(leftover.first?.mediaKey.contains("smb://") == true)
    }
}
