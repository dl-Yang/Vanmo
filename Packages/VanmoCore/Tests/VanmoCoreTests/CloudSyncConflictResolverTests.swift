import SwiftData
import XCTest
@testable import VanmoCore

@MainActor
final class CloudSyncConflictResolverTests: XCTestCase {
    func testProgressKeepsNewerLastPlayedAt() {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        item.lastPlaybackPosition = 400
        item.lastPlayedAt = Date(timeIntervalSince1970: 200)

        CloudSyncConflictResolver.mergeProgress(
            into: item,
            position: 100,
            playedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(item.lastPlaybackPosition, 400)

        CloudSyncConflictResolver.mergeProgress(
            into: item,
            position: 800,
            playedAt: Date(timeIntervalSince1970: 300)
        )
        XCTAssertEqual(item.lastPlaybackPosition, 800)
        XCTAssertEqual(item.lastPlayedAt, Date(timeIntervalSince1970: 300))
    }

    func testProgressTieBreakPrefersFartherPosition() {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        item.lastPlaybackPosition = 100
        item.lastPlayedAt = Date(timeIntervalSince1970: 50)

        CloudSyncConflictResolver.mergeProgress(
            into: item,
            position: 250,
            playedAt: Date(timeIntervalSince1970: 51)
        )
        XCTAssertEqual(item.lastPlaybackPosition, 250)
    }

    func testFavoriteLastWriteWins() {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        CloudSyncConflictResolver.mergeFavorite(
            into: item,
            isFavorite: true,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        CloudSyncConflictResolver.mergeFavorite(
            into: item,
            isFavorite: false,
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.favoriteUpdatedAt, Date(timeIntervalSince1970: 10))

        CloudSyncConflictResolver.mergeFavorite(
            into: item,
            isFavorite: false,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.favoriteUpdatedAt, Date(timeIntervalSince1970: 20))
    }

    func testWatchedIsStickyTrue() {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        CloudSyncConflictResolver.mergeWatched(
            into: item,
            isWatched: true,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        CloudSyncConflictResolver.mergeWatched(
            into: item,
            isWatched: false,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertTrue(item.isWatched)
    }

    func testMergeConnectionKeepsNewerUpdatedAt() {
        let local = SavedConnection(name: "Old", type: .webdav, host: "dav.local")
        local.updatedAt = Date(timeIntervalSince1970: 1)
        let remote = SavedConnection(name: "New", type: .webdav, host: "dav.local")
        remote.updatedAt = Date(timeIntervalSince1970: 2)
        remote.path = "/media"

        CloudSyncConflictResolver.mergeConnection(local, with: remote)
        XCTAssertEqual(local.name, "New")
        XCTAssertEqual(local.path, "/media")
        XCTAssertEqual(local.updatedAt, Date(timeIntervalSince1970: 2))
    }

    func testDedupeBookmarksKeepsLaterUpdatedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let connectionId = UUID()
        let older = FolderBookmark(
            title: "Old",
            connectionId: connectionId,
            connectionName: "NAS",
            path: "/Movies"
        )
        older.updatedAt = Date(timeIntervalSince1970: 1)
        let newer = FolderBookmark(
            title: "New",
            connectionId: connectionId,
            connectionName: "NAS",
            path: "/Movies"
        )
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        context.insert(older)
        context.insert(newer)
        try context.save()

        try CloudSyncConflictResolver.mergePendingConflicts(in: context)
        try context.save()

        let leftover = try context.fetch(FetchDescriptor<FolderBookmark>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(leftover.count, 1)
        XCTAssertEqual(leftover.first?.title, "New")
    }

    func testMergeCollapsesDuplicateSMBConnectionsThenDedupeStates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = SavedConnection(name: "Mac", type: .smb, host: "nas.local", port: 445, username: nil)
        earlier.addedAt = Date(timeIntervalSince1970: 1)
        let later = SavedConnection(name: "iOS", type: .smb, host: "nas.local", port: 445, username: nil)
        later.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(earlier)
        context.insert(later)

        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        item.serverId = "/MacShare/movie.mkv"
        item.sourceConnectionId = later.id
        item.lastPlaybackPosition = 10
        item.lastPlayedAt = Date(timeIntervalSince1970: 1)
        context.insert(item)

        let winnerState = CloudMediaState(
            mediaKey: "conn:\(earlier.id.uuidString.lowercased())|/macshare/movie.mkv",
            mediaItemID: item.id,
            sourceConnectionId: earlier.id
        )
        winnerState.lastPlaybackPosition = 20
        winnerState.lastPlayedAt = Date(timeIntervalSince1970: 3)
        winnerState.syncUpdatedAt = Date(timeIntervalSince1970: 3)

        let loserState = CloudMediaState(
            mediaKey: "conn:\(later.id.uuidString.lowercased())|/macshare/movie.mkv",
            mediaItemID: item.id,
            sourceConnectionId: later.id
        )
        loserState.lastPlaybackPosition = 40
        loserState.lastPlayedAt = Date(timeIntervalSince1970: 5)
        loserState.syncUpdatedAt = Date(timeIntervalSince1970: 5)

        context.insert(winnerState)
        context.insert(loserState)
        try context.save()

        try CloudSyncConflictResolver.mergePendingConflicts(in: context)
        try context.save()

        let connections = try context.fetch(FetchDescriptor<SavedConnection>())
        XCTAssertEqual(Set(connections.map(\.id)), Set([earlier.id]))
        let states = try context.fetch(FetchDescriptor<CloudMediaState>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.sourceConnectionId, earlier.id)
        XCTAssertEqual(states.first?.lastPlaybackPosition, 40)
        XCTAssertEqual(item.sourceConnectionId, earlier.id)
        XCTAssertEqual(item.lastPlaybackPosition, 40)
    }

    func testDedupeCloudMediaStatesMergesFieldsThenAppliesOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/conflict.mkv"))
        item.lastPlaybackPosition = 10
        item.lastPlayedAt = Date(timeIntervalSince1970: 1)
        context.insert(item)

        let older = CloudMediaState(mediaKey: CloudMediaStateStore.mediaKey(for: item), mediaItemID: item.id, sourceConnectionId: nil)
        older.lastPlaybackPosition = 40
        older.lastPlayedAt = Date(timeIntervalSince1970: 5)
        older.isFavorite = false
        older.favoriteUpdatedAt = Date(timeIntervalSince1970: 2)
        older.syncUpdatedAt = Date(timeIntervalSince1970: 5)

        let newer = CloudMediaState(mediaKey: CloudMediaStateStore.mediaKey(for: item), mediaItemID: item.id, sourceConnectionId: nil)
        newer.lastPlaybackPosition = 20
        newer.lastPlayedAt = Date(timeIntervalSince1970: 3)
        newer.isFavorite = true
        newer.favoriteUpdatedAt = Date(timeIntervalSince1970: 8)
        newer.syncUpdatedAt = Date(timeIntervalSince1970: 8)

        context.insert(older)
        context.insert(newer)
        try context.save()

        try CloudSyncConflictResolver.mergePendingConflicts(in: context)
        try context.save()

        let states = try context.fetch(FetchDescriptor<CloudMediaState>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.lastPlaybackPosition, 40)
        XCTAssertEqual(states.first?.isFavorite, true)
        XCTAssertEqual(item.lastPlaybackPosition, 40)
        XCTAssertTrue(item.isFavorite)
    }

    func testMediaServerFlagsSkipCloudProgressAndFavorite() {
        let item = MediaItem(title: "Emby", fileURL: URL(fileURLWithPath: "/tmp/emby.mkv"))
        item.isProgressCloudSynced = false
        item.isFavoriteCloudSynced = false
        item.lastPlaybackPosition = 15
        item.isFavorite = false

        CloudSyncConflictResolver.mergeProgress(
            into: item,
            position: 90,
            playedAt: Date(timeIntervalSince1970: 99)
        )
        CloudSyncConflictResolver.mergeFavorite(
            into: item,
            isFavorite: true,
            updatedAt: Date(timeIntervalSince1970: 99)
        )
        XCTAssertEqual(item.lastPlaybackPosition, 15)
        XCTAssertFalse(item.isFavorite)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
    }
}
