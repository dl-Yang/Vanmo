import Foundation

struct ParsedFileName {
    let title: String
    let year: Int?
    let season: Int?
    let episode: Int?
    let isTV: Bool

    var searchQuery: String {
        title.replacingOccurrences(of: ".", with: " ")
             .replacingOccurrences(of: "_", with: " ")
             .trimmingCharacters(in: .whitespaces)
    }
}

enum FileNameParser {
    // Common patterns:
    // Movie.Name.2024.1080p.BluRay.x264
    // Movie Name (2024)
    // Show.Name.S01E02.Episode.Title.720p
    // Show Name - S01E02
    // Show.Name.1x02

    private static let tvPatterns: [(pattern: String, seasonGroup: Int, episodeGroup: Int)] = [
        (#"[Ss](\d{1,2})[Ee](\d{1,3})"#, 1, 2),        // S01E02
        (#"(\d{1,2})[xX](\d{1,3})"#, 1, 2),             // 1x02
        (#"[Ss]eason\s*(\d{1,2}).*[Ee]pisode\s*(\d{1,3})"#, 1, 2),  // Season 1 Episode 2
        (#"\[(\d{1,2})x(\d{1,3})\]"#, 1, 2),             // [1x02]
    ]

    private static let yearPattern = #"\b((?:19|20)\d{2})\b"#

    private static let cleanupPatterns = [
        #"\b(720p|1080p|2160p|4K|UHD)\b"#,
        #"\b(BluRay|BDRip|BRRip|WEB-DL|WEBRip|HDTV|DVDRip|HDRip)\b"#,
        #"\b(x264|x265|H\.264|H\.265|HEVC|AVC|AAC|DTS|AC3|FLAC|Atmos)\b"#,
        #"\b(REMUX|PROPER|REPACK|EXTENDED|UNRATED|DIRECTORS\.CUT)\b"#,
        #"\[.*?\]"#,
        #"\((?!.*\d{4})[^)]*\)"#,
    ]

    static func parse(_ fileName: String) -> ParsedFileName {
        let name = (fileName as NSString).deletingPathExtension

        // Check for TV show patterns first
        for tvPattern in tvPatterns {
            if let regex = try? NSRegularExpression(pattern: tvPattern.pattern),
               let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {

                let seasonRange = Range(match.range(at: tvPattern.seasonGroup), in: name)
                let episodeRange = Range(match.range(at: tvPattern.episodeGroup), in: name)

                let season = seasonRange.flatMap { Int(name[$0]) }
                let episode = episodeRange.flatMap { Int(name[$0]) }

                let titleEnd = match.range.location
                let rawTitle = String(name.prefix(titleEnd))
                let title = cleanTitle(rawTitle)

                return ParsedFileName(
                    title: title,
                    year: extractYear(from: name),
                    season: season,
                    episode: episode,
                    isTV: true
                )
            }
        }

        // Movie pattern
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
            isTV: false
        )
    }

    private static func extractYear(from string: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: yearPattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
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

        // Remove trailing separators
        while title.hasSuffix("-") || title.hasSuffix(" ") {
            title = String(title.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return title
    }
}
