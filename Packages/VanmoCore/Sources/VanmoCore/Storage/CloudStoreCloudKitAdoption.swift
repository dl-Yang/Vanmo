#if canImport(CloudKit)
import CloudKit
#endif
import CoreData
import Foundation
import SQLite3
import SwiftData

enum CloudStoreCloudKitAdoption {
    static let generationKey = "cloudSync.cloudStoreCloudKitGeneration"
    static let currentGeneration = 3
    static let legacyStoreName = "CloudStore"

    static var adoptedStoreName: String {
        storeName(forGeneration: currentGeneration)
    }

    static var previousStoreNames: [String] {
        (0..<currentGeneration).map(storeName(forGeneration:))
    }

    static var sourceStoreNameForAdoption: String {
        storeName(forGeneration: UserDefaults.standard.integer(forKey: generationKey))
    }

    static var activeStoreName: String {
        storeName(
            forGeneration: min(
                max(UserDefaults.standard.integer(forKey: generationKey), 0),
                currentGeneration
            )
        )
    }

    static func storeName(forGeneration generation: Int) -> String {
        generation <= 0 ? legacyStoreName : "CloudStore-ck\(generation)"
    }

    static var needsAdoption: Bool {
        ModelContainerFactory.shouldAttachPrivateCloudKit
            && UserDefaults.standard.integer(forKey: generationKey) < currentGeneration
    }

    static func markAdopted() {
        UserDefaults.standard.set(currentGeneration, forKey: generationKey)
    }

    enum SnapshotError: Error {
        case storeMissing(String)
    }

    static func restoreGeneration(_ value: Any?) {
        if let value {
            UserDefaults.standard.set(value, forKey: generationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: generationKey)
        }
    }

    #if DEBUG
    static func startMirroringLogs() {
        UserDefaults.standard.set(2, forKey: "com.apple.CoreData.CloudKitDebug")
        UserDefaults.standard.set(1, forKey: "com.apple.CoreData.Logging.stderr")
        _ = mirroringObserver
        logAccountAndZones()
    }

    private static var didProbeExportFailure = false

