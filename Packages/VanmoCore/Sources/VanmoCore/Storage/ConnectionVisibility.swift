import Foundation
import SwiftData

/// Filters CloudStore connections for the current device.
/// A row stays hidden when it has a global `deletedAt` or a tombstone for this device.
public enum ConnectionVisibility {
    public static func hiddenConnectionIDs(
        in context: ModelContext,
        deviceId: String = CloudSyncDevice.id
    ) -> Set<UUID> {
        let tombstones = (try? context.fetch(FetchDescriptor<ConnectionTombstone>())) ?? []
        return Set(
            tombstones.compactMap { tombstone in
                tombstone.deviceId == deviceId ? tombstone.connectionId : nil
            }
        )
    }

    public static func visibleConnectionIDs(in context: ModelContext) -> Set<UUID> {
        let hiddenIDs = hiddenConnectionIDs(in: context)
        let connections = (try? context.fetch(FetchDescriptor<SavedConnection>())) ?? []
        return Set(connections.filter { isVisible($0, hiddenIDs: hiddenIDs) }.map(\.id))
    }

    public static func isVisible(_ connection: SavedConnection, hiddenIDs: Set<UUID>) -> Bool {
        connection.deletedAt == nil && !hiddenIDs.contains(connection.id)
    }

    public static func isVisible(_ connection: SavedConnection, in context: ModelContext) -> Bool {
        isVisible(connection, hiddenIDs: hiddenConnectionIDs(in: context))
    }

    public static func visibleConnections(
        from connections: [SavedConnection],
        hiddenIDs: Set<UUID>
    ) -> [SavedConnection] {
        connections.filter { isVisible($0, hiddenIDs: hiddenIDs) }
    }

    @discardableResult
    public static func upsertTombstone(
        for connectionId: UUID,
        in context: ModelContext,
        deviceId: String = CloudSyncDevice.id
    ) -> ConnectionTombstone {
        let existing = (try? context.fetch(FetchDescriptor<ConnectionTombstone>())) ?? []
        if let match = existing.first(where: { $0.connectionId == connectionId && $0.deviceId == deviceId }) {
            match.deletedAt = Date()
            return match
        }
        let tombstone = ConnectionTombstone(connectionId: connectionId, deviceId: deviceId)
        context.insert(tombstone)
        return tombstone
    }

    public static func removeTombstone(
        for connectionId: UUID,
        in context: ModelContext,
        deviceId: String = CloudSyncDevice.id
    ) {
        let tombstones = (try? context.fetch(FetchDescriptor<ConnectionTombstone>())) ?? []
        for tombstone in tombstones where tombstone.connectionId == connectionId && tombstone.deviceId == deviceId {
            context.delete(tombstone)
        }
    }
}
