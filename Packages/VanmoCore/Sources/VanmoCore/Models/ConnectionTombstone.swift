import Foundation
import SwiftData

/// Per-device CloudStore marker that hides a connection on one device only.
/// CloudKit mirrors the row; other devices ignore tombstones that are not theirs.
@Model
public final class ConnectionTombstone {
    public var id: UUID = UUID()
    public var connectionId: UUID = UUID()
    public var deviceId: String = ""
    public var deletedAt: Date = Date()

    public init(connectionId: UUID, deviceId: String = CloudSyncDevice.id) {
        self.id = UUID()
        self.connectionId = connectionId
        self.deviceId = deviceId
        self.deletedAt = Date()
    }
}
