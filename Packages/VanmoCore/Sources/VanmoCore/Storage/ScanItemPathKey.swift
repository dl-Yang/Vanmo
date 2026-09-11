import Foundation

/// Normalizes remote file paths so the same SMB/file item is not inserted twice
/// when a later listing uses a different slash spelling.
public enum ScanItemPathKey {
    public static func normalize(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "\\", with: "/")
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        if result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        if !result.isEmpty, !result.hasPrefix("/") {
            result = "/" + result
        }
        return result
    }

    public static func make(serverId: String, connectionId: UUID?) -> String {
        let path = normalize(serverId)
        if let connectionId {
            return "\(connectionId.uuidString)::\(path)"
        }
        return path
    }
}
