import Foundation

/// 通过 HTTP(S) Range 回源；剥离 URL 内嵌凭据并转为 Basic Auth 头。
public final class RemoteFetcher {
    public let cleanURL: URL
    private let extraHeaders: [String: String]
    /// 用于 OAuth Bearer token 网盘（如 Google Drive）：token 可能在长播放会话中过期，
    /// 每次发请求前调用以取到当前有效值，而不是像 `extraHeaders` 那样在初始化时固定。
    private let headerProvider: (() async -> [String: String])?
    private let session: URLSession
    private let rangeSession: URLSession
    private let rangeSessionDelegate: RangeSessionDelegate
    private let ownsSession: Bool

    /// 默认创建带重定向委托的专用 session：当 AList/网盘把 WebDAV 直链 302 到对象存储
    /// 签名直链（跨 host）时剥离 Authorization，避免把 Basic Auth 凭据转发到第三方 CDN，
    /// 也避免多余的 Authorization 头与签名 URL 自带鉴权冲突导致 403。
    public init(originalURL: URL, session: URLSession? = nil, headerProvider: (() async -> [String: String])? = nil) {
        let (clean, headers) = Self.stripCredentials(originalURL)
        self.cleanURL = clean
        self.extraHeaders = headers
        self.headerProvider = headerProvider
        let rangeDelegate = RangeSessionDelegate()
        self.rangeSessionDelegate = rangeDelegate
        if let session {
            self.session = session
            self.rangeSession = URLSession(
                configuration: .default,
                delegate: rangeDelegate,
                delegateQueue: nil
            )
            self.ownsSession = false
        } else {
            let createdSession = URLSession(
                configuration: .default,
                delegate: rangeDelegate,
                delegateQueue: nil
            )
            self.session = createdSession
            self.rangeSession = createdSession
            self.ownsSession = true
        }
    }

    init(
        originalURL: URL,
        sessionConfiguration: URLSessionConfiguration,
        headerProvider: (() async -> [String: String])? = nil
    ) {
        let (clean, headers) = Self.stripCredentials(originalURL)
        self.cleanURL = clean
        self.extraHeaders = headers
        self.headerProvider = headerProvider
        let rangeDelegate = RangeSessionDelegate()
        self.rangeSessionDelegate = rangeDelegate
        let createdSession = URLSession(
            configuration: sessionConfiguration,
            delegate: rangeDelegate,
            delegateQueue: nil
        )
        self.session = createdSession
        self.rangeSession = createdSession
        self.ownsSession = true
    }

    deinit {
        if ownsSession {
            session.finishTasksAndInvalidate()
        }
        if rangeSession !== session {
            rangeSession.finishTasksAndInvalidate()
        }
    }

