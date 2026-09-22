import Foundation

/// 限制同时回源请求数量。
public actor FetchLimiter {
    public static let shared = FetchLimiter()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []

    public init(limit: Int = PrefetchConfig.maxConcurrentFetches) {
        self.limit = max(1, limit)
    }

    public func acquire() async throws {
        while active >= limit {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters.append(Waiter(id: waiterID, continuation: continuation))
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelWaiter(id: waiterID)
                }
            }
            try Task.checkCancellation()
        }
        active += 1
    }

    public func release() {
        guard active > 0 else { return }
        active -= 1
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.continuation.resume() }
    }

    var waitingCount: Int {
        waiters.count
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

actor CancellableReadGate {
    private enum Lifecycle {
        case open
        case closing
        case closed
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var lifecycle = Lifecycle.open
    private var isHeld = false
    private var waiters: [Waiter] = []
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async throws {
        while true {
            try Task.checkCancellation()
            guard lifecycle == .open else { throw CancellationError() }
            if !isHeld {
                isHeld = true
                return
            }

            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled || lifecycle != .open {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters.append(Waiter(id: waiterID, continuation: continuation))
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelWaiter(id: waiterID)
                }
            }
        }
    }

    func release() {
        guard isHeld else { return }
        isHeld = false
        if lifecycle == .open {
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.continuation.resume() }
            return
        }
        finishCloseIfPossible()
    }

    func beginClose() {
        guard lifecycle == .open else { return }
        lifecycle = .closing
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach {
            $0.continuation.resume(throwing: CancellationError())
        }
        finishCloseIfPossible()
    }

    func waitUntilClosed() async {
        guard lifecycle != .closed else { return }
        await withCheckedContinuation { continuation in
            closeWaiters.append(continuation)
        }
    }

    var waitingCount: Int {
        waiters.count
    }

    var isClosed: Bool {
        lifecycle == .closed
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func finishCloseIfPossible() {
        guard lifecycle == .closing, !isHeld else { return }
        lifecycle = .closed
        let currentCloseWaiters = closeWaiters
        closeWaiters.removeAll()
        currentCloseWaiters.forEach { $0.resume() }
    }
}
