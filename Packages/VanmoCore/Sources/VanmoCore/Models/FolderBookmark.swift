import Foundation
import SwiftData

@Model
public final class FolderBookmark {
    public var id: UUID
    public var title: String
    public var connectionId: UUID
    public var connectionName: String
    public var path: String
    public var addedAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var lastModifiedDeviceId: String?

    public init(title: String, connectionId: UUID, connectionName: String, path: String) {
        self.id = UUID()
        self.title = title
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.path = path
        self.addedAt = Date()
        self.updatedAt = Date()
        self.lastModifiedDeviceId = CloudSyncDevice.id
    }
}
