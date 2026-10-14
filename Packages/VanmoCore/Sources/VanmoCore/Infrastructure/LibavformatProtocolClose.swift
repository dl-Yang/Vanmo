import Foundation

/// 记录被 shutdown 的播放器何时真正关闭协议上下文。
/// KSPlayer 的 `avformat_close_input` 排在读线程之后执行，弱网下读线程可能卡在
/// `smbc_read` 远超固定 drain，闸门需要等到这里返回 true 才能放行下一次打开。
public final class LibavformatProtocolClose: @unchecked Sendable {
    private let lock = NSLock()
    private var isClosed: (@Sendable () -> Bool)?

    public init() {}

    public func track(_ isClosed: @escaping @Sendable () -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.isClosed = isClosed
    }

    public func take() -> (@Sendable () -> Bool)? {
        lock.lock()
        defer { lock.unlock() }
        let isClosed = self.isClosed
        self.isClosed = nil
        return isClosed
    }
}
