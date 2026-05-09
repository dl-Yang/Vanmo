import Foundation

/// 通过 HTTP(S) Range 回源；剥离 URL 内嵌凭据并转为 Basic Auth 头。
final class RemoteFetcher {
    let cleanURL: URL
    private let extraHeaders: [String: String]
    private let session: URLSession

    init(originalURL: URL, session: URLSession = .shared) {
        let (clean, headers) = Self.stripCredentials(originalURL)
        self.cleanURL = clean
        self.extraHeaders = headers
        self.session = session
    }

    static func stripCredentials(_ url: URL) -> (URL, [String: String]) {
        guard let user = url.user, !user.isEmpty else {
            return (url, [:])
        }
        let password = url.password ?? ""
        let credential = "\(user):\(password)"
        let base64 = Data(credential.utf8).base64EncodedString()

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.user = nil
        components.password = nil
        let cleanURL = components.url ?? url

        return (cleanURL, ["Authorization": "Basic \(base64)"])
    }

    func apply(to request: inout URLRequest) {
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func totalFromResponse(_ http: HTTPURLResponse) -> Int64? {
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let total = Self.parseContentRangeTotal(cr) {
            return total
        }
        if let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
           let len = Int64(lenStr), len > 0 {
            return len
        }
        let expected = http.expectedContentLength
        if expected > 0 {
            return expected
        }
        return nil
    }

    /// 探测资源总长度（多种策略，兼容 Emby / WebDAV 等对 HEAD、小 Range 行为不一致的服务器）。
    func probeTotalSize() async throws -> Int64 {
        var head = URLRequest(url: cleanURL)
        head.httpMethod = "HEAD"
        apply(to: &head)

        do {
            let (_, response) = try await session.data(for: head)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
               let len = Int64(lenStr), len > 0 {
                VanmoLogger.prefetch.debug("[Prefetch] probe size via HEAD: \(len)")
                return len
            }
        } catch {
            VanmoLogger.prefetch.debug("[Prefetch] HEAD probe failed: \(error.localizedDescription)")
        }

        // Range bytes=0-0
        if let len = try await probeWithRange(first: 0, last: 0) {
            VanmoLogger.prefetch.debug("[Prefetch] probe size via 0-0: \(len)")
            return len
        }

        // 部分服务对 0-0 返回异常，再试稍大范围（仍限制体量，避免整文件下载）
        if let len = try await probeWithRange(first: 0, last: 1023) {
            VanmoLogger.prefetch.debug("[Prefetch] probe size via 0-1023: \(len)")
            return len
        }

        let oneMB: Int64 = 1024 * 1024
        if let len = try await probeWithRange(first: 0, last: oneMB - 1) {
            VanmoLogger.prefetch.debug("[Prefetch] probe size via 0-1MB: \(len)")
            return len
        }

        VanmoLogger.prefetch.error("[Prefetch] probeTotalSize failed for \(self.cleanURL.absoluteString)")
        throw PrefetchError.unknownSize
    }

    private func probeWithRange(first: Int64, last: Int64) async throws -> Int64? {
        var getR = URLRequest(url: cleanURL)
        getR.setValue("bytes=\(first)-\(last)", forHTTPHeaderField: "Range")
        getR.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        apply(to: &getR)

        let (_, response) = try await session.data(for: getR)
        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 416 {
            return nil
        }
        if !(200...299).contains(http.statusCode) {
            return nil
        }

        if let total = totalFromResponse(http) {
            return total
        }

        return nil
    }

    /// 一次性读取指定闭区间字节（含端点）。
    /// 之前用 `URLSession.AsyncBytes` 逐字节迭代，1MB 累积需要 200~1500ms（CPU 瓶颈）；
    /// 改用 `URLSession.data(for:)` 由系统 buffer 化拉取，等同于网络耗时本身。
    func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: cleanURL)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        apply(to: &request)
        return try await session.data(for: request)
    }

    static func parseContentRangeTotal(_ header: String) -> Int64? {
        let parts = header.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let tail = parts[1].trimmingCharacters(in: .whitespaces)
        if tail == "*" { return nil }
        return Int64(tail)
    }

    static func parseContentRangeSlice(_ header: String) -> ClosedRange<Int64>? {
        let main = header.split(separator: "/").first.map(String.init) ?? header
        guard let spaceIdx = main.firstIndex(of: " ") else { return nil }
        let afterBytes = main[main.index(after: spaceIdx)...].trimmingCharacters(in: .whitespaces)
        let dashIdx = afterBytes.firstIndex(of: "-") ?? afterBytes.endIndex
        let startStr = String(afterBytes[..<dashIdx])
        let endStr = String(afterBytes[afterBytes.index(after: dashIdx)...])
        guard let s = Int64(startStr), let e = Int64(endStr) else { return nil }
        return s...e
    }
}
