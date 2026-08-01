import Foundation
import SwiftData

public enum ScanJobPhase: String, Codable, Sendable {
    case idle
    case scanning
    case paused
    case probing
    case completed
    case cancelled
    case failed
}

@Model
public final class ScanJobRecord {
    public var id: UUID
    public var connectionId: UUID
    public var connectionName: String
    public var rootPath: String
    public var phaseRaw: String
    public var isPartialScan: Bool
    public var forceFullScan: Bool
    public var pendingDirectoriesData: Data?
    public var visitedDirectoriesData: Data?
    public var scannedDirectories: Int
    public var discoveredVideos: Int
    public var insertedCount: Int
    public var updatedCount: Int
    public var unchangedCount: Int
    public var prunedCount: Int
    public var currentDirectory: String?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        connectionId: UUID,
        connectionName: String,
        rootPath: String,
        isPartialScan: Bool,
        forceFullScan: Bool
    ) {
        self.id = UUID()
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.rootPath = rootPath
        self.phaseRaw = ScanJobPhase.scanning.rawValue
        self.isPartialScan = isPartialScan
        self.forceFullScan = forceFullScan
        self.scannedDirectories = 0
        self.discoveredVideos = 0
        self.insertedCount = 0
        self.updatedCount = 0
        self.unchangedCount = 0
        self.prunedCount = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var phase: ScanJobPhase {
        get { ScanJobPhase(rawValue: phaseRaw) ?? .idle }
        set { phaseRaw = newValue.rawValue }
    }

    public var pendingDirectories: [String] {
        get { Self.decodeStringArray(pendingDirectoriesData) }
        set { pendingDirectoriesData = Self.encodeStringArray(newValue) }
    }

    public var visitedDirectories: Set<String> {
        get { Set(Self.decodeStringArray(visitedDirectoriesData)) }
        set { visitedDirectoriesData = Self.encodeStringArray(Array(newValue)) }
    }

    private static func encodeStringArray(_ values: [String]) -> Data? {
        try? JSONEncoder().encode(values)
    }

    private static func decodeStringArray(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