    private static let mirroringObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSPersistentCloudKitContainer.eventChangedNotification,
        object: nil,
        queue: .main
    ) { notification in
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return }
        print("[Debug][CloudKit] mirroring type=\(event.type.rawValue) ended=\(event.endDate != nil) \(debugErrorSummary(event.error))")
        if event.type.rawValue == 2, event.endDate != nil, isPartialCloudKitFailure(event.error) {
            probePrivateDatabaseAfterExportFailure()
        }
    }

    private static func logAccountAndZones() {
        #if canImport(CloudKit)
        let container = CKContainer(identifier: ModelContainerFactory.cloudKitContainerIdentifier)
        container.accountStatus { status, error in
            print("[Debug][CloudKit] accountStatus=\(status.rawValue) \(debugErrorSummary(error))")
        }
        container.privateCloudDatabase.fetchAllRecordZones { zones, error in
            let names = (zones ?? []).map(\.zoneID.zoneName).sorted().joined(separator: ",")
            print("[Debug][CloudKit] zones=\(names) count=\(zones?.count ?? 0) \(debugErrorSummary(error))")
        }
        #endif
    }

    private static func debugErrorSummary(_ error: Error?) -> String {
        guard let error else { return "error=none" }
        return summarize(error as NSError, depth: 0)
    }

    private static func summarize(_ nsError: NSError, depth: Int) -> String {
        var parts = [
            "error=\(nsError.localizedDescription)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
        ]
        if let reason = nsError.localizedFailureReason {
            parts.append("reason=\(reason)")
        }
        let infoKeys = nsError.userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
        if !infoKeys.isEmpty {
            parts.append("keys=\(infoKeys)")
        }
        for (key, value) in nsError.userInfo.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
            let keyText = String(describing: key)
            if keyText == NSUnderlyingErrorKey
                || keyText == NSDetailedErrorsKey
                || keyText == NSLocalizedDescriptionKey
                || keyText.contains("PartialError") {
                continue
            }
            if value is NSError { continue }
            if value is Data { continue }
            if let text = value as? String, !text.isEmpty {
                parts.append("\(keyText)=\(text)")
            } else if let number = value as? NSNumber {
                parts.append("\(keyText)=\(number)")
            }
        }
        let debug = nsError.debugDescription.replacingOccurrences(of: "\n", with: " ")
        if !debug.isEmpty {
            parts.append("debug=\(debug)")
        }
        #if canImport(CloudKit)
        if let ckError = nsError as? CKError {
            parts.append("ck=\(ckError.code.rawValue)")
            if let partial = ckError.partialErrorsByItemID, !partial.isEmpty {
                parts.append("ckPartial=\(partial.count)")
            }
        }
        #endif
        guard depth < 2 else { return parts.joined(separator: " ") }
        let nested = nestedErrors(in: nsError).prefix(4).map { summarize($0, depth: depth + 1) }
        if !nested.isEmpty {
            parts.append("nested=[\(nested.joined(separator: " | "))]")
        }
        return parts.joined(separator: " ")
    }

    private static func nestedErrors(in nsError: NSError) -> [NSError] {
        var errors: [NSError] = []
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            errors.append(underlying)
        }
        if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
            errors.append(contentsOf: detailed)
        }
        if let encountered = nsError.userInfo["encounteredErrors"] as? [Any] {
            errors.append(contentsOf: encountered.compactMap { $0 as? NSError })
        }
        #if canImport(CloudKit)
        if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
            errors.append(contentsOf: partial.allValues.compactMap { $0 as? NSError })
        }
        #endif
        for (key, value) in nsError.userInfo {
            let keyText = String(describing: key)
            if keyText == NSUnderlyingErrorKey
                || keyText == NSDetailedErrorsKey
                || keyText.contains("PartialError") {
                continue
            }
            if let nested = value as? NSError {
                errors.append(nested)
            }
        }
        return errors
    }

    private static func isPartialCloudKitFailure(_ error: Error?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        #if canImport(CloudKit)
        return nsError.domain == CKErrorDomain && nsError.code == CKError.partialFailure.rawValue
        #else
        return nsError.domain == "CKErrorDomain" && nsError.code == 2
        #endif
    }

    private static func probePrivateDatabaseAfterExportFailure() {
        guard !didProbeExportFailure else { return }
        didProbeExportFailure = true
        #if canImport(CloudKit)
        let container = CKContainer(identifier: ModelContainerFactory.cloudKitContainerIdentifier)
        let record = CKRecord(recordType: "VanmoCloudKitProbe")
        record["probe"] = "ok"
        container.privateCloudDatabase.save(record) { _, error in
            print("[Debug][CloudKit] exportProbe \(debugErrorSummary(error))")
        }
        #endif
    }
    #endif
}

enum CloudStoreSQLiteTypeOverlay {
    static func rawTypesByConnectionID(storeURL: URL) -> [UUID: String] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return [:]
        }
        defer { sqlite3_close(db) }

        let columns = tableColumns(db, table: "ZSAVEDCONNECTION")
        guard columns.contains("ZID") else { return [:] }
        let typeColumn: String
        if columns.contains("ZTYPE") {
            typeColumn = "ZTYPE"
        } else if columns.contains("ZTYPERAWVALUE") {
            typeColumn = "ZTYPERAWVALUE"
        } else {
            return [:]
        }

        let sql = "SELECT ZID, \(typeColumn) FROM ZSAVEDCONNECTION"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var result: [UUID: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = uuid(from: statement, column: 0),
                  let raw = sqlite3_column_text(statement, 1) else { continue }
            let value = String(cString: raw)
            guard !value.isEmpty else { continue }
            result[id] = value
        }
        return result
    }

    private static func tableColumns(_ db: OpaquePointer, table: String) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private static func uuid(from statement: OpaquePointer, column: Int32) -> UUID? {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB else { return nil }
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length == 16, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        let data = Data(bytes: bytes, count: length)
        return data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return UUID(uuid: base.load(as: uuid_t.self))
        }
    }
}

struct CloudStoreSnapshot {
    var connections: [SavedConnectionDraft] = []
    var bookmarks: [FolderBookmarkDraft] = []
    var mediaStates: [CloudMediaStateDraft] = []

    var isEmpty: Bool {
        connections.isEmpty && bookmarks.isEmpty && mediaStates.isEmpty
    }
}

