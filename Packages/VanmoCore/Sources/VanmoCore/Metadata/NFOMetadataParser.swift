import Foundation
import SWXMLHash

public struct ParsedNFOMetadata: Sendable, Equatable {
    public let title: String?
    public let showTitle: String?
    public let episodeTitle: String?
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let overview: String?
    public let tmdbID: Int?
    public let kind: NFOKind

    public enum NFOKind: Sendable {
        case movie
        case tvShow
        case episode
    }
}

public enum NFOMetadataParser {
    public static func parse(data: Data, fileName: String) -> ParsedNFOMetadata? {
        let xml = XMLHash.parse(data)
        let root: XMLIndexer
        let kind: ParsedNFOMetadata.NFOKind
        if xml["movie"].element != nil {
            root = xml["movie"]
            kind = .movie
        } else if xml["tvshow"].element != nil {
            root = xml["tvshow"]
            kind = .tvShow
        } else if xml["episodedetails"].element != nil {
            root = xml["episodedetails"]
            kind = .episode
        } else {
            root = xml
            let lower = fileName.lowercased()
            if lower == "tvshow.nfo" {
                kind = .tvShow
            } else if lower.hasSuffix(".nfo"), lower != "movie.nfo" {
                kind = .episode
            } else {
                kind = .movie
            }
        }

        let title = firstString(in: root, keys: ["title", "name", "originaltitle"])
        let showTitle = firstString(in: root, keys: ["showtitle"])
        let episodeTitle = firstString(in: root, keys: ["episodename", "subtitle"])
        let overview = firstString(in: root, keys: ["plot", "outline"])
        let year = firstInt(in: root, keys: ["year"])
            ?? yearFromDateString(firstString(in: root, keys: ["premiered", "releasedate"]))
        let season = firstInt(in: root, keys: ["season"])
        let episode = firstInt(in: root, keys: ["episode"])

        return ParsedNFOMetadata(
            title: title,
            showTitle: showTitle,
            episodeTitle: episodeTitle,
            year: year,
            season: season,
            episode: episode,
            overview: overview,
            tmdbID: extractTMDBID(from: root),
            kind: kind
        )
    }

    public static func nfoFileNameCandidates(forVideoFileName fileName: String) -> [String] {
        let stem = (fileName as NSString).deletingPathExtension
        return [
            "\(stem).nfo",
            "movie.nfo",
            "tvshow.nfo",
        ]
    }

    public static func isNFOFileName(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".nfo")
    }

    // MARK: - Private

    private static func firstString(in element: XMLIndexer, keys: [String]) -> String? {
        for key in keys {
            if let value = element[key].element?.text.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstInt(in element: XMLIndexer, keys: [String]) -> Int? {
        guard let raw = firstString(in: element, keys: keys) else { return nil }
        let digits = raw.filter(\.isNumber)
        return Int(digits)
    }

    private static func yearFromDateString(_ value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    private static func extractTMDBID(from root: XMLIndexer) -> Int? {
        for uniqueID in root["uniqueid"].all {
            let type = uniqueID.element?.attribute(by: "type")?.text.lowercased()
            let defaultAttr = uniqueID.element?.attribute(by: "default")?.text.lowercased()
            let text = uniqueID.element?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if type == "tmdb", let id = Int(text.filter(\.isNumber)), id > 0 {
                return id
            }
            if defaultAttr == "true", type == "tmdb", let id = Int(text.filter(\.isNumber)), id > 0 {
                return id
            }
        }

        if let imdbStyle = firstString(in: root, keys: ["tmdbid", "tmdbId", "tmdb_id"]),
           let id = Int(imdbStyle.filter(\.isNumber)), id > 0 {
            return id
        }

        return nil
    }
}
