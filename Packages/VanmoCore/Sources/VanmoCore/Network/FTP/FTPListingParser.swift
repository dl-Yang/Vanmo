import Foundation

/// FTP listing and PASV helpers. Used by `FTPClient` and unit tests.
enum FTPListingParser {
    struct PassiveEndpoint: Equatable {
        let host: String
        let port: Int
    }

    static func parsePASV(_ message: String, controlHost: String) -> PassiveEndpoint? {
        guard let match = message.range(of: #"(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let parts = message[match].split(separator: ",").compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        let advertised = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = parts[4] * 256 + parts[5]
        guard port > 0, port <= 65_535 else { return nil }
        let host = rewrittenDataHost(advertised, controlHost: controlHost)
        return PassiveEndpoint(host: host, port: port)
    }

    static func parseEPSV(_ message: String, controlHost: String) -> PassiveEndpoint? {
        guard let match = message.range(of: #"\|(\d+)\|"#, options: .regularExpression) else {
            return nil
        }
        let digits = message[match].filter(\.isNumber)
        guard let port = Int(digits), port > 0, port <= 65_535 else { return nil }
        return PassiveEndpoint(host: controlHost, port: port)
    }

    static func rewrittenDataHost(_ advertised: String, controlHost: String) -> String {
        if advertised == "127.0.0.1" || advertised == "0.0.0.0" || advertised.hasPrefix("127.") {
            return controlHost
        }
        return advertised
    }

    static func parseListing(_ text: String, directoryPath: String) -> [RemoteFile] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.contains(where: { $0.contains("type=") && $0.contains(";") }) {
            return lines.compactMap { parseMLSDLine($0, directoryPath: directoryPath) }
        }
        return lines.compactMap { parseLISTLine($0, directoryPath: directoryPath) }
    }

    static func joinPath(_ directory: String, name: String) -> String {
        let dir = normalizePath(directory)
        if dir == "/" { return "/\(name)" }
        return "\(dir)/\(name)"
    }

    static func normalizePath(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "/" }
        if !trimmed.hasPrefix("/") { trimmed = "/\(trimmed)" }
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    // MARK: - Private

    private static func parseMLSDLine(_ line: String, directoryPath: String) -> RemoteFile? {
        guard let separator = line.firstIndex(of: " ") else { return nil }
        let facts = String(line[..<separator])
        let name = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        guard isListableName(name) else { return nil }

        var typeFact = ""
        var size: Int64 = 0
        var modified: Date?
        for fact in facts.split(separator: ";") where !fact.isEmpty {
            let pieces = fact.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].lowercased()
            let value = String(pieces[1])
            switch key {
            case "type":
                typeFact = value.lowercased()
            case "size":
                size = Int64(value) ?? 0
            case "modify":
                modified = parseMLSDDate(value)
            default:
                break
            }
        }

        if typeFact == "cdir" || typeFact == "pdir" { return nil }
        let isDirectory = typeFact == "dir"
        return makeRemoteFile(name: name, directoryPath: directoryPath, size: size, isDirectory: isDirectory, modified: modified)
    }

    private static func parseLISTLine(_ line: String, directoryPath: String) -> RemoteFile? {
        if line.hasPrefix("total ") { return nil }
        if let unix = parseUnixLIST(line, directoryPath: directoryPath) {
            return unix
        }
        return parseWindowsLIST(line, directoryPath: directoryPath)
    }

    private static func parseUnixLIST(_ line: String, directoryPath: String) -> RemoteFile? {
        guard let first = line.first, "dl-".contains(first) else { return nil }
        let isDirectory = first == "d" || first == "l"
        let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 9 else { return nil }
        let size = Int64(parts[4]) ?? 0
        let name = parts[8...].joined(separator: " ")
        guard isListableName(name) else { return nil }
        return makeRemoteFile(name: name, directoryPath: directoryPath, size: size, isDirectory: isDirectory, modified: nil)
    }

    private static func parseWindowsLIST(_ line: String, directoryPath: String) -> RemoteFile? {
        // 01-22-26  10:15AM       <DIR>          Movies
        // 01-22-26  10:15PM              1234567 video.mp4
        let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 4 else { return nil }
        let isDirectory = parts.contains(where: { $0.caseInsensitiveCompare("<DIR>") == .orderedSame })
        let size: Int64
        let name: String
        if isDirectory {
            guard let dirIndex = parts.firstIndex(where: { $0.caseInsensitiveCompare("<DIR>") == .orderedSame }),
                  dirIndex + 1 < parts.count else { return nil }
            size = 0
            name = parts[(dirIndex + 1)...].joined(separator: " ")
        } else {
            guard parts.count >= 4, let parsedSize = Int64(parts[2]) else { return nil }
            size = parsedSize
            name = parts[3...].joined(separator: " ")
        }
        guard isListableName(name) else { return nil }
        return makeRemoteFile(name: name, directoryPath: directoryPath, size: size, isDirectory: isDirectory, modified: nil)
    }

    private static func makeRemoteFile(
        name: String,
        directoryPath: String,
        size: Int64,
        isDirectory: Bool,
        modified: Date?
    ) -> RemoteFile {
        RemoteFile(
            name: name,
            path: joinPath(directoryPath, name: name),
            size: size,
            isDirectory: isDirectory,
            modifiedDate: modified,
            type: isDirectory ? .directory : RemoteFileType.from(filename: name)
        )
    }

    private static func isListableName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
    }

    private static func parseMLSDDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.count >= 14 ? "yyyyMMddHHmmss" : "yyyyMMddHHmm"
        return formatter.date(from: String(value.prefix(14)))
    }
}
