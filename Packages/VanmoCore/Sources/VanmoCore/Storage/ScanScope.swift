import Foundation

public enum ScanScope: Sendable, Equatable {
    case connectionRoot
    case directory(path: String)
    case bookmarks(paths: [String])

    public var isPartialScan: Bool {
        switch self {
        case .connectionRoot:
            return false
        case .directory, .bookmarks:
            return true
        }
    }

    public var rootPaths: [String] {
        switch self {
        case .connectionRoot:
            return []
        case .directory(let path):
            return [path]
        case .bookmarks(let paths):
            return Array(Set(paths)).sorted()
        }
    }
}

public extension RemoteScanOptions {
    static func forScope(_ scope: ScanScope, forceFullScan: Bool, connectionType: ConnectionType? = nil) -> RemoteScanOptions {
        switch scope {
        case .connectionRoot:
            return forConnectionRoot(forceFullScan: forceFullScan, connectionType: connectionType)
        case .directory, .bookmarks:
            return forPartialDirectory(forceFullScan: forceFullScan, connectionType: connectionType)
        }
    }
}
