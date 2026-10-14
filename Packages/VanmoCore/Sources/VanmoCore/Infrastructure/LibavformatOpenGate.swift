import Foundation

/// libsmbclient / libavformat protocol contexts (smb, ftp, sftp) are process-global
/// and abort in `talloc` if two `avformat_open_input` calls overlap.
///
/// Actor isolation alone is not enough: `await` inside the work closure
/// suspends the actor. Keep an explicit busy token until `work` returns.
public actor LibavformatOpenGate {
    public static let shared = LibavformatOpenGate()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func exclusive<T: Sendable>(
        awaitingClose close: LibavformatProtocolClose? = nil,
        _ work: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire()
        do {
            let result = try await work()
            await Self.waitForProtocolClose(close?.take())
            await Self.waitForProtocolCloseDrain()
            release()
            return result
        } catch {
            await Self.waitForProtocolClose(close?.take())
            await Self.waitForProtocolCloseDrain()
            release()
            throw error
        }
    }

    public static func needsExclusiveOpen(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "smb", "ftp", "sftp", "ftps":
            return true
        default:
            return false
        }
    }

    /// KSPlayer `shutdown()` returns before `avformat_close_input` finishes on
    /// `KSPlayer_MEPlayerItem_close`. Hold the gate through that window so the
    /// next `avformat_open_input` cannot overlap libsmbclient teardown.
    public static let protocolCloseDrainNanoseconds: UInt64 = 400_000_000

    /// Upper bound for a close blocked behind a stalled network read. A stalled read and
    /// each teardown request (close, tree disconnect, logoff) can each hit libsmbclient's
    /// 20 s timeout; reopening mid-teardown crashes, so SMB opens queue instead.
    public static let protocolCloseTimeoutNanoseconds: UInt64 = 120_000_000_000

    static let protocolClosePollNanoseconds: UInt64 = 50_000_000

    /// The drain runs in its own task so a cancelled caller cannot skip it.
    public static func waitForProtocolCloseDrain() async {
        await Task {
            try? await Task.sleep(nanoseconds: protocolCloseDrainNanoseconds)
        }.value
    }

    /// Returns `false` when the close did not finish within `timeoutNanoseconds`.
    @discardableResult
    public static func waitForProtocolClose(
        _ isClosed: (@Sendable () -> Bool)?,
        timeoutNanoseconds: UInt64 = protocolCloseTimeoutNanoseconds
    ) async -> Bool {
        guard let isClosed else { return true }
        let poll = protocolClosePollNanoseconds
        let closed = await Task {
            var waited: UInt64 = 0
            while !isClosed() {
                guard waited < timeoutNanoseconds else { return false }
                try? await Task.sleep(nanoseconds: poll)
                waited += poll
            }
#if DEBUG
            if waited > 0 {
                VanmoLogger.player.info("[Debug][Player] event=protocolCloseWait waitedMs=\(waited / 1_000_000, privacy: .public)")
            }
#endif
            return true
        }.value
        if !closed {
            VanmoLogger.player.error("[LibavformatGate] protocol close still running after \(timeoutNanoseconds / 1_000_000, privacy: .public)ms; releasing gate")
        }
        return closed
    }

    public func releaseAfterProtocolCloseDrain() async {
        await Self.waitForProtocolCloseDrain()
        release()
    }

    public func releaseAfterProtocolClose(
        _ isClosed: (@Sendable () -> Bool)?,
        timeoutNanoseconds: UInt64 = protocolCloseTimeoutNanoseconds
    ) async {
        await Self.waitForProtocolClose(isClosed, timeoutNanoseconds: timeoutNanoseconds)
        await Self.waitForProtocolCloseDrain()
        release()
    }

    public func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func release() {
        if waiters.isEmpty {
            isBusy = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}