    public static func stripCredentials(_ url: URL) -> (URL, [String: String]) {
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

    public func apply(to request: inout URLRequest) async {
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let headerProvider {
            for (key, value) in await headerProvider() {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
    }

    /// 探测资源总长度（多种策略，兼容 Emby / WebDAV 等对 HEAD、小 Range 行为不一致的服务器）。
    public func probeTotalSize() async throws -> Int64 {
        var head = URLRequest(url: cleanURL)
        head.httpMethod = "HEAD"
        await apply(to: &head)

        do {
            let response = try await rangeSessionDelegate.head(
                in: rangeSession,
                request: head
            )
            if let lenStr = response.value(forHTTPHeaderField: "Content-Length"),
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
        await apply(to: &getR)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await rangeSessionDelegate.data(
                in: rangeSession,
                request: getR,
                requestedRange: first...last,
                allowsEOFClamp: true
            )
        } catch PrefetchError.badRequest {
            return nil
        }
        return try Self.validateProbeRangeResponse(
            data: data,
            response: response,
            requestedRange: first...last
        )
    }

    /// 读取指定闭区间字节（含端点）。Delegate 在响应头阶段验证 Range，
    /// 并把正文严格限制在请求长度内，避免忽略 Range 的上游把整文件载入内存。
    public func data(forInclusiveRange range: ClosedRange<Int64>) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: cleanURL)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        await apply(to: &request)
        return try await rangeSessionDelegate.data(
            in: rangeSession,
            request: request,
            requestedRange: range,
            allowsEOFClamp: false
        )
    }

    /// 下载指定 Range 到系统临时文件。下载管理器使用此接口兼容忽略 Range、直接返回
    /// 整文件的服务器，避免把大型视频一次性载入内存。
    public func downloadFile(forInclusiveRange range: ClosedRange<Int64>) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: cleanURL)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        await apply(to: &request)
        return try await session.download(for: request)
    }

    func close() {
        rangeSession.invalidateAndCancel()
        if ownsSession, rangeSession !== session {
            session.invalidateAndCancel()
        }
    }

    /// 验证普通内存 Range 请求。预取不兼容忽略 Range 并返回整文件的上游，
    /// 否则一个 256 KiB chunk 请求可能把整部视频保留在内存缓存中。
    @discardableResult
    public static func validateRangeResponse(
        data: Data,
        response: URLResponse,
        requestedRange: ClosedRange<Int64>
    ) throws -> Int64? {
        let validation = try validateRangeHeaders(
            response: response,
            requestedRange: requestedRange,
            allowsEOFClamp: false
        )
        guard data.count == validation.expectedCount else {
            throw PrefetchError.badResponse
        }
        return validation.total
    }

    /// Size probes may request past end-of-file. A compliant server clamps the
    /// returned upper bound while preserving the requested lower bound.
    @discardableResult
    public static func validateProbeRangeResponse(
        data: Data,
        response: URLResponse,
        requestedRange: ClosedRange<Int64>
    ) throws -> Int64? {
        guard let http = response as? HTTPURLResponse else {
            throw PrefetchError.badResponse
        }
        if http.statusCode == 416 {
            return nil
        }
        let validation = try validateRangeHeaders(
            response: response,
            requestedRange: requestedRange,
            allowsEOFClamp: true
        )
        guard data.count == validation.expectedCount else {
            throw PrefetchError.badResponse
        }
        return validation.total
    }

    public static func parseContentRangeTotal(_ header: String) -> Int64? {
        let parts = header.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let tail = parts[1].trimmingCharacters(in: .whitespaces)
        if tail == "*" { return nil }
        return Int64(tail)
    }

    public static func parseContentRangeSlice(_ header: String) -> ClosedRange<Int64>? {
        let main = header.split(separator: "/").first.map(String.init) ?? header
        guard let spaceIdx = main.firstIndex(of: " ") else { return nil }
        let afterBytes = main[main.index(after: spaceIdx)...].trimmingCharacters(in: .whitespaces)
        let dashIdx = afterBytes.firstIndex(of: "-") ?? afterBytes.endIndex
        let startStr = String(afterBytes[..<dashIdx])
        let endStr = String(afterBytes[afterBytes.index(after: dashIdx)...])
        guard let s = Int64(startStr), let e = Int64(endStr) else { return nil }
        return s...e
    }

    private static func parseStrictContentRange(
        _ header: String
    ) -> (range: ClosedRange<Int64>, total: Int64?)? {
        let unitAndValue = header.split(
            maxSplits: 1,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard unitAndValue.count == 2,
              unitAndValue[0].lowercased() == "bytes" else {
            return nil
        }

        let rangeAndTotal = unitAndValue[1].split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard rangeAndTotal.count == 2 else { return nil }

        let bounds = rangeAndTotal[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard bounds.count == 2,
              let lower = Int64(bounds[0]),
              let upper = Int64(bounds[1]),
              lower >= 0,
              lower <= upper else {
            return nil
        }

        let totalText = rangeAndTotal[1].trimmingCharacters(in: .whitespaces)
        if totalText == "*" {
            return (lower...upper, nil)
        }
        guard let total = Int64(totalText), total > upper else {
            return nil
        }
        return (lower...upper, total)
    }

    private struct RangeHeaderValidation {
        let expectedCount: Int
        let total: Int64?
    }

    private static func validateRangeHeaders(
        response: URLResponse,
        requestedRange: ClosedRange<Int64>,
        allowsEOFClamp: Bool
    ) throws -> RangeHeaderValidation {
        guard let http = response as? HTTPURLResponse else {
            throw PrefetchError.badResponse
        }
        if http.statusCode == 416 {
            throw PrefetchError.badRequest
        }
        guard http.statusCode == 206 else {
            if (200...299).contains(http.statusCode) {
                throw PrefetchError.badResponse
            }
            throw PrefetchError.upstream(http.statusCode)
        }
        guard requestedRange.lowerBound >= 0,
              let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
              let parsed = parseStrictContentRange(contentRange) else {
            throw PrefetchError.badResponse
        }

        if allowsEOFClamp {
            guard parsed.range.lowerBound == requestedRange.lowerBound,
                  parsed.range.upperBound <= requestedRange.upperBound,
                  parsed.range.upperBound == requestedRange.upperBound
                    || parsed.total == parsed.range.upperBound + 1 else {
                throw PrefetchError.badResponse
            }
        } else {
            guard parsed.range == requestedRange else {
                throw PrefetchError.badResponse
            }
        }

        let count = parsed.range.upperBound - parsed.range.lowerBound + 1
        let requestedCount = requestedRange.upperBound - requestedRange.lowerBound + 1
        guard count > 0,
              count <= requestedCount,
              count <= Int64(Int.max) else {
            throw PrefetchError.badResponse
        }
        let expectedCount = Int(count)
        if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           Int64(contentLength) != count {
            throw PrefetchError.badResponse
        }
        return RangeHeaderValidation(expectedCount: expectedCount, total: parsed.total)
    }

    private final class RangeSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private enum RequestKind {
            case head
            case range(ClosedRange<Int64>, allowsEOFClamp: Bool)
        }

        private struct PendingRequest {
            let kind: RequestKind
            let continuation: CheckedContinuation<(Data, URLResponse), Error>
            var response: URLResponse?
            var expectedCount: Int?
            var data = Data()
        }

        private final class RequestHandle: @unchecked Sendable {
            private let lock = NSLock()
            private var task: URLSessionDataTask?
            private var isCancelled = false

            func install(_ task: URLSessionDataTask) {
                lock.lock()
                self.task = task
                let shouldCancel = isCancelled
                lock.unlock()
                if shouldCancel {
                    task.cancel()
                }
            }

            func cancel() {
                lock.lock()
                isCancelled = true
                let task = task
                lock.unlock()
                task?.cancel()
            }
        }

        private let lock = NSLock()
        private var pending: [Int: PendingRequest] = [:]

        func data(
            in session: URLSession,
            request: URLRequest,
            requestedRange: ClosedRange<Int64>,
            allowsEOFClamp: Bool
        ) async throws -> (Data, URLResponse) {
            try await perform(
                in: session,
                request: request,
                kind: .range(requestedRange, allowsEOFClamp: allowsEOFClamp)
            )
        }

        func head(
            in session: URLSession,
            request: URLRequest
        ) async throws -> HTTPURLResponse {
            let (_, response) = try await perform(
                in: session,
                request: request,
                kind: .head
            )
            guard let http = response as? HTTPURLResponse else {
                throw PrefetchError.badResponse
            }
            return http
        }

        private func perform(
            in session: URLSession,
            request: URLRequest,
            kind: RequestKind
        ) async throws -> (Data, URLResponse) {
            let handle = RequestHandle()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let task = session.dataTask(with: request)
                    let request = PendingRequest(
                        kind: kind,
                        continuation: continuation
                    )
                    lock.lock()
                    pending[task.taskIdentifier] = request
                    lock.unlock()
                    handle.install(task)
                    task.resume()
                }
            } onCancel: {
                handle.cancel()
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.lock()
            guard var request = pending[dataTask.taskIdentifier] else {
                lock.unlock()
                completionHandler(.cancel)
                return
            }
            do {
                let expectedCount: Int
                switch request.kind {
                case .head:
                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        throw PrefetchError.badResponse
                    }
                    expectedCount = 0
                case .range(let requestedRange, let allowsEOFClamp):
                    let validation = try RemoteFetcher.validateRangeHeaders(
                        response: response,
                        requestedRange: requestedRange,
                        allowsEOFClamp: allowsEOFClamp
                    )
                    expectedCount = validation.expectedCount
                }
                request.response = response
                request.expectedCount = expectedCount
                request.data.reserveCapacity(expectedCount)
                pending[dataTask.taskIdentifier] = request
                lock.unlock()
                completionHandler(.allow)
            } catch {
                pending[dataTask.taskIdentifier] = nil
                lock.unlock()
                completionHandler(.cancel)
                request.continuation.resume(throwing: error)
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive data: Data
        ) {
            lock.lock()
            guard var request = pending[dataTask.taskIdentifier],
                  let expectedCount = request.expectedCount,
                  request.response != nil else {
                lock.unlock()
                dataTask.cancel()
                return
            }
            guard data.count <= expectedCount - request.data.count else {
                pending[dataTask.taskIdentifier] = nil
                lock.unlock()
                dataTask.cancel()
                request.continuation.resume(throwing: PrefetchError.badResponse)
                return
            }
            request.data.append(data)
            pending[dataTask.taskIdentifier] = request
            lock.unlock()
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            lock.lock()
            guard let request = pending.removeValue(forKey: task.taskIdentifier) else {
                lock.unlock()
                return
            }
            lock.unlock()

            if let error {
                if (error as NSError).code == NSURLErrorCancelled {
                    request.continuation.resume(throwing: CancellationError())
                } else {
                    request.continuation.resume(throwing: error)
                }
                return
            }
            guard let response = request.response,
                  let expectedCount = request.expectedCount,
                  request.data.count == expectedCount else {
                request.continuation.resume(throwing: PrefetchError.badResponse)
                return
            }
            request.continuation.resume(returning: (request.data, response))
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            let originalHost = task.originalRequest?.url?.host
            let newHost = request.url?.host
            guard originalHost != newHost else {
                completionHandler(request)
                return
            }
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            VanmoLogger.prefetch.info("[Prefetch] cross-host redirect, stripped Authorization: \(originalHost ?? "?") -> \(newHost ?? "?")")
            completionHandler(stripped)
        }
    }
}
