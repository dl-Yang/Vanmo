import Foundation

enum SFTPPath {
    static func normalize(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "/" }
        if !trimmed.hasPrefix("/") { trimmed = "/\(trimmed)" }
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func join(_ directory: String, name: String) -> String {
        let dir = normalize(directory)
        if dir == "/" { return "/\(name)" }
        return "\(dir)/\(name)"
    }

    static func isListableName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
    }

    static func isDirectory(permissions: UInt32?, longname: String) -> Bool {
        if let permissions {
            return (permissions & 0o170000) == 0o040000
        }
        return longname.hasPrefix("d")
    }
}
