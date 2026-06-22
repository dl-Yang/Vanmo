import Foundation

struct iCloudSyncSnapshot: Codable, Equatable {
    var connectionIDs: [UUID]
    var favoriteItemIDs: [UUID]
    var playbackPositions: [UUID: TimeInterval]
    var folderBookmarkIDs: [UUID]
}

actor ICloudSyncService {
    static let shared = ICloudSyncService()

    private let store = NSUbiquitousKeyValueStore.default
    private let snapshotKey = "vanmo.sync.snapshot"

    func saveSnapshot(_ snapshot: iCloudSyncSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        store.set(data, forKey: snapshotKey)
        store.synchronize()
    }

    func loadSnapshot() throws -> iCloudSyncSnapshot? {
        guard let data = store.data(forKey: snapshotKey) else { return nil }
        return try JSONDecoder().decode(iCloudSyncSnapshot.self, from: data)
    }
}
