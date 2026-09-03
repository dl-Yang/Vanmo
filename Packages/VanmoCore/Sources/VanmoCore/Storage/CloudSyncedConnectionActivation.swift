import Foundation

/// Per-device record of CloudStore connections that already ran the local
/// connect/scan path. CloudKit does not sync Keychain passwords; this set only
/// lives in UserDefaults on the current device.
public enum CloudSyncedConnectionActivation {
    public static let processedIDsKey = "cloudSync.processedConnectionIDs"

    public static func processedIDs(defaults: UserDefaults = .standard) -> Set<UUID> {
        let raw = defaults.stringArray(forKey: processedIDsKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    public static func markProcessed<S: Sequence>(_ ids: S, defaults: UserDefaults = .standard) where S.Element == UUID {
        var current = processedIDs(defaults: defaults)
        current.formUnion(ids)
        defaults.set(current.map(\.uuidString).sorted(), forKey: processedIDsKey)
    }

    public static func removeProcessed(_ id: UUID, defaults: UserDefaults = .standard) {
        var current = processedIDs(defaults: defaults)
        current.remove(id)
        defaults.set(current.map(\.uuidString).sorted(), forKey: processedIDsKey)
    }

    public static func unprocessedConnections(
        from connections: [SavedConnection],
        defaults: UserDefaults = .standard
    ) -> [SavedConnection] {
        let processed = processedIDs(defaults: defaults)
        return connections.filter { $0.deletedAt == nil && !processed.contains($0.id) }
    }

    /// True when this device cannot authenticate the synced connection yet.
    /// Passwords and OAuth tokens stay in the local Keychain and do not arrive via CloudKit.
    public static func needsLocalCredential(_ connection: SavedConnection) -> Bool {
        guard connection.type.requiresAuth else { return false }
        if connection.type.supportsOAuthLogin {
            return (try? OAuthCredentialStore.load(connectionId: connection.id)) == nil
        }
        let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        return password?.isEmpty != false
    }
}
