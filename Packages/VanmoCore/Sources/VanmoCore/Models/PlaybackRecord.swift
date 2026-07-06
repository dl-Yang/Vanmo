import Foundation
import SwiftData

@Model
public final class PlaybackRecord {
    public var id: UUID
    public var mediaItemID: UUID
    public var position: TimeInterval
    public var duration: TimeInterval
    public var playedAt: Date
    public var selectedAudioTrack: Int?
    public var selectedSubtitleTrack: Int?

    public init(
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
