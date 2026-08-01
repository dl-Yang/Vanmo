import Foundation

public struct MediaIdentificationResult: Sendable, Equatable {
    public let title: String
    public let showTitle: String?
    public let episodeTitle: String?
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let mediaType: MediaType
    public let overview: String?
    public let tmdbID: Int?
    public let confidence: Double

    public var isTV: Bool { mediaType == .tvEpisode }
}

public enum MediaIdentificationPipeline {
    public static func identify(
        fileName: String,
        directoryPath: String,
        nfoByFileName: [String: ParsedNFOMetadata] = [:]
    ) -> MediaIdentificationResult? {
        if isIgnoredRelease(fileName) {
            return nil
        }

        let parsedFile = FileNameParser.parse(fileName)
        let directory = DirectorySemanticsParser.parse(directoryPath: directoryPath)
        let nfo = resolveNFO(for: fileName, nfoByFileName: nfoByFileName)

        return merge(
            fileName: fileName,
            parsedFile: parsedFile,
            directory: directory,
            nfo: nfo
        )
    }

    // MARK: - Private

    private static func isIgnoredRelease(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        let ignoredTokens = ["sample", "trailer", "preview", "teaser", "deleted.scene", "featurette"]
        return ignoredTokens.contains { lower.contains($0) }
    }

    private static func resolveNFO(
        for fileName: String,
        nfoByFileName: [String: ParsedNFOMetadata]
    ) -> ParsedNFOMetadata? {
        for candidate in NFOMetadataParser.nfoFileNameCandidates(forVideoFileName: fileName) {
            if let nfo = nfoByFileName[candidate.lowercased()] {
                return nfo
            }
        }
        return nil
    }

    private static func merge(
        fileName: String,
        parsedFile: ParsedFileName,
        directory: DirectorySemantics?,
        nfo: ParsedNFOMetadata?
    ) -> MediaIdentificationResult {
        var confidence = parsedFile.confidence
        var mediaType: MediaType = parsedFile.isTV ? .tvEpisode : .movie
        var title = parsedFile.title
        var showTitle: String? = parsedFile.isTV ? parsedFile.title : nil
        var episodeTitle: String? = parsedFile.episodeTitle
        var year = parsedFile.year
        var season = parsedFile.season
        var episode = parsedFile.episode
        var overview: String?
        var tmdbID: Int?

        if let directory {
            confidence = max(confidence, directory.confidence)
            switch directory.kind {
            case .movieRoot:
                if !parsedFile.isTV {
                    mediaType = .movie
                    if let folderTitle = directory.title, !folderTitle.isEmpty {
                        title = folderTitle
                    }
                    if year == nil {
                        year = directory.year
                    }
                }
            case .tvShowRoot:
                if let folderShow = directory.showTitle, !folderShow.isEmpty {
                    showTitle = folderShow
                    if parsedFile.title.isEmpty || parsedFile.title == folderShow {
                        title = folderShow
                    }
                }
                if parsedFile.isTV || directory.season != nil {
                    mediaType = .tvEpisode
                }
            case .tvSeason:
                mediaType = .tvEpisode
                if let folderShow = directory.showTitle, !folderShow.isEmpty {
                    showTitle = folderShow
                }
                if season == nil {
                    season = directory.season
                }
            }
        }

        if let nfo {
            confidence = max(confidence, 0.85)
            switch nfo.kind {
            case .movie:
                if let nfoTitle = nfo.title, !nfoTitle.isEmpty { title = nfoTitle }
                mediaType = .movie
            case .tvShow:
                if let nfoShow = nfo.showTitle ?? nfo.title, !nfoShow.isEmpty {
                    showTitle = nfoShow
                    title = nfoShow
                }
            case .episode:
                mediaType = .tvEpisode
                if let nfoShow = nfo.showTitle, !nfoShow.isEmpty { showTitle = nfoShow }
                if let nfoEpisodeTitle = nfo.episodeTitle, !nfoEpisodeTitle.isEmpty {
                    episodeTitle = nfoEpisodeTitle
                    title = nfoEpisodeTitle
                } else if let nfoTitle = nfo.title, !nfoTitle.isEmpty {
                    title = nfoTitle
                }
            }
            if year == nil { year = nfo.year }
            if season == nil { season = nfo.season }
            if episode == nil { episode = nfo.episode }
            overview = nfo.overview
            if tmdbID == nil { tmdbID = nfo.tmdbID }
        }

        if mediaType == .tvEpisode, let showTitle, !showTitle.isEmpty, title.isEmpty {
            title = showTitle
        }

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = (fileName as NSString).deletingPathExtension
        }

