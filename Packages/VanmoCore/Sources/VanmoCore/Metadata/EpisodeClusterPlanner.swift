import Foundation

/// Groups same-folder videos that share a show title and episode naming pattern.
public enum EpisodeClusterPlanner {
    private struct ClusterKey: Hashable {
        let showTitle: String
        let kind: EpisodePatternKind
    }

    public static func refine(
        identifications: [String: MediaIdentificationResult],
        parsedNames: [String: ParsedFileName]
    ) -> [String: MediaIdentificationResult] {
        var grouped: [ClusterKey: [String]] = [:]

        for (fileName, parsed) in parsedNames {
            guard parsed.isTV,
                  parsed.episode != nil,
                  let kind = parsed.patternKind else {
                continue
            }
            let showTitle = normalizedShowTitle(parsed.title)
            guard !showTitle.isEmpty else { continue }
            grouped[ClusterKey(showTitle: showTitle, kind: kind), default: []].append(fileName)
        }

        var refined = identifications
        for (key, fileNames) in grouped {
            let episodeNumbers = Set(fileNames.compactMap { parsedNames[$0]?.episode })
            guard fileNames.count >= 2, episodeNumbers.count >= 2 else { continue }

            LibraryScanDebugLog.scan(
                "cluster show=\(key.showTitle) kind=\(key.kind.rawValue) files=\(fileNames.count) episodes=\(episodeNumbers.sorted().map(String.init).joined(separator: ","))"
            )

            for fileName in fileNames {
                guard var identification = refined[fileName],
                      let parsed = parsedNames[fileName],
                      let episode = parsed.episode else {
                    continue
                }
                identification = identification.clusteredEpisode(
                    showTitle: key.showTitle,
                    episode: episode,
                    season: parsed.season
                )
                refined[fileName] = identification
            }
        }

        return refined
    }

    public static func normalizedShowTitle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
