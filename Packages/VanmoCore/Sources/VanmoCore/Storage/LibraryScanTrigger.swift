import Foundation

/// Decides whether a file-server connect should scan, and how deep.
public enum LibraryScanTrigger {
    public static func shouldScanRemoteFiles(
        type: ConnectionType,
        scanPath: String?,
        hasLocalMediaItems: Bool
    ) -> Bool {
        if !type.requiresManualDirectorySync {
            return true
        }
        if scanPath != nil {
            return true
        }
        return !hasLocalMediaItems
    }

    /// Local catalog already exists; only missing posters should be extracted.
    public static func shouldResumeCovers(
        hasLocalMediaItems: Bool,
        hasMissingPosters: Bool
    ) -> Bool {
        hasLocalMediaItems && hasMissingPosters
    }

    /// `nil` means connect only.
    public static func fileScanScope(
        type: ConnectionType,
        scanPath: String?,
        isPartialScan: Bool,
        hasLocalMediaItems: Bool
    ) -> ScanScope? {
        guard shouldScanRemoteFiles(
            type: type,
            scanPath: scanPath,
            hasLocalMediaItems: hasLocalMediaItems
        ) else {
            return nil
        }

        if isPartialScan, let scanPath {
            return .directory(path: scanPath)
        }

        if type.requiresManualDirectorySync, scanPath == nil, !hasLocalMediaItems {
            return .shallowRoot
        }

        return .connectionRoot
    }
}