struct SavedConnectionDraft {
    init(_ connection: SavedConnection) {
        id = connection.id
        name = connection.name
        type = connection.type
        host = connection.host
        port = connection.port
        username = connection.username
        path = connection.path
        bookmarkData = connection.bookmarkData
        isFavorite = connection.isFavorite
        lastConnectedAt = connection.lastConnectedAt
        lastSyncedAt = connection.lastSyncedAt
        addedAt = connection.addedAt
        updatedAt = connection.updatedAt
        deletedAt = connection.deletedAt
        lastModifiedDeviceId = connection.lastModifiedDeviceId
    }

    var id: UUID
    var name: String
    var type: ConnectionType
    var host: String
    var port: Int
    var username: String?
    var path: String?
    var bookmarkData: Data?
    var isFavorite: Bool
    var lastConnectedAt: Date?
    var lastSyncedAt: Date?
    var addedAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceId: String?
}

struct FolderBookmarkDraft {
    init(_ bookmark: FolderBookmark) {
        id = bookmark.id
        title = bookmark.title
        connectionId = bookmark.connectionId
        connectionName = bookmark.connectionName
        path = bookmark.path
        addedAt = bookmark.addedAt
        updatedAt = bookmark.updatedAt
        deletedAt = bookmark.deletedAt
        lastModifiedDeviceId = bookmark.lastModifiedDeviceId
    }

    var id: UUID
    var title: String
    var connectionId: UUID
    var connectionName: String
    var path: String
    var addedAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceId: String?
}

struct CloudMediaStateDraft {
    init(_ state: CloudMediaState) {
        mediaKey = state.mediaKey
        mediaItemID = state.mediaItemID
        sourceConnectionId = state.sourceConnectionId
        lastPlaybackPosition = state.lastPlaybackPosition
        lastPlayedAt = state.lastPlayedAt
        isWatched = state.isWatched
        isFavorite = state.isFavorite
        progressUpdatedAt = state.progressUpdatedAt
        favoriteUpdatedAt = state.favoriteUpdatedAt
        syncUpdatedAt = state.syncUpdatedAt
        lastModifiedDeviceId = state.lastModifiedDeviceId
        deletedAt = state.deletedAt
    }

    var mediaKey: String
    var mediaItemID: UUID?
    var sourceConnectionId: UUID?
    var lastPlaybackPosition: TimeInterval
    var lastPlayedAt: Date?
    var isWatched: Bool
    var isFavorite: Bool
    var progressUpdatedAt: Date?
    var favoriteUpdatedAt: Date?
    var syncUpdatedAt: Date?
    var lastModifiedDeviceId: String?
    var deletedAt: Date?
}

extension SavedConnection {
    convenience init(draft: SavedConnectionDraft) {
        self.init(
            name: draft.name,
            type: draft.type,
            host: draft.host,
            port: draft.port,
            username: draft.username,
            path: draft.path,
            bookmarkData: draft.bookmarkData
        )
        id = draft.id
        isFavorite = draft.isFavorite
        lastConnectedAt = draft.lastConnectedAt
        lastSyncedAt = draft.lastSyncedAt
        addedAt = draft.addedAt
        updatedAt = draft.updatedAt
        deletedAt = draft.deletedAt
        lastModifiedDeviceId = draft.lastModifiedDeviceId
    }
}

extension FolderBookmark {
    convenience init(draft: FolderBookmarkDraft) {
        self.init(
            title: draft.title,
            connectionId: draft.connectionId,
            connectionName: draft.connectionName,
            path: draft.path
        )
        id = draft.id
        addedAt = draft.addedAt
        updatedAt = draft.updatedAt
        deletedAt = draft.deletedAt
        lastModifiedDeviceId = draft.lastModifiedDeviceId
    }
}

extension CloudMediaState {
    convenience init(draft: CloudMediaStateDraft) {
        self.init(
            mediaKey: draft.mediaKey,
            mediaItemID: draft.mediaItemID,
            sourceConnectionId: draft.sourceConnectionId
        )
        lastPlaybackPosition = draft.lastPlaybackPosition
        lastPlayedAt = draft.lastPlayedAt
        isWatched = draft.isWatched
        isFavorite = draft.isFavorite
        progressUpdatedAt = draft.progressUpdatedAt
        favoriteUpdatedAt = draft.favoriteUpdatedAt
        syncUpdatedAt = draft.syncUpdatedAt
        lastModifiedDeviceId = draft.lastModifiedDeviceId
        deletedAt = draft.deletedAt
    }
}
