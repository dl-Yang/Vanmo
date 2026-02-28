import Foundation
import SwiftData

@Model
final class PlaybackRecord {
    var id: UUID
    var mediaItemID: UUID
    var position: TimeInterval
    var duration: TimeInterval
    var playedAt: Date
    var selectedAudioTrack: Int?
    var selectedSubtitleTrack: Int?

    init(
        mediaItemID: UUID,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        self.id = UUID()
        self.mediaItemID = mediaItemID
        self.position = position
        self.duration = duration
        self.playedAt = Date()
    }
}
