import Foundation
import SwiftData

@Model
final class MediaItem {
    var id: UUID
    var title: String
    var originalTitle: String?
    var year: Int?
    var overview: String?
    var posterURL: URL?
    var backdropURL: URL?
    var rating: Double?
    var mediaType: MediaType
    var fileURL: URL
    var fileSize: Int64
    var duration: TimeInterval
    var lastPlayedAt: Date?
    var lastPlaybackPosition: TimeInterval
    var isWatched: Bool
    var isFavorite: Bool
    var addedAt: Date

    var tmdbID: Int?
    var genres: [String]
    var director: String?
    var cast: [String]

    var originCountry: [String]

    var seasonNumber: Int?
    var episodeNumber: Int?
    var showTitle: String?

    var audioTracks: [AudioTrackInfo]
    var subtitleTracks: [SubtitleTrackInfo]

    init(
        title: String,
        fileURL: URL,
        mediaType: MediaType = .movie,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0
    ) {
        self.id = UUID()
        self.title = title
        self.fileURL = fileURL
        self.mediaType = mediaType
        self.fileSize = fileSize
        self.duration = duration
        self.lastPlaybackPosition = 0
        self.isWatched = false
        self.isFavorite = false
        self.addedAt = Date()
        self.genres = []
        self.cast = []
        self.originCountry = []
        self.audioTracks = []
        self.subtitleTracks = []
    }

    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return lastPlaybackPosition / duration
    }

    var isRecentlyPlayed: Bool {
        guard let lastPlayed = lastPlayedAt else { return false }
        return Date().timeIntervalSince(lastPlayed) < 7 * 24 * 3600
    }

    var displayTitle: String {
        if mediaType == .tvEpisode,
           let showTitle,
           let season = seasonNumber,
           let episode = episodeNumber {
            return "\(showTitle) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
        }
        return title
    }
}

enum MediaType: String, Codable, CaseIterable {
    case movie
    case tvShow
    case tvEpisode
    case other

    var displayName: String {
        switch self {
        case .movie: return "电影"
        case .tvShow: return "电视剧"
        case .tvEpisode: return "单集"
        case .other: return "其他"
        }
    }

    var icon: String {
        switch self {
        case .movie: return "film"
        case .tvShow: return "tv"
        case .tvEpisode: return "play.rectangle"
        case .other: return "doc.richtext"
        }
    }
}

struct AudioTrackInfo: Codable, Identifiable, Hashable {
    var id: Int
    var language: String?
    var title: String?
    var codec: String?
    var channels: Int?

    var displayName: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let language { parts.append(language) }
        if let codec { parts.append(codec) }
        if let channels { parts.append("\(channels)ch") }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}

struct SubtitleTrackInfo: Codable, Identifiable, Hashable {
    var id: Int
    var language: String?
    var title: String?
    var isEmbedded: Bool
    var fileURL: URL?

    var displayName: String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let language { parts.append(language) }
        parts.append(isEmbedded ? "内嵌" : "外挂")
        return parts.isEmpty ? "Subtitle \(id)" : parts.joined(separator: " · ")
    }
}
