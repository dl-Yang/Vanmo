import Foundation
import SwiftData

/// Stable match for CloudStore connections that share a real host.
/// Local folders and OAuth drives are not merged: bookmarks are device-bound,
/// and OAuth rows often share the placeholder host `oauth`.
public struct ConnectionIdentity: Hashable, Sendable {
    public let type: String
    public let host: String
    public let port: Int
    public let username: String

    public static func canDeduplicate(_ type: ConnectionType) -> Bool {
        !type.isLocal && !type.supportsOAuthLogin
    }

    public static func make(
        type: ConnectionType,
        host: String,
        port: Int,
        username: String?
    ) -> ConnectionIdentity? {
        guard canDeduplicate(type) else { return nil }
        let normalizedHost = normalizeHost(host)
        guard !normalizedHost.isEmpty else { return nil }
        return ConnectionIdentity(
            type: type.rawValue,
            host: normalizedHost,
            port: normalizePort(port, type: type),
            username: normalizeUsername(username, type: type)
        )
    }

    public static func make(from connection: SavedConnection) -> ConnectionIdentity? {
        make(
            type: connection.type,
            host: connection.host,
            port: connection.port,
            username: connection.username
        )
    }

    public static func existingMatch(
        type: ConnectionType,
        host: String,
        port: Int,
        username: String?,
        in context: ModelContext
    ) -> SavedConnection? {
        guard let identity = make(type: type, host: host, port: port, username: username) else {
            return nil
        }
        let connections = (try? context.fetch(FetchDescriptor<SavedConnection>())) ?? []
        let hiddenIDs = ConnectionVisibility.hiddenConnectionIDs(in: context)
        return connections
            .filter { $0.deletedAt == nil && make(from: $0) == identity }
            .sorted { lhs, rhs in
                let lhsHidden = hiddenIDs.contains(lhs.id)
                let rhsHidden = hiddenIDs.contains(rhs.id)
                if lhsHidden != rhsHidden { return !lhsHidden && rhsHidden }
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    /// Inserts a new CloudStore row, or reuses the matching live/tombstoned row.
    public static func resolveForSave(
        name: String,
        type: ConnectionType,
        host: String,
        port: Int,
        username: String?,
        path: String?,
        bookmarkData: Data?,
        in context: ModelContext
    ) -> (connection: SavedConnection, reused: Bool) {
        if let existing = existingMatch(
            type: type,
            host: host,
            port: port,
            username: username,
            in: context
        ) {
            ConnectionVisibility.removeTombstone(for: existing.id, in: context)
            existing.name = name
            existing.host = host
            existing.port = port
            existing.username = username
            existing.path = path
            if let bookmarkData {
                existing.bookmarkData = bookmarkData
            }
            return (existing, true)
        }

        let connection = SavedConnection(
            name: name,
            type: type,
            host: host,
            port: port,
            username: username,
            path: path,
            bookmarkData: bookmarkData
        )
        context.insert(connection)
        return (connection, false)
    }

    /// Deletes extra CloudStore rows for the same identity so CloudKit keeps one
    /// `SavedConnection`. Local media, bookmarks, and cloud-media keys move to the winner.
    /// Winner is the earliest `addedAt`, then the smaller UUID — never this device's processed set.
    @MainActor
    @discardableResult
    public static func collapseDuplicates(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> Set<UUID> {
        let connections = ((try? context.fetch(FetchDescriptor<SavedConnection>())) ?? [])
            .filter { $0.deletedAt == nil }
        var winnerByIdentity: [ConnectionIdentity: SavedConnection] = [:]
        let ranked = connections.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var removedIDs = Set<UUID>()
        for connection in ranked {
            guard let identity = make(from: connection) else { continue }
            if let winner = winnerByIdentity[identity] {
                remapLocalReferences(from: connection.id, to: winner.id, in: context)
                ConnectionVisibility.removeTombstone(for: connection.id, in: context)
                CloudSyncedConnectionActivation.markProcessed([connection.id], defaults: defaults)
                context.delete(connection)
                removedIDs.insert(connection.id)
            } else {
                winnerByIdentity[identity] = connection
            }
        }
        return removedIDs
    }

    /// Collapses CloudStore duplicates, then returns visible survivors.
    /// A lifted winner that was not in `connections` is appended.
    @MainActor
    public static func hideDuplicates(
        _ connections: [SavedConnection],
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> [SavedConnection] {
        let removedIDs = collapseDuplicates(in: context, defaults: defaults)
        if !removedIDs.isEmpty {
            try? context.save()
        }
        let hiddenIDs = ConnectionVisibility.hiddenConnectionIDs(in: context)
        var result = connections.filter { !removedIDs.contains($0.id) && !hiddenIDs.contains($0.id) }
        let resultIDs = Set(result.map(\.id))
        let promoted = ((try? context.fetch(FetchDescriptor<SavedConnection>())) ?? [])
            .filter {
                $0.deletedAt == nil
                    && !hiddenIDs.contains($0.id)
                    && !resultIDs.contains($0.id)
            }
            .sorted { lhs, rhs in
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        result.append(contentsOf: promoted)
        return result
    }

    public static func isDuplicate(
        _ connection: SavedConnection,
        of others: [SavedConnection]
    ) -> Bool {
        guard let identity = make(from: connection) else { return false }
        return others.contains { other in
            other.id != connection.id && make(from: other) == identity
        }
    }

    static func normalizeHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let at = value.firstIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }
        if value.hasPrefix("[") {
            if let close = value.firstIndex(of: "]") {
                value = String(value[value.index(after: value.startIndex)..<close])
            }
        } else if let colon = value.lastIndex(of: ":"), value[colon...].dropFirst().allSatisfy(\.isNumber) {
            value = String(value[..<colon])
        }
        while value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }

    static func normalizePort(_ port: Int, type: ConnectionType) -> Int {
        port == 0 ? type.defaultPort : port
    }

    static func normalizeUsername(_ raw: String?, type: ConnectionType = .smb) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == .smb, value == "guest" {
            return ""
        }
        return value
    }

    @MainActor
    static func remapLocalReferences(from loserID: UUID, to winnerID: UUID, in context: ModelContext) {
        let items = ((try? context.fetch(FetchDescriptor<MediaItem>())) ?? [])
            .filter { $0.sourceConnectionId == loserID }
        for item in items {
            item.sourceConnectionId = winnerID
        }

        let states = ((try? context.fetch(FetchDescriptor<CloudMediaState>())) ?? [])
            .filter { $0.sourceConnectionId == loserID }
        let oldPrefix = "conn:\(loserID.uuidString.lowercased())|"
        let newPrefix = "conn:\(winnerID.uuidString.lowercased())|"
        for state in states {
            state.sourceConnectionId = winnerID
            if state.mediaKey.lowercased().hasPrefix(oldPrefix) {
                state.mediaKey = newPrefix + String(state.mediaKey.dropFirst(oldPrefix.count))
            }
        }

        let bookmarks = ((try? context.fetch(FetchDescriptor<FolderBookmark>())) ?? [])
            .filter { $0.connectionId == loserID }
        for bookmark in bookmarks {
            bookmark.connectionId = winnerID
        }

        let jobs = ((try? context.fetch(FetchDescriptor<ScanJobRecord>())) ?? [])
            .filter { $0.connectionId == loserID }
        for job in jobs {
            job.connectionId = winnerID
        }

        if let password = try? KeychainManager.shared.loadString(for: "conn_\(loserID)"),
           (try? KeychainManager.shared.loadString(for: "conn_\(winnerID)")) == nil {
            try? KeychainManager.shared.save(password, for: "conn_\(winnerID)")
        }
    }
}
