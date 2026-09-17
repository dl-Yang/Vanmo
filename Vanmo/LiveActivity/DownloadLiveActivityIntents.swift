import AppIntents
import Foundation

enum DownloadLiveActivityAction: Sendable {
    case pause(UUID)
    case resume(UUID)
    case cancel(UUID)
}

enum DownloadLiveActivityActionCenter {
    static var handler: ((DownloadLiveActivityAction) async -> Void)?

    static func submit(_ action: DownloadLiveActivityAction) async {
        guard let handler else { return }
        await handler(action)
    }
}

struct PauseDownloadIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停"
    static var description = IntentDescription("Pause the current download")

    @Parameter(title: "Task")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            await DownloadLiveActivityActionCenter.submit(.pause(id))
        }
        return .result()
    }
}

struct ResumeDownloadIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续"
    static var description = IntentDescription("Resume the current download")

    @Parameter(title: "Task")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            await DownloadLiveActivityActionCenter.submit(.resume(id))
        }
        return .result()
    }
}

struct CancelDownloadIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "取消"
    static var description = IntentDescription("Cancel the current download")

    @Parameter(title: "Task")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            await DownloadLiveActivityActionCenter.submit(.cancel(id))
        }
        return .result()
    }
}
