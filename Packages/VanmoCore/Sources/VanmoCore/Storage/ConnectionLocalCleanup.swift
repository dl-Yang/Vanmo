import Foundation
import SwiftData

/// Removes LocalStore catalog and playback rows that belong to one connection.
public enum ConnectionLocalCleanup {
    public static func deleteLocalMedia(for connectionId: UUID, in context: ModelContext) {
        do {
            let items = try context.fetch(
                FetchDescriptor<MediaItem>(
                    predicate: #Predicate<MediaItem> { item in
                        item.sourceConnectionId == connectionId
                    }
                )
            )
            let itemIDs = Set(items.map(\.id))
            for item in items {
                context.delete(item)
            }
            guard !itemIDs.isEmpty else { return }
            let records = try context.fetch(FetchDescriptor<PlaybackRecord>())
            for record in records where itemIDs.contains(record.mediaItemID) {
                context.delete(record)
            }
        } catch {
            VanmoLogger.library.error("[Connections] Delete cached media failed: \(error.localizedDescription)")
        }
    }
}
