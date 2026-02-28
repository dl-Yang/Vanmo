import Foundation

final class VTTParser: SubtitleParser {
    func parse(data: Data, encoding: String.Encoding? = nil) throws -> [SubtitleCue] {
        guard let content = String(data: data, encoding: encoding ?? .utf8) else {
            throw SubtitleError.encodingDetectionFailed
        }
        return try parse(string: content)
    }

    func parse(string: String) throws -> [SubtitleCue] {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.hasPrefix("WEBVTT") else {
            throw SubtitleError.invalidFormat
        }

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks.dropFirst() {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }

            var timeLineIndex = 0
            for (i, line) in lines.enumerated() {
                if line.contains("-->") {
                    timeLineIndex = i
                    break
                }
            }

            guard timeLineIndex < lines.count,
                  let (start, end) = parseTimeLine(lines[timeLineIndex]) else { continue }

            let text = lines[(timeLineIndex + 1)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedText = stripTags(text)

            guard !cleanedText.isEmpty else { continue }

            cues.append(SubtitleCue(
                id: cues.count,
                startTime: start,
                endTime: end,
                text: cleanedText
            ))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    private func parseTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""

        guard let start = parseTime(startStr),
              let end = parseTime(endStr) else { return nil }
        return (start, end)
    }

    private func parseTime(_ string: String) -> TimeInterval? {
        let components = string.split(separator: ":")
        switch components.count {
        case 3:
            guard let h = Double(components[0]),
                  let m = Double(components[1]),
                  let s = Double(components[2]) else { return nil }
            return h * 3600 + m * 60 + s
        case 2:
            guard let m = Double(components[0]),
                  let s = Double(components[1]) else { return nil }
            return m * 60 + s
        default:
            return nil
        }
    }

    private func stripTags(_ string: String) -> String {
        string.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }
}
