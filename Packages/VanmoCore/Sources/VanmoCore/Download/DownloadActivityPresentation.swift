import Foundation

/// Chooses which download the island, fallback bar, or similar chrome should show.
public struct DownloadActivityPresentation: Equatable, Sendable {
    public let task: DownloadTaskSnapshot?
    public let didCompleteCurrent: Bool

    public var shouldEnd: Bool { task == nil }

    public var title: String {
        guard let task else { return "" }
        return Self.title(for: task.request)
    }

    public var progress: Double {
        guard let task else { return didCompleteCurrent ? 1 : 0 }
        if task.status == .completed { return 1 }
        return task.progress
    }

    public var posterURL: URL? {
        task?.request.postUrl
    }

    public init(task: DownloadTaskSnapshot?, didCompleteCurrent: Bool) {
        self.task = task
        self.didCompleteCurrent = didCompleteCurrent
    }

    public static func select(
        from tasks: [DownloadTaskSnapshot],
        previouslyDisplayedID: UUID? = nil
    ) -> DownloadActivityPresentation {
        let current = focusedTask(in: tasks)
        let previous = previouslyDisplayedID.flatMap { id in
            tasks.first { $0.id == id }
        }
        let previousJustCompleted = previous?.status == .completed
            && (current == nil || current?.id != previous?.id)

        if let current {
            return DownloadActivityPresentation(
                task: current,
                didCompleteCurrent: previousJustCompleted
            )
        }
        return DownloadActivityPresentation(
            task: nil,
            didCompleteCurrent: previousJustCompleted
        )
    }

    public static func title(for request: DownloadRequest) -> String {
        if request.mediaType == .tvEpisode {
            let episode = request.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedEpisode = (episode?.isEmpty == false) ? episode : request.displayTitle
            if let show = request.showTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !show.isEmpty,
               let resolvedEpisode,
               resolvedEpisode != show {
                return "\(show) · \(resolvedEpisode)"
            }
        }
        return request.displayTitle
    }

    private static func focusedTask(in tasks: [DownloadTaskSnapshot]) -> DownloadTaskSnapshot? {
        if let seriesTask = focusedSeriesTask(in: tasks) {
            return seriesTask
        }
        return focusedSingleTask(in: tasks)
    }

    private static func focusedSeriesTask(in tasks: [DownloadTaskSnapshot]) -> DownloadTaskSnapshot? {
        let groups = Dictionary(grouping: tasks.filter { $0.request.mediaType == .tvEpisode }) {
            seriesKey(for: $0.request)
        }
        let multiEpisode = groups.values.filter { $0.count >= 2 }
        guard !multiEpisode.isEmpty else { return nil }

        let activeGroups = multiEpisode.filter { group in
            group.contains { isPresentable($0.status) }
        }
        guard !activeGroups.isEmpty else { return nil }

        let preferredGroup: [DownloadTaskSnapshot]
        if let downloadingGroup = activeGroups.first(where: { group in
            group.contains { $0.status == .downloading }
        }) {
            preferredGroup = downloadingGroup
        } else {
            preferredGroup = activeGroups.max { lhs, rhs in
                latestActivity(in: lhs) < latestActivity(in: rhs)
            } ?? []
        }

        if let downloading = preferredGroup
            .filter({ $0.status == .downloading })
            .min(by: episodeOrder) {
            return downloading
        }
        return preferredGroup
            .filter { isPresentable($0.status) }
            .min(by: episodeOrder)
    }

    private static func focusedSingleTask(in tasks: [DownloadTaskSnapshot]) -> DownloadTaskSnapshot? {
        let presentable = tasks.filter { isPresentable($0.status) }
        if let downloading = presentable
            .filter({ $0.status == .downloading })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return downloading
        }
        if let queued = presentable
            .filter({ $0.status == .queued })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return queued
        }
        return presentable
            .filter { $0.status == .paused }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    private static func isPresentable(_ status: DownloadTaskStatus) -> Bool {
        switch status {
        case .queued, .downloading, .paused:
            return true
        case .completed, .failed:
            return false
        }
    }

    private static func seriesKey(for request: DownloadRequest) -> String {
        if let seriesID = request.seriesServerID, !seriesID.isEmpty {
            return "server:\(seriesID)"
        }
        if let showTitle = request.showTitle, !showTitle.isEmpty {
            return "title:\(showTitle)"
        }
        return "episode:\(request.id.uuidString)"
    }

    private static func episodeOrder(_ lhs: DownloadTaskSnapshot, _ rhs: DownloadTaskSnapshot) -> Bool {
        let left = (
            lhs.request.seasonNumber ?? Int.max,
            lhs.request.episodeNumber ?? Int.max,
            lhs.createdAt
        )
        let right = (
            rhs.request.seasonNumber ?? Int.max,
            rhs.request.episodeNumber ?? Int.max,
            rhs.createdAt
        )
        return left < right
    }

    private static func latestActivity(in tasks: [DownloadTaskSnapshot]) -> Date {
        tasks.map(\.updatedAt).max() ?? .distantPast
    }
}
