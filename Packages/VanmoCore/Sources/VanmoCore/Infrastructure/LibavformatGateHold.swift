import Foundation

/// 记录播放器当前持有的 `LibavformatOpenGate` 份额。每次 acquire 发一个持有号，
/// 被取代的 load 只能凭自己的持有号释放，不会放掉更新 load 已拿到的闸门。
public final class LibavformatGateHold: @unchecked Sendable {
    private let lock = NSLock()
    private var current: UInt64?
    private var next: UInt64 = 0

    public init() {}

    public func mark() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        next &+= 1
        current = next
        return next
    }

    /// `hold == nil` 释放当前持有者；传入持有号时只在仍是这一份时释放。
    public func consume(_ hold: UInt64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current, hold == nil || hold == current else { return false }
        self.current = nil
        return true
    }
}
