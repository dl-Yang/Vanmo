import Foundation

public struct ParsedFileName {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let episodeTitle: String?
    public let isTV: Bool
    public let confidence: Double

    public var searchQuery: String {
        title.replacingOccurrences(of: ".", with: " ")
             .replacingOccurrences(of: "_", with: " ")
             .trimmingCharacters(in: .whitespaces)
    }

    public init(
        title: String,
        year: Int?,
        season: Int?,
        episode: Int?,
        episodeTitle: String? = nil,
        isTV: Bool,
        confidence: Double = 0.5
    ) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.isTV = isTV
        self.confidence = confidence
    }
}

public enum FileNameParser {
    private static let tvPatterns: [(pattern: String, seasonGroup: Int, episodeGroup: Int, confidence: Double)] = [
        (#"[Ss](\d{1,2})[Ee](\d{1,3})(?:[Ee](\d{1,3}))?"#, 1, 2, 0.9),
        (#"(\d{1,2})[xX](\d{1,3})"#, 1, 2, 0.85),
        (#"[Ss]eason[\s._-]*(\d{1,2}).*[Ee]pisode[\s._-]*(\d{1,3})"#, 1, 2, 0.85),
        (#"\[(\d{1,2})[xX](\d{1,3})\]"#, 1, 2, 0.8),
        (#"\b[Ee][Pp](\d{1,3})\b"#, 0, 1, 0.75),
        (#"\b[Ee](\d{1,3})\b"#, 0, 1, 0.65),
        (#"第[\s]*(\d{1,2})[\s]*季[\s._-]*第[\s]*(\d{1,3})[\s]*集"#, 1, 2, 0.85),
        (#"第[\s]*(\d{1,3})[\s]*集"#, 0, 1, 0.7),
        (#"\[(\d{1,3})\]"#, 0, 1, 0.6),
    ]

    private static let yearPattern = #"\b((?:19|20)\d{2})\b"#

    private static let cleanupPatterns = [
        #"\b(720p|1080p|1440p|2160p|4320p|4K|8K|UHD|HD|FHD)\b"#,
        #"\b(BluRay|BDRip|BRRip|WEB-DL|WEBRip|WEBDL|HDTV|DVDRip|HDRip|HDTC|CAM|TS|TC)\b"#,
        #"\b(x264|x265|H\.264|H\.265|HEVC|AVC|AAC|DTS|AC3|FLAC|Atmos|TrueHD|DDP?\d?(?:\.\d)?)\b"#,
        #"\b(REMUX|PROPER|REPACK|EXTENDED|UNRATED|DIRECTORS\.CUT|IMAX|HDR10|DV|DoVi)\b"#,
        #"\b(SP|OVA|OAD|NC|PV|CM|Menu|Bonus|Extra|Special)\b"#,
        #"\[.*?\]"#,
        #"\((?!.*\d{4})[^)]*\)"#,
    ]

    public static func parse(_ fileName: String) -> ParsedFileName {
        let name = (fileName as NSString).deletingPathExtension

        for tvPattern in tvPatterns {
            if let regex = try? NSRegularExpression(pattern: tvPattern.pattern),
               let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {

                let season: Int?
                if tvPattern.seasonGroup > 0,
                   let seasonRange = Range(match.range(at: tvPattern.seasonGroup), in: name) {
                    season = Int(name[seasonRange])
                } else {
                    season = nil
                }

                let episodeRange = Range(match.range(at: tvPattern.episodeGroup), in: name)
                let episode = episodeRange.flatMap { Int(name[$0]) }

                let titleEnd = match.range.location
                let rawTitle = String(name.prefix(titleEnd))
                let title = cleanTitle(rawTitle)
                let episodeTitle = extractEpisodeTitle(from: name, afterIndex: match.range.upperBound)

                return ParsedFileName(
                    title: title,
                    year: extractYear(from: name),
                    season: season,
                    episode: episode,
                    episodeTitle: episodeTitle,
                    isTV: true,
                    confidence: tvPattern.confidence
                )
            }
        }

        let year = extractYear(from: name)
        var title = name

        if let year {
            if let range = title.range(of: "\(year)") {
                title = String(title[title.startIndex..<range.lowerBound])
            }
        }

        title = cleanTitle(title)

        return ParsedFileName(
            title: title,
            year: year,
            season: nil,
            episode: nil,
            episodeTitle: nil,
            isTV: false,
            confidence: year == nil ? 0.45 : 0.6
        )
    }

    private static func extractEpisodeTitle(from string: String, afterIndex: Int) -> String? {
        guard afterIndex < string.count else { return nil }
        let start = string.index(string.startIndex, offsetBy: afterIndex)
        var remainder = String(string[start...])
        remainder = cleanTitle(remainder)
        return remainder.isEmpty ? nil : remainder
    }

    private static func extractYear(from string: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: yearPattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range, in: string) else {
            return nil
        }
        return Int(string[range])
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = raw

        for pattern in cleanupPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                title = regex.stringByReplacingMatches(
                    in: title,
                    range: NSRange(title.startIndex..., in: title),
                    withTemplate: ""
                )
            }
        }

        title = title
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: " - ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while title.hasSuffix("-") || title.hasSuffix(" ") {
            title = String(title.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return title
    }
}
