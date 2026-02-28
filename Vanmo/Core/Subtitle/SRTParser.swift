import Foundation

final class SRTParser: SubtitleParser {
    func parse(data: Data, encoding: String.Encoding? = nil) throws -> [SubtitleCue] {
        let detectedEncoding = encoding ?? detectEncoding(data)
        guard let content = String(data: data, encoding: detectedEncoding) else {
            throw SubtitleError.encodingDetectionFailed
        }
        return try parse(string: content)
    }

    func parse(string: String) throws -> [SubtitleCue] {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 3 else { continue }

            let timeLine: String
            let textStartIndex: Int

            if let _ = Int(lines[0].trimmingCharacters(in: .whitespaces)) {
                timeLine = lines[1]
                textStartIndex = 2
            } else if lines[0].contains("-->") {
                timeLine = lines[0]
                textStartIndex = 1
            } else {
                continue
            }

            guard let (start, end) = parseTimeLine(timeLine) else { continue }

            let text = lines[textStartIndex...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedText = stripHTMLTags(text)

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

    // MARK: - Private

    private func parseTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        guard let start = parseTime(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (start, end)
    }

    private func parseTime(_ string: String) -> TimeInterval? {
        let normalized = string.replacingOccurrences(of: ",", with: ".")
        let components = normalized.split(separator: ":")
        guard components.count == 3 else { return nil }

        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private func stripHTMLTags(_ string: String) -> String {
        string.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }

    private func detectEncoding(_ data: Data) -> String.Encoding {
        // BOM detection
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return .utf8
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return .utf16LittleEndian
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return .utf16BigEndian
        }

        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }

        // Fallback to common CJK encodings
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        let gbEncoding = String.Encoding(rawValue: cfEncoding)
        if String(data: data, encoding: gbEncoding) != nil {
            return gbEncoding
        }

        return .utf8
    }
}
