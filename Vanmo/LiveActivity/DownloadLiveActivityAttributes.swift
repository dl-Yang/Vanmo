import ActivityKit
import Foundation

struct DownloadLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var progress: Double
        var isCompleted: Bool
        var statusText: String
        var taskID: String
        var isPaused: Bool
        var receivedBytes: Int64
        var totalBytes: Int64

        enum CodingKeys: String, CodingKey {
            case title, progress, isCompleted, statusText, taskID, isPaused, receivedBytes, totalBytes
        }

        init(
            title: String,
            progress: Double,
            isCompleted: Bool,
            statusText: String,
            taskID: String,
            isPaused: Bool,
            receivedBytes: Int64 = 0,
            totalBytes: Int64 = 0
        ) {
            self.title = title
            self.progress = progress
            self.isCompleted = isCompleted
            self.statusText = statusText
            self.taskID = taskID
            self.isPaused = isPaused
            self.receivedBytes = receivedBytes
            self.totalBytes = totalBytes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            progress = try container.decode(Double.self, forKey: .progress)
            isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
            statusText = try container.decode(String.self, forKey: .statusText)
            taskID = try container.decodeIfPresent(String.self, forKey: .taskID) ?? ""
            isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            receivedBytes = try container.decodeIfPresent(Int64.self, forKey: .receivedBytes) ?? 0
            totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        }

        var percent: Int {
            Int(((isCompleted ? 1 : min(max(progress, 0), 1)) * 100).rounded())
        }

        var byteLine: String {
            let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
            guard totalBytes > 0 else { return received }
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(received) / \(total)"
        }
    }

    var posterURLString: String?
}
