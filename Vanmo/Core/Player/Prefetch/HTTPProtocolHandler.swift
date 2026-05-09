import Foundation

/// HTTP Range 解析结果。
enum HTTPRangeSpec: Equatable {
    case closed(ClosedRange<Int64>)
    /// `bytes=start-`
    case from(start: Int64)
    /// `bytes=-suffix`
    case lastN(Int64)
}

enum HTTPProtocolHandler {

    struct ParsedHTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
    }

    static func parseRequest(_ headerData: Data) -> ParsedHTTPRequest? {
        guard let raw = String(data: headerData, encoding: .utf8) else { return nil }
        // 兼容仅 `\n` 换行的客户端
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let first = lines.first, !first.isEmpty else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var hdr: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            hdr[key.lowercased()] = val
        }
        return ParsedHTTPRequest(method: method, path: path, headers: hdr)
    }

    /// 解析 `Range:` 头（仅 `bytes=`）。
    static func parseRangeHeader(_ value: String) -> HTTPRangeSpec? {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = String(t.dropFirst(6))

        if spec.hasPrefix("-") {
            let n = String(spec.dropFirst())
            guard let v = Int64(n), v > 0 else { return nil }
            return .lastN(v)
        }

        let dashParts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard dashParts.count == 2, let start = Int64(dashParts[0]) else { return nil }
        if dashParts[1].isEmpty {
            return .from(start: start)
        }
        guard let end = Int64(dashParts[1]) else { return nil }
        return .closed(start...end)
    }

    static func streamToken(from path: String) -> String? {
        guard path.hasPrefix(PrefetchConfig.streamPathPrefix) else { return nil }
        let rest = String(path.dropFirst(PrefetchConfig.streamPathPrefix.count))
        let token = rest.split(separator: "?").first.map(String.init) ?? rest
        return token.isEmpty ? nil : token
    }

    /// 必须用 `\r\n` 严格拼接，避免 Swift `"""` 缩进或杂空格导致 FFmpeg 解析失败。
    static func build206(
        contentLength: Int,
        rangeStart: Int64,
        rangeEnd: Int64,
        totalSize: Int64?
    ) -> Data {
        let totalStr: String
        if let t = totalSize, t >= 0 {
            totalStr = "\(t)"
        } else {
            totalStr = "*"
        }
        let header =
            "HTTP/1.1 206 Partial Content\r\n" +
            "Content-Type: application/octet-stream\r\n" +
            "Accept-Ranges: bytes\r\n" +
            "Content-Length: \(contentLength)\r\n" +
            "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalStr)\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        return Data(header.utf8)
    }

    static func build404() -> Data {
        let header =
            "HTTP/1.1 404 Not Found\r\n" +
            "Connection: close\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
        return Data(header.utf8)
    }

    static func build400() -> Data {
        let header =
            "HTTP/1.1 400 Bad Request\r\n" +
            "Connection: close\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
        return Data(header.utf8)
    }
}
