import Foundation

public enum MediaItemFactory {
    public static func makeMediaItem(
        from file: RemoteFile,
        streamURL: URL,
        connectionId: UUID?,
        directoryPath: String,
        nfoByFileName: [String: ParsedNFOMetadata] = [:]
    ) -> MediaItem? {
        guard let identification = MediaIdentificationPipeline.identify(
            fileName: file.name,
            directoryPath: directoryPath,
            nfoByFileName: nfoByFileName
        ) else {
            return nil
        }

        let item = MediaItem(
            title: identification.title,
            fileURL: streamURL,
            mediaType: identification.mediaType,
            fileSize: file.size
        )
        applyIdentification(identification, file: file, connectionId: connectionId, to: item)
        return item
    }

    public static func applyIdentification(
        _ identification: MediaIdentificationResult,
        file: RemoteFile,
        connectionId: UUID?,
        to item: MediaItem
    ) {
        item.title = identification.title
        item.year = identification.year
        item.seasonNumber = identification.season
        item.episodeNumber = identification.episode
        item.episodeTitle = identification.episodeTitle
        item.mediaType = identification.mediaType
        item.overview = identification.overview ?? item.overview
        item.identificationConfidence = identification.confidence
        if let tmdbID = identification.tmdbID {
            item.tmdbID = tmdbID
        }

        if identification.isTV {
            item.showTitle = identification.showTitle ?? identification.title
        } else {
            item.showTitle = nil
        }

        item.serverId = file.path
        item.sourceConnectionId = connectionId
        item.originalFileName = file.name
        item.remoteModifiedAt = file.modifiedDate
        item.remoteContentVersion = file.contentVersion
        let ext = (file.name as NSString).pathExtension
        item.container = ext.isEmpty ? nil : ext.lowercased()
        MediaProbeApplicator.invalidateIfNeeded(existing: item, file: file)
    }

    public static func applyRemoteFileMetadata(
        _ file: RemoteFile,
        streamURL: URL,
        connectionId: UUID?,
        directoryPath: String,
        nfoByFileName: [String: ParsedNFOMetadata],
        to item: MediaItem
    ) {
        item.fileURL = streamURL
        item.fileSize = file.size
        item.originalFileName = file.name
        item.remoteModifiedAt = file.modifiedDate
        item.remoteContentVersion = file.contentVersion
        item.serverId = file.path
        if let connectionId {
            item.sourceConnectionId = connectionId
        }

        MediaProbeApplicator.invalidateIfNeeded(existing: item, file: file)

        if let identification = MediaIdentificationPipeline.identify(
            fileName: file.name,
            directoryPath: directoryPath,
            nfoByFileName: nfoByFileName
        ) {
            applyIdentification(identification, file: file, connectionId: connectionId, to: item)
        }
    }

    public static func remoteFileChanged(existing: MediaItem, file: RemoteFile, forceFullScan: Bool) -> Bool {
        if forceFullScan { return true }
        if existing.originalFileName != file.name { return true }
        if existing.fileSize != file.size { return true }
        if let version = file.contentVersion, existing.remoteContentVersion != version {
            return true
        }
        if let remoteModified = file.modifiedDate {
            if existing.remoteModifiedAt != remoteModified { return true }
            return false
        }
        return false
    }

    public static func parentDirectoryPath(for filePath: String) -> String {
        if filePath == "/" || filePath.isEmpty { return "/" }
        let nsPath = filePath as NSString
        let parent = nsPath.deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}
