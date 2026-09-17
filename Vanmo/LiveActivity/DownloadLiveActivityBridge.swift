import ActivityKit
import Foundation
import VanmoCore

struct DownloadLiveActivitySnapshot: Equatable {
    var title: String
    var progress: Double
    var isCompleted: Bool
    var isPaused: Bool
    var posterURL: URL?
    var taskID: String
}

@MainActor
final class DownloadLiveActivityBridge: ObservableObject {
    static let shared = DownloadLiveActivityBridge()

    @Published private(set) var startFailed = false
    @Published private(set) var displayedSnapshot: DownloadLiveActivitySnapshot?

    private var activity: Activity<DownloadLiveActivityAttributes>?
    private var previousID: UUID?
    private var lastPublishedKey: String?
    private var completionPulseTask: Task<Void, Never>?
    private var endGeneration = 0

    var shouldShowFallbackBar: Bool {
        !DownloadIslandCapability.hasDynamicIsland
    }

    func sync(tasks: [DownloadTaskSnapshot]) {
        adoptExistingActivityIfNeeded()
        let presentation = DownloadActivityPresentation.select(
            from: tasks,
            previouslyDisplayedID: previousID
        )

        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if !DownloadIslandCapability.hasDynamicIsland || !enabled {
            previousID = presentation.task?.id
#if DEBUG
            print("[Debug][Downloads] live activity skipped island=\(DownloadIslandCapability.hasDynamicIsland) enabled=\(enabled)")
#endif
            if !enabled {
                startFailed = false
                displayedSnapshot = nil
                Task { await end(immediate: true) }
            }
            return
        }

        if completionPulseTask != nil, !presentation.didCompleteCurrent {
            if presentation.task == nil {
                previousID = nil
                Task { await end(immediate: true) }
            }
            return
        }

        if presentation.didCompleteCurrent {
            let completed = previousID.flatMap { id in tasks.first { $0.id == id } }
            publish(
                taskID: completed?.id ?? presentation.task?.id,
                posterURL: completed?.request.postUrl ?? presentation.task?.request.postUrl,
                title: completed.map { DownloadActivityPresentation.title(for: $0.request) } ?? presentation.title,
                progress: 1,
                isCompleted: true,
                isPaused: false,
                receivedBytes: completed?.receivedBytes ?? presentation.task?.receivedBytes ?? 0,
                totalBytes: completed?.totalBytes ?? presentation.task?.totalBytes ?? 0,
                alertOnComplete: true
            )
            if let next = presentation.task {
                previousID = next.id
                completionPulseTask?.cancel()
                completionPulseTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.completionPulseTask = nil
                    self.publish(
                        taskID: next.id,
                        posterURL: next.request.postUrl,
                        title: DownloadActivityPresentation.title(for: next.request),
                        progress: next.progress,
                        isCompleted: false,
                        isPaused: next.status == .paused,
                        receivedBytes: next.receivedBytes,
                        totalBytes: next.totalBytes,
                        alertOnComplete: false
                    )
                }
                return
            }
            previousID = nil
            Task { await end(immediate: false) }
            return
        }

        if let task = presentation.task {
            previousID = task.id
            publish(
                taskID: task.id,
                posterURL: task.request.postUrl,
                title: DownloadActivityPresentation.title(for: task.request),
                progress: task.progress,
                isCompleted: false,
                isPaused: task.status == .paused,
                receivedBytes: task.receivedBytes,
                totalBytes: task.totalBytes,
                alertOnComplete: false
            )
            return
        }

        previousID = nil
        Task { await end(immediate: true) }
    }

    private func adoptExistingActivityIfNeeded() {
        guard activity == nil else { return }
        activity = Activity<DownloadLiveActivityAttributes>.activities.first
        if activity != nil {
            startFailed = false
        }
    }

    private func publish(
        taskID: UUID?,
        posterURL: URL?,
        title: String,
        progress: Double,
        isCompleted: Bool,
        isPaused: Bool,
        receivedBytes: Int64,
        totalBytes: Int64,
        alertOnComplete: Bool
    ) {
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        let resolvedID = taskID?.uuidString ?? ""
        let key = "\(resolvedID)|\(title)|\(percent)|\(isCompleted)|\(isPaused)|\(receivedBytes)|\(totalBytes)|\(alertOnComplete)"
        guard key != lastPublishedKey || (activity == nil && startFailed) else { return }
        let statusText: String
        if isCompleted {
            statusText = L10n.tr("已完成")
        } else if isPaused {
            statusText = L10n.tr("已暂停")
        } else {
            statusText = L10n.tr("下载中")
        }
        displayedSnapshot = DownloadLiveActivitySnapshot(
            title: title,
            progress: isCompleted ? 1 : Double(percent) / 100,
            isCompleted: isCompleted,
            isPaused: isPaused,
            posterURL: posterURL,
            taskID: resolvedID
        )
        let state = DownloadLiveActivityAttributes.ContentState(
            title: title,
            progress: isCompleted ? 1 : Double(percent) / 100,
            isCompleted: isCompleted,
            statusText: statusText,
            taskID: resolvedID,
            isPaused: isPaused,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes
        )
        upsert(posterURL: posterURL, state: state, alertOnComplete: alertOnComplete && isCompleted)
    }

    private func upsert(
        posterURL: URL?,
        state: DownloadLiveActivityAttributes.ContentState,
        alertOnComplete: Bool
    ) {
        if let activity {
            Task { await update(activity, state: state, alertOnComplete: alertOnComplete) }
            return
        }
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let attributes = DownloadLiveActivityAttributes(posterURLString: posterURL?.absoluteString)
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
            startFailed = false
            lastPublishedKey = "\(state.taskID)|\(state.title)|\(state.percent)|\(state.isCompleted)|\(state.isPaused)|\(state.receivedBytes)|\(state.totalBytes)|\(alertOnComplete)"
#if DEBUG
            print("[Debug][Downloads] live activity started enabled=\(enabled)")
#endif
        } catch {
            startFailed = true
            lastPublishedKey = nil
            displayedSnapshot = nil
#if DEBUG
            print("[Debug][Downloads] live activity start failed enabled=\(enabled) type=\(type(of: error))")
#endif
        }
    }

    private func update(
        _ activity: Activity<DownloadLiveActivityAttributes>,
        state: DownloadLiveActivityAttributes.ContentState,
        alertOnComplete: Bool
    ) async {
        lastPublishedKey = "\(state.taskID)|\(state.title)|\(state.percent)|\(state.isCompleted)|\(state.isPaused)|\(state.receivedBytes)|\(state.totalBytes)|\(alertOnComplete)"
        let content = ActivityContent(state: state, staleDate: nil)
        if alertOnComplete {
            let alert = AlertConfiguration(
                title: LocalizedStringResource("下载完成"),
                body: LocalizedStringResource(stringLiteral: state.title),
                sound: .default
            )
            await activity.update(content, alertConfiguration: alert)
            return
        }
        await activity.update(content)
    }

    private func end(immediate: Bool) async {
        endGeneration += 1
        let generation = endGeneration
        completionPulseTask?.cancel()
        completionPulseTask = nil
        lastPublishedKey = nil
        displayedSnapshot = nil
        startFailed = false
        guard let ending = activity else { return }
        activity = nil
        let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .after(.now + 2)
        await ending.end(ending.content, dismissalPolicy: policy)
        guard generation == endGeneration else { return }
    }
}
