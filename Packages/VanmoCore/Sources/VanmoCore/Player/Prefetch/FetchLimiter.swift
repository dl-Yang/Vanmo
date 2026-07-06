import Foundation

/// 限制同时回源请求数量。
public actor FetchLimiter {
    public static let shared = FetchLimiter()

    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public func acquire() async {
        while active >= PrefetchConfig.maxConcurrentFetches {
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }
        active += 1
    }

    public func release() {
        active -= 1
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }
}
