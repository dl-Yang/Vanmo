import Foundation

public actor MetadataService {
    public static let shared = MetadataService()

    @MainActor
    public func applyCachedRecord(_ record: MetadataCacheRecord, rootDirectory: URL, to item: MediaItem) {
        item.title = record.title
        item.originalTitle = record.originalTitle
        item.year = record.year
        item.overview = record.overview
        item.rating = record.rating
        item.genres = record.genres
        item.director = record.director
        item.cast = record.castMembers.isEmpty ? record.cast : record.castMembers.map(\.name)
        item.originCountry = record.originCountry
        item.tmdbID = record.tmdbID
        item.logoURL = record.resolvedLogoURL(rootDirectory: rootDirectory)
        item.backdropURL = record.resolvedBackdropURL(rootDirectory: rootDirectory)
        if let poster = record.posterRemoteURL {
            item.posterURL = poster
        }
    }
}
