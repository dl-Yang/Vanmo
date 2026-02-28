import Foundation
import Combine

actor SubtitleManager {
    private var cues: [SubtitleCue] = []
    private var delay: TimeInterval = 0

    func load(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let format = SubtitleFormat.detect(from: url)

        let parser: SubtitleParser
        switch format {
        case .srt:
            parser = SRTParser()
        case .vtt:
            parser = VTTParser()
        case .ass:
            parser = SRTParser() // Fallback; full ASS parser would be separate
        case .unknown:
            let detected = SubtitleFormat.detect(from: data)
            switch detected {
            case .srt: parser = SRTParser()
            case .vtt: parser = VTTParser()
            default: throw SubtitleError.invalidFormat
            }
        }

        cues = try parser.parse(data: data, encoding: nil)
        VanmoLogger.subtitle.info("Loaded \(self.cues.count) subtitle cues")
    }

    func load(from data: Data, format: SubtitleFormat) throws {
        let parser: SubtitleParser
        switch format {
        case .srt: parser = SRTParser()
        case .vtt: parser = VTTParser()
        default: throw SubtitleError.invalidFormat
        }
        cues = try parser.parse(data: data, encoding: nil)
    }

    func cue(at time: TimeInterval) -> SubtitleCue? {
        let adjustedTime = time + delay
        return binarySearch(for: adjustedTime)
    }

    func setDelay(_ newDelay: TimeInterval) {
        delay = newDelay
    }

    func clear() {
        cues = []
        delay = 0
    }

    // Binary search for performance with large subtitle files
    private func binarySearch(for time: TimeInterval) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }

        var low = 0
        var high = cues.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]

            if cue.contains(time: time) {
                return cue
            } else if time < cue.startTime {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return nil
    }

    // Find matching subtitle files in the same directory as the video
    static func findSubtitleFiles(for videoURL: URL) -> [URL] {
        let directory = videoURL.deletingLastPathComponent()
        let videoName = videoURL.deletingPathExtension().lastPathComponent

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.filter { url in
            guard url.isSubtitleFile else { return false }
            let subtitleName = url.deletingPathExtension().lastPathComponent
            return subtitleName.hasPrefix(videoName)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
