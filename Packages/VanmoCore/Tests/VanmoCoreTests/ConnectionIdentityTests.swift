import SwiftData
import XCTest
@testable import VanmoCore

@MainActor
final class ConnectionIdentityTests: XCTestCase {
    func testHostNormalizationIgnoresSchemePathAndTrailingDot() {
        let https = ConnectionIdentity.make(
            type: .emby,
            host: "https://Emby.Example.com./library",
            port: 8096,
            username: "Ada"
        )
        let bare = ConnectionIdentity.make(
            type: .emby,
            host: "emby.example.com",
            port: 8096,
            username: "ada"
        )
        XCTAssertEqual(https, bare)
    }

    func testEmptyAndNilUsernameShareIdentity() {
        let empty = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 445, username: "  ")
        let missing = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 445, username: nil)
        XCTAssertEqual(empty, missing)
    }

    func testZeroPortMatchesTypeDefault() {
        let implicit = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 0, username: nil)
        let explicit = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 445, username: nil)
        XCTAssertEqual(implicit, explicit)
    }

    func testSMBGuestSharesIdentityWithEmptyUsername() {
        let guest = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 445, username: "Guest")
        let missing = ConnectionIdentity.make(type: .smb, host: "nas.local", port: 445, username: nil)
        XCTAssertEqual(guest, missing)
    }

    func testDifferentUsernameIsDifferentIdentity() {
        let ada = ConnectionIdentity.make(type: .emby, host: "emby.local", port: 8096, username: "ada")
        let bob = ConnectionIdentity.make(type: .emby, host: "emby.local", port: 8096, username: "bob")
        XCTAssertNotEqual(ada, bob)
    }

    func testOAuthAndLocalFolderAreNotDeduplicated() {
        XCTAssertNil(ConnectionIdentity.make(type: .googleDrive, host: "oauth", port: 443, username: "user"))
        XCTAssertNil(ConnectionIdentity.make(type: .localFolder, host: "", port: 0, username: nil))
    }

    func testResolveForSaveReusesLiveRowAndLiftsTombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = SavedConnection(
            name: "Old",
            type: .emby,
            host: "emby.local",
            port: 8096,
            username: "ada"
        )
        context.insert(existing)
        ConnectionVisibility.upsertTombstone(for: existing.id, in: context)
        try context.save()

        let resolved = ConnectionIdentity.resolveForSave(
            name: "Public Emby",
            type: .emby,
            host: "https://emby.local",
            port: 8096,
            username: "Ada",
            path: nil,
            bookmarkData: nil,
            in: context
        )

        XCTAssertTrue(resolved.reused)
        XCTAssertEqual(resolved.connection.id, existing.id)
        XCTAssertEqual(resolved.connection.name, "Public Emby")
        XCTAssertTrue(ConnectionVisibility.hiddenConnectionIDs(in: context).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedConnection>()).count, 1)
    }

    func testHideDuplicatesKeepsEarlierAddedAtAndDeletesTheRest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = SavedConnection(name: "First", type: .emby, host: "emby.local", port: 8096, username: "ada")
        earlier.addedAt = Date(timeIntervalSince1970: 1)
        let later = SavedConnection(name: "Second", type: .emby, host: "https://emby.local", port: 8096, username: "Ada")
        later.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(earlier)
        context.insert(later)
        try context.save()

        let suiteName = "ConnectionIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let visible = ConnectionIdentity.hideDuplicates([later, earlier], in: context, defaults: defaults)

        XCTAssertEqual(visible.map(\.id), [earlier.id])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SavedConnection>()).map(\.id)), Set([earlier.id]))
        XCTAssertTrue(ConnectionVisibility.hiddenConnectionIDs(in: context).isEmpty)
        XCTAssertTrue(CloudSyncedConnectionActivation.processedIDs(defaults: defaults).contains(later.id))
        XCTAssertTrue(ConnectionIdentity.isDuplicate(later, of: [earlier, later]))
        XCTAssertFalse(ConnectionIdentity.isDuplicate(earlier, of: [earlier]))
    }

    func testCollapseRemapsLocalMediaAndDeletesLoserCloudRow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = SavedConnection(name: "Mac", type: .smb, host: "nas.local", port: 445, username: nil)
        earlier.addedAt = Date(timeIntervalSince1970: 1)
        let later = SavedConnection(name: "iOS", type: .smb, host: "nas.local", port: 0, username: "guest")
        later.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(earlier)
        context.insert(later)

        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        item.serverId = "/MacShare/movie.mkv"
        item.sourceConnectionId = later.id
        context.insert(item)

        let laterKey = "conn:\(later.id.uuidString.lowercased())|/macshare/movie.mkv"
        let state = CloudMediaState(
            mediaKey: laterKey,
            mediaItemID: item.id,
            sourceConnectionId: later.id
        )
        state.lastPlaybackPosition = 40
        context.insert(state)

        let bookmark = FolderBookmark(
            title: "Share",
            connectionId: later.id,
            connectionName: "iOS",
            path: "/MacShare"
        )
        context.insert(bookmark)
        try context.save()

        let removed = ConnectionIdentity.collapseDuplicates(in: context)
        try context.save()

        XCTAssertEqual(removed, [later.id])
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SavedConnection>()).map(\.id)), Set([earlier.id]))
        XCTAssertEqual(item.sourceConnectionId, earlier.id)
        XCTAssertEqual(state.sourceConnectionId, earlier.id)
        XCTAssertEqual(state.mediaKey, "conn:\(earlier.id.uuidString.lowercased())|/macshare/movie.mkv")
        XCTAssertEqual(bookmark.connectionId, earlier.id)
        XCTAssertTrue(ConnectionVisibility.hiddenConnectionIDs(in: context).isEmpty)
    }

    func testCollapseKeepsWinnerUserDeleteTombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = SavedConnection(name: "First", type: .smb, host: "nas.local", port: 445, username: nil)
        earlier.addedAt = Date(timeIntervalSince1970: 1)
        let later = SavedConnection(name: "Second", type: .smb, host: "nas.local", port: 445, username: nil)
        later.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(earlier)
        context.insert(later)
        ConnectionVisibility.upsertTombstone(for: earlier.id, in: context)
        try context.save()

        let visible = ConnectionIdentity.hideDuplicates([later], in: context)

        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SavedConnection>()).map(\.id)), Set([earlier.id]))
        XCTAssertEqual(ConnectionVisibility.hiddenConnectionIDs(in: context), Set([earlier.id]))
    }

    func testCollapseDoesNotLiftWhenBothAreTombstoned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let earlier = SavedConnection(name: "First", type: .smb, host: "nas.local", port: 445, username: nil)
        earlier.addedAt = Date(timeIntervalSince1970: 1)
        let later = SavedConnection(name: "Second", type: .smb, host: "nas.local", port: 445, username: nil)
        later.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(earlier)
        context.insert(later)
        ConnectionVisibility.upsertTombstone(for: earlier.id, in: context)
        ConnectionVisibility.upsertTombstone(for: later.id, in: context)
        try context.save()

        let visible = ConnectionIdentity.hideDuplicates([earlier, later], in: context)

        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SavedConnection>()).map(\.id)), Set([earlier.id]))
        XCTAssertEqual(ConnectionVisibility.hiddenConnectionIDs(in: context), Set([earlier.id]))
    }

    func testExistingMatchPrefersVisibleOverTombstoned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let hidden = SavedConnection(name: "Hidden", type: .webdav, host: "dav.local", port: 443, username: "ada")
        hidden.addedAt = Date(timeIntervalSince1970: 1)
        let visible = SavedConnection(name: "Visible", type: .webdav, host: "dav.local", port: 443, username: "ada")
        visible.addedAt = Date(timeIntervalSince1970: 2)
        context.insert(hidden)
        context.insert(visible)
        ConnectionVisibility.upsertTombstone(for: hidden.id, in: context)
        try context.save()

        let match = ConnectionIdentity.existingMatch(
            type: .webdav,
            host: "dav.local",
            port: 443,
            username: "ada",
            in: context
        )
        XCTAssertEqual(match?.id, visible.id)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
    }
}
