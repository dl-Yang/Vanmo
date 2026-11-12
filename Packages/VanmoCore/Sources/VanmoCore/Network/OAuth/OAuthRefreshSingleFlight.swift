import Foundation

/// 同一连接上并发 refresh 的合并器。
///
/// Box 的 refresh token 是一次性的：用旧 token 并发刷新时，后到的请求会收到
/// `invalid_grant`，把一次正常续期变成登录失效。这里把同一 connectionId 的并发刷新
/// 合并成一个任务，所有等待者共享同一份新凭据，并把旋转后的 refresh token 持久化一次。
@MainActor
final class OAuthRefreshSingleFlight {
    private var tasks: [UUID: Task<OAuthCredential, Error>] = [:]
    private var waiterCount = 0

    /// 每个连接同时只允许一个刷新任务；后来的调用等待同一个结果。
    func credential(
        for connectionId: UUID,
        operation: @escaping @MainActor () async throws -> OAuthCredential
    ) async throws -> OAuthCredential {
        if let existing = tasks[connectionId] {
            waiterCount += 1
            defer { waiterCount -= 1 }
            return try await existing.value
        }

        // 槽位在任务内部清空，任务完成的那一刻之后发起的调用一定会重新刷新，
        // 不会命中刚结束（尤其是刚失败）的旧任务。
        let task = Task { @MainActor in
            defer { self.tasks[connectionId] = nil }
            return try await operation()
        }
        tasks[connectionId] = task
        return try await task.value
    }

    /// 测试与连接清理用：当前是否有在途刷新。
    var hasInFlightRefresh: Bool {
        !tasks.isEmpty
    }

    /// 测试观察用：正在等待同一个在途刷新的调用数。
    var pendingWaiterCount: Int {
        waiterCount
    }
}