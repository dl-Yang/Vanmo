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

    public func exclusive<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await work()
            await Self.waitForProtocolCloseDrain()
            release()
            return result
        } catch {
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

    public static func waitForProtocolCloseDrain() async {
        try? await Task.sleep(nanoseconds: protocolCloseDrainNanoseconds)
    }

    public func releaseAfterProtocolCloseDrain() async {
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
