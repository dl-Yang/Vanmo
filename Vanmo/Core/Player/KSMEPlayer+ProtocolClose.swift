import Foundation
import KSPlayer
import VanmoCore

extension KSMEPlayer {
    /// `shutdown()` 只是把 `avformat_close_input` 排进 MEPlayerItem 的串行队列，排在读线程之后，
    /// KSPlayer 不公开这个队列，只能反射拿到。队列清空才说明 libsmbclient 已经关闭；只读不可变的
    /// `operationQueue`，避免和 open/close 线程争用可变字段。字段改名时返回 nil，调用方退回固定 drain。
    func shutdownObservingProtocolClose() -> (@Sendable () -> Bool)? {
        shutdown()
        guard let item = Mirror(reflecting: self).children.first(where: { $0.label == "playerItem" })?.value,
              let queue = Mirror(reflecting: item).children.first(where: { $0.label == "operationQueue" })?.value as? OperationQueue
        else {
            VanmoLogger.player.error("[KSEngine] KSPlayer operation queue not found; falling back to fixed close drain")
            return nil
        }
        return { [weak queue] in (queue?.operationCount ?? 0) == 0 }
    }
}
