import Foundation

public enum DownloadRequestFactory {
    @MainActor
    public static func make(
        from item: MediaItem,
        connectionType: ConnectionType?
    ) throws -> DownloadRequest {
        guard DownloadEligibility.isEligible(item: item, connectionType: connectionType) else {
            throw DownloadError.unsupportedSource
        }

        let remotePath = connectionType == .plex
            ? item.fileURL.path
            : (item.serverId ?? item.fileURL.path)
        let fallbackName = fileName(
            title: item.displayTitle,
            preferredName: item.originalFileName,
            sourceURL: item.fileURL,
            container: item.container
        )
        return DownloadRequest(
            sourceConnectionId: item.sourceConnectionId,
            postUrl: item.posterURL ?? item.backdropURL,
            sourceMediaItemID: item.id,
            sourceServerID: item.serverId,
            seriesServerID: item.seriesId,
            connectionType: connectionType,
            remotePath: remotePath,
            sourceFileURL: item.sourceConnectionId == nil ? item.fileURL : nil,
            fileName: fallbackName,
            displayTitle: item.displayTitle,
            mediaType: item.mediaType,
            totalBytes: item.fileSize,
            showTitle: item.showTitle,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            episodeTitle: item.episodeTitle
        )
    }

    public static func make(
        from file: RemoteFile,
        connectionId: UUID,
        connectionType: ConnectionType
    ) throws -> DownloadRequest {
        guard DownloadEligibility.isEligible(file: file, connectionType: connectionType) else {
            throw DownloadError.unsupportedSource
        }
        return DownloadRequest(
            sourceConnectionId: connectionId,
            connectionType: connectionType,
            remotePath: file.path,
            fileName: file.name,
            displayTitle: file.name.deletingPathExtension,
            mediaType: .movie,
            totalBytes: file.size
        )
    }

    @MainActor
    public static func make(
        from episode: EpisodeInfo,
        show: MediaItem,
        connectionType: ConnectionType?
    ) throws -> DownloadRequest {
        guard let connectionId = show.sourceConnectionId else {
            throw DownloadError.missingConnection
        }
        if let connectionType, !DownloadEligibility.isSupported(connectionType: connectionType) {
            throw DownloadError.unsupportedSource
        }

        let showTitle = show.showTitle ?? show.title
        let displayTitle = "\(showTitle) S\(String(format: "%02d", episode.seasonNumber))E\(String(format: "%02d", episode.episodeNumber))"
        let fileName = fileName(
            title: displayTitle,
            preferredName: episode.originalFileName,
            sourceURL: episode.streamURL,
            container: episode.container
        )
        return DownloadRequest(
            sourceConnectionId: connectionId,
            postUrl: episode.backdropURL ?? show.posterURL ?? show.backdropURL,
            sourceMediaItemID: show.id,
            sourceServerID: episode.id,
            seriesServerID: show.serverId ?? show.seriesId,
            connectionType: connectionType,
            remotePath: episode.remotePath ?? episode.id,
            fileName: fileName,
            displayTitle: displayTitle,
            mediaType: .tvEpisode,
            totalBytes: episode.fileSize,
            showTitle: showTitle,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
            episodeTitle: episode.title
        )
    }

    private static func fileName(
        title: String,
        preferredName: String?,
        sourceURL: URL,
        container: String?
    ) -> String {
        if let preferredName, !preferredName.isEmpty {
            return preferredName
        }
        let sourceExtension = sourceURL.pathExtension
        let ext = sourceExtension.isEmpty ? (container ?? "") : sourceExtension
        return ext.isEmpty ? title : "\(title).\(ext)"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
