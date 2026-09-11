import Foundation

/// Temporary local-console probes for first-connect shallow scan, clustering, and thumbnails.
/// Search Xcode Console / Console.app for `[Debug][LibraryScan]` or `[Debug][Thumbnail]`.
public enum LibraryScanDebugLog {
    public static func scan(_ message: String) {
        #if DEBUG
        VanmoLogger.library.debug("[Debug][LibraryScan] \(message, privacy: .public)")
        #endif
    }

    public static func thumbnail(_ message: String) {
        #if DEBUG
        VanmoLogger.library.debug("[Debug][Thumbnail] \(message, privacy: .public)")
        #endif
    }

    public static func leaf(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    public static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

public extension ScanScope {
    var debugName: String {
        switch self {
        case .connectionRoot:
            return "connectionRoot"
        case .shallowRoot:
            return "shallowRoot"
        case .directory:
            return "directory"
        case .bookmarks:
            return "bookmarks"
        }
    }
}