        return MediaIdentificationResult(
            title: title,
            showTitle: showTitle,
            episodeTitle: episodeTitle,
            year: year,
            season: season,
            episode: episode,
            mediaType: mediaType,
            overview: overview,
            tmdbID: tmdbID,
            confidence: min(confidence, 1.0)
        )
    }
}

public struct DirectorySemantics: Sendable, Equatable {
    public enum Kind: Sendable {
        case movieRoot
        case tvShowRoot
        case tvSeason
    }

    public let kind: Kind
    public let title: String?
    public let showTitle: String?
    public let year: Int?
    public let season: Int?
    public let confidence: Double
}

public enum DirectorySemanticsParser {
    private static let movieFolderNames: Set<String> = [
        "movies", "movie", "films", "film", "电影", "影片"
    ]

    private static let tvFolderNames: Set<String> = [
        "tv", "tv shows", "tvshows", "series", "shows", "television",
        "电视剧", "剧集", "电视", "番剧", "动漫"
    ]

    public static func parse(directoryPath: String) -> DirectorySemantics? {
        let components = normalizedComponents(directoryPath)
        guard !components.isEmpty else { return nil }

        for (index, component) in components.enumerated() {
            let lower = component.lowercased()

            if movieFolderNames.contains(lower), index + 1 < components.count {
                let movieFolder = components[index + 1]
                let (title, year) = parseTitleYear(from: movieFolder)
                return DirectorySemantics(
                    kind: .movieRoot,
                    title: title,
                    showTitle: nil,
                    year: year,
                    season: nil,
                    confidence: 0.75
                )
            }

            if tvFolderNames.contains(lower), index + 1 < components.count {
                let showFolder = components[index + 1]
                if let seasonInfo = parseSeasonFolder(components, startIndex: index + 2, showTitle: showFolder) {
                    return seasonInfo
                }
                let (showTitle, _) = parseTitleYear(from: showFolder)
                return DirectorySemantics(
                    kind: .tvShowRoot,
                    title: showTitle,
                    showTitle: showTitle,
                    year: nil,
                    season: nil,
                    confidence: 0.7
                )
            }
        }

        if let seasonOnly = parseSeasonFolder(components, startIndex: components.count - 1, showTitle: nil) {
            return seasonOnly
        }

        return nil
    }

    private static func normalizedComponents(_ path: String) -> [String] {
        path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func parseTitleYear(from folder: String) -> (String, Int?) {
        if let regex = try? NSRegularExpression(pattern: #"^(.*)\((\d{4})\)\s*$"#),
           let match = regex.firstMatch(in: folder, range: NSRange(folder.startIndex..., in: folder)),
           let titleRange = Range(match.range(at: 1), in: folder),
           let yearRange = Range(match.range(at: 2), in: folder) {
            let title = String(folder[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let year = Int(folder[yearRange])
            return (title, year)
        }
        return (folder, nil)
    }

    private static func parseSeasonFolder(
        _ components: [String],
        startIndex: Int,
        showTitle: String?
    ) -> DirectorySemantics? {
        guard startIndex >= 0, startIndex < components.count else { return nil }
        let folder = components[startIndex]
        let patterns = [
            #"^[Ss]eason[\s._-]*(\d{1,2})$"#,
            #"^[Ss](\d{1,2})$"#,
            #"^第[\s]*(\d{1,2})[\s]*季$"#,
            #"^Season[\s._-]*(\d{1,2})$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: folder, range: NSRange(folder.startIndex..., in: folder)),
               let seasonRange = Range(match.range(at: 1), in: folder),
               let season = Int(folder[seasonRange]) {
                let resolvedShowTitle: String?
                if let showTitle {
                    resolvedShowTitle = parseTitleYear(from: showTitle).0
                } else if startIndex > 0 {
                    resolvedShowTitle = parseTitleYear(from: components[startIndex - 1]).0
                } else {
                    resolvedShowTitle = nil
                }
                return DirectorySemantics(
                    kind: .tvSeason,
                    title: resolvedShowTitle,
                    showTitle: resolvedShowTitle,
                    year: nil,
                    season: season,
                    confidence: 0.8
                )
            }
        }
        return nil
    }
}
