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
        hiddenIDs: Set<UUID> = [],
        defaults: UserDefaults = .standard
    ) -> [SavedConnection] {
        let processed = processedIDs(defaults: defaults)
        return connections.filter {
            $0.deletedAt == nil && !hiddenIDs.contains($0.id) && !processed.contains($0.id)
        }
    }

    /// True when this device cannot authenticate the synced connection yet.
    /// Passwords and OAuth tokens stay in the local Keychain and do not arrive via CloudKit.
    public static func needsLocalCredential(_ connection: SavedConnection) -> Bool {
        guard connection.type.requiresAuth else { return false }
        if connection.type.supportsOAuthLogin {
            return (try? OAuthCredentialStore.load(connectionId: connection.id)) == nil
        }
        let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        return isMissingLocalPassword(password)
    }

    /// Missing Keychain item needs a prompt. Empty or non-empty strings are confirmed.
    public static func isMissingLocalPassword(_ stored: String?) -> Bool {
        stored == nil
    }

    /// `nil` means leave the existing Keychain item unchanged.
    public static func resolvedPasswordToStore(
        incoming: String?,
        existing: String?,
        replaceExisting: Bool
    ) -> String? {
        if let incoming, !incoming.isEmpty { return incoming }
        if replaceExisting || existing == nil { return "" }
        return nil
    }

    /// Writes `conn_<id>` for password-auth types. An empty string means this device
    /// already confirmed that no password is required (public Emby, etc.).
    /// `replaceExisting` is true for first save; false for edit-so-blank-keeps-current.
    public static func persistLocalPassword(
        _ password: String?,
        for connection: SavedConnection,
        replaceExisting: Bool
    ) throws {
        guard connection.type.requiresAuth, !connection.type.supportsOAuthLogin else { return }
        let key = "conn_\(connection.id)"
        let existing = try KeychainManager.shared.loadString(for: key)
        guard let value = resolvedPasswordToStore(
            incoming: password,
            existing: existing,
            replaceExisting: replaceExisting
        ) else {
            return
        }
        try KeychainManager.shared.save(value, for: key)
    }
}
