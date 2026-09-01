import Foundation

public enum ServerMediaItemMapper {
    @MainActor
    public static func makeMediaItem(from serverItem: ServerMediaItem) -> MediaItem {
        let item = MediaItem(
            title: serverItem.title,
            fileURL: serverItem.streamURL,
            mediaType: serverItem.mediaType,
            fileSize: serverItem.fileSize,
            duration: serverItem.duration
        )
        item.originalTitle = serverItem.originalTitle
        item.year = serverItem.year
        item.overview = serverItem.overview
        item.posterURL = serverItem.posterURL
        item.backdropURL = serverItem.backdropURL
        item.logoURL = serverItem.logoURL
        item.rating = serverItem.rating
        item.contentRating = serverItem.contentRating
        item.originalFileName = serverItem.originalFileName
        item.container = serverItem.container
        item.videoWidth = serverItem.videoWidth
        item.videoHeight = serverItem.videoHeight
        if let dynamicRange = serverItem.dynamicRange {
            item.dynamicRange = dynamicRange
        }
        item.genres = serverItem.genres
        item.director = serverItem.director
        item.cast = serverItem.cast
        item.originCountry = serverItem.originCountry
        item.tmdbID = serverItem.tmdbID
        item.serverId = serverItem.serverId
        item.seriesId = serverItem.seriesId
        item.showTitle = serverItem.showTitle
        item.seasonNumber = serverItem.seasonNumber
        item.episodeNumber = serverItem.episodeNumber
        item.episodeTitle = serverItem.episodeTitle
        item.lastPlaybackPosition = serverItem.lastPlaybackPosition
        if let lastPlayedAt = serverItem.lastPlayedAt {
            item.lastPlayedAt = lastPlayedAt
        }
        if let dateCreated = serverItem.dateCreated {
            item.addedAt = dateCreated
        }
        item.isFavorite = serverItem.isFavoriteOnServer
        item.isProgressCloudSynced = false
        item.isFavoriteCloudSynced = false
        return item
    }
}
