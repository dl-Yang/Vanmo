import XCTest
@testable import VanmoCore

final class CloudSyncedConnectionActivationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CloudSyncedConnectionActivationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUnprocessedConnectionsIgnoresAlreadyMarkedIDs() {
        let first = SavedConnection(name: "One", type: .emby, host: "one.local")
        let second = SavedConnection(name: "Two", type: .smb, host: "two.local")
        CloudSyncedConnectionActivation.markProcessed([first.id], defaults: defaults)

        let newcomers = CloudSyncedConnectionActivation.unprocessedConnections(
            from: [first, second],
            defaults: defaults
        )

        XCTAssertEqual(newcomers.map(\.id), [second.id])
    }

    func testUnprocessedConnectionsSkipsSoftDeleted() {
        let live = SavedConnection(name: "Live", type: .emby, host: "live.local")
        let deleted = SavedConnection(name: "Gone", type: .emby, host: "gone.local")
        deleted.deletedAt = Date()

        let newcomers = CloudSyncedConnectionActivation.unprocessedConnections(
            from: [live, deleted],
            defaults: defaults
        )

        XCTAssertEqual(newcomers.map(\.id), [live.id])
    }

    func testRemoveProcessedMakesConnectionNewAgain() {
        let connection = SavedConnection(name: "Emby", type: .emby, host: "emby.local")
        CloudSyncedConnectionActivation.markProcessed([connection.id], defaults: defaults)
        CloudSyncedConnectionActivation.removeProcessed(connection.id, defaults: defaults)

        let newcomers = CloudSyncedConnectionActivation.unprocessedConnections(
            from: [connection],
            defaults: defaults
        )

        XCTAssertEqual(newcomers.map(\.id), [connection.id])
    }

    func testLocalFolderDoesNotNeedPassword() {
        let folder = SavedConnection(name: "Movies", type: .localFolder, host: "")
        XCTAssertFalse(CloudSyncedConnectionActivation.needsLocalCredential(folder))
    }

    func testEmbyWithoutKeychainNeedsPassword() {
        let emby = SavedConnection(name: "Reno", type: .emby, host: "emby.local")
        XCTAssertTrue(CloudSyncedConnectionActivation.needsLocalCredential(emby))
    }
}
