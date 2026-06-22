import Foundation
import SwiftData

@Model
final class FolderBookmark {
    var id: UUID
    var title: String
    var connectionId: UUID
    var connectionName: String
    var path: String
    var addedAt: Date

    init(title: String, connectionId: UUID, connectionName: String, path: String) {
        self.id = UUID()
        self.title = title
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.path = path
        self.addedAt = Date()
    }
}
