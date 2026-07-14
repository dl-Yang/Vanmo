import Foundation

/// Emby/Jellyfin Playback Progress 的 EventName。
public enum EmbyPlaybackProgressEvent: Sendable {
    case timeUpdate
    case pause
    case unpause
    /// Seek 完成后立即上报；服务端 EventName 仍为 TimeUpdate。
    case seek

    var apiValue: String {
        switch self {
        case .timeUpdate, .seek: return "TimeUpdate"
        case .pause: return "Pause"
        case .unpause: return "Unpause"
        }
    }

    var bypassesThrottle: Bool {
        switch self {
        case .timeUpdate: return false
        case .pause, .unpause, .seek: return true
        }
    }
}

/// 单次播放会话的 Emby/Jellyfin Check-in 上报器（节流 + PlaySessionId）。
@MainActor
public final class EmbyPlaybackSession {
    private enum Phase {
        case idle
        case starting
        case started
        case stopped
    }

    public let isEnabled: Bool

    private let itemId: String?
    private let connection: MediaServerConnectionSnapshot?
    private let playSessionId: String
    private let progressInterval: TimeInterval

    private var phase: Phase = .idle
    private var lastProgressAt: Date?
    private var inFlightProgressCount = 0
    /// 播放会话期间复用已认证 service，避免每 10s 重新 AuthenticateByName。
    private var service: EmbyService?

    public init(
        item: MediaItem,
        connection: MediaServerConnectionSnapshot?,
        progressInterval: TimeInterval = 10
    ) {
        self.itemId = item.serverId
        self.connection = connection
        self.playSessionId = UUID().uuidString
        self.progressInterval = progressInterval

        if item.isLiveStream {
            self.isEnabled = false
        } else if let connection {
            self.isEnabled = item.serverId != nil
                && (connection.type == .emby || connection.type == .jellyfin)
        } else {
            // 无明确连接时不猜测来源，避免把 Plex 等 serverId 打到 Emby。
            self.isEnabled = false
        }
    }

    public func started(position: TimeInterval) async {
        guard isEnabled, let itemId, phase == .idle else { return }
        phase = .starting
        do {
            let service = try await ensureService()
            guard phase == .starting else { return }
            try await service.reportPlaybackStarted(
                itemId: itemId,
                positionTicks: EmbyService.positionTicks(fromSeconds: position),
                playSessionId: playSessionId
            )
            guard phase == .starting else { return }
            phase = .started
            lastProgressAt = Date()
        } catch {
            if phase == .starting {
                phase = .idle
            }
            VanmoLogger.network.error(
                "[EmbyPlayback] started failed: \(error.localizedDescription)"
            )
        }
    }

    public func progress(
        position: TimeInterval,
        isPaused: Bool,
        event: EmbyPlaybackProgressEvent,
        force: Bool = false
    ) async {
        guard isEnabled, let itemId, phase == .started else { return }

        let shouldSend = force || event.bypassesThrottle || shouldSendThrottledProgress()
        guard shouldSend else { return }

        // 乐观更新，避免并发 timeUpdate 冲破节流。
        lastProgressAt = Date()
        inFlightProgressCount += 1
        defer { inFlightProgressCount -= 1 }

        do {
            let service = try await ensureService()
            guard phase == .started else { return }
            try await service.reportPlaybackProgress(
                itemId: itemId,
                positionTicks: EmbyService.positionTicks(fromSeconds: position),
                isPaused: isPaused,
                eventName: event.apiValue,
                playSessionId: playSessionId
            )
        } catch {
            VanmoLogger.network.error(
                "[EmbyPlayback] progress failed: \(error.localizedDescription)"
            )
        }
    }

    public func stopped(position: TimeInterval) async {
        guard isEnabled, let itemId else {
            phase = .stopped
            await tearDownService()
            return
        }
        guard phase == .started || phase == .starting else {
            phase = .stopped
            await tearDownService()
            return
        }
        phase = .stopped
        do {
            let service = try await ensureService()
            try await service.reportPlaybackStopped(
                itemId: itemId,
                positionTicks: EmbyService.positionTicks(fromSeconds: position),
                playSessionId: playSessionId
            )
        } catch {
            VanmoLogger.network.error(
                "[EmbyPlayback] stopped failed: \(error.localizedDescription)"
            )
        }
        await tearDownService()
    }

    private func shouldSendThrottledProgress() -> Bool {
        guard let lastProgressAt else { return true }
        return Date().timeIntervalSince(lastProgressAt) >= progressInterval
    }

    private func ensureService() async throws -> EmbyService {
        if let service { return service }
        let created = try await makeService()
        guard phase != .stopped else {
            await created.disconnect()
            throw NetworkError.notConnected
        }
        service = created
        return created
    }

    private func tearDownService() async {
        guard let service else { return }
        self.service = nil
        await service.disconnect()
    }

    private func makeService() async throws -> EmbyService {
        if let connection {
            return try await EmbyConnectionHelper.connect(connection)
        }
        throw NetworkError.notConnected
    }
}

/// 将本地「已看 / 未看」写回 Emby/Jellyfin（镜像 `EmbyFavoriteUpdater`）。
public enum EmbyPlayedUpdater {
    @MainActor
    public static func setPlayed(
        _ item: MediaItem,
        isPlayed: Bool,
        connection: MediaServerConnectionSnapshot? = nil
    ) async throws {
        guard let itemId = item.serverId else { return }
        guard let connection,
              connection.type == .emby || connection.type == .jellyfin else {
            return
        }

        let service = try await EmbyConnectionHelper.connect(connection)
        defer { Task { await service.disconnect() } }
        try await service.setPlayed(itemId: itemId, isPlayed: isPlayed)
    }
}
