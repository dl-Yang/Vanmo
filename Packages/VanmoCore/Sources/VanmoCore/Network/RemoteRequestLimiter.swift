import Foundation

public actor RemoteRequestLimiter {
    public static let shared = RemoteRequestLimiter()

    private var lastRequestAt: [ConnectionType: Date] = [:]

    public func acquire(for type: ConnectionType) async {
        let minInterval = 1.0 / max(type.serviceCapabilities.requestsPerSecond, 0.5)
        if let last = lastRequestAt[type] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                let nanos = UInt64((minInterval - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
        lastRequestAt[type] = Date()
    }
}
