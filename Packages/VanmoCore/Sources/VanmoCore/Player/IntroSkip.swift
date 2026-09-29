import CoreMedia
import Foundation

public struct IntroSkipWindow: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }

    public func contains(_ time: TimeInterval, remainingGrace: TimeInterval = 2) -> Bool {
        time >= start && time < end && (end - time) > remainingGrace
    }
}

public enum IntroSkipResolver: Sendable {
    public static func window(
        chapters: [Chapter],
        serverWindow: IntroSkipWindow?,
        manualEnd: TimeInterval?
    ) -> IntroSkipWindow? {
        if let manualEnd, manualEnd > 1 {
            return IntroSkipWindow(start: 0, end: manualEnd)
        }
        if let serverWindow, serverWindow.end > serverWindow.start + 1 {
            return serverWindow
        }
        return window(from: chapters)
    }

    public static func window(from chapters: [Chapter]) -> IntroSkipWindow? {
        guard let chapter = chapters.first(where: { isIntroChapterTitle($0.title) }) else {
            return nil
        }
        let start = chapter.startTime.seconds
        let end = chapter.endTime.seconds
        guard end.isFinite, start.isFinite, end > start + 1 else { return nil }
        return IntroSkipWindow(start: start, end: end)
    }

    public static func isIntroChapterTitle(_ title: String) -> Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized == "op" || normalized.hasPrefix("op ") || normalized.hasPrefix("op:") {
            return true
        }
        if normalized.contains("片头") {
            return true
        }
        if normalized.contains("opening") || normalized.contains("intro") {
            return true
        }
        return false
    }
}

public enum IntroSkipStore: Sendable {
    public static let storageKey = "playback.introSkipEnds"

    public static func mediaKey(for item: MediaItem) -> String {
        CloudMediaStateStore.mediaKey(for: item)
    }

    public static func manualEnd(for mediaKey: String) -> TimeInterval? {
        let values = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double]
        guard let end = values?[mediaKey], end > 1 else { return nil }
        return end
    }

    public static func save(manualEnd: TimeInterval, for mediaKey: String) {
        var values = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        values[mediaKey] = manualEnd
        UserDefaults.standard.set(values, forKey: storageKey)
    }

    public static func remove(for mediaKey: String) {
        var values = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        values.removeValue(forKey: mediaKey)
        UserDefaults.standard.set(values, forKey: storageKey)
    }
}

public enum IntroMarkerParser: Sendable {
    public static func embyWindow(from data: Data) throws -> IntroSkipWindow? {
        let detail = try JSONDecoder().decode(EmbyChapterPayload.self, from: data)
        let raw = detail.chapters ?? []
        let chapters = raw.enumerated().compactMap { index, item -> Chapter? in
            item.chapter(endTicks: raw.dropFirst(index + 1).first?.startPositionTicks)
        }
        if let marked = raw.enumerated().first(where: { $0.element.isIntroMarker }) {
            if let chapter = marked.element.chapter(
                endTicks: raw.dropFirst(marked.offset + 1).first?.startPositionTicks
            ) {
                return IntroSkipWindow(start: chapter.startTime.seconds, end: chapter.endTime.seconds)
            }
        }
        return IntroSkipResolver.window(from: chapters)
    }

    public static func plexWindow(from data: Data) throws -> IntroSkipWindow? {
        let container = try JSONDecoder().decode(PlexMarkerPayload.self, from: data)
        let markers = container.mediaContainer.metadata?.first?.markers ?? []
        guard let intro = markers.first(where: { $0.isIntro }) else { return nil }
        return intro.window
    }
}

private struct EmbyChapterPayload: Decodable {
    let chapters: [EmbyChapter]?

    enum CodingKeys: String, CodingKey {
        case chapters = "Chapters"
    }
}

private struct EmbyChapter: Decodable {
    let startPositionTicks: Int64?
    let name: String?
    let markerType: String?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case markerType = "MarkerType"
    }

    var isIntroMarker: Bool {
        let marker = markerType?.lowercased() ?? ""
        if marker.contains("intro") { return true }
        return IntroSkipResolver.isIntroChapterTitle(name ?? "")
    }

    func chapter(endTicks: Int64?) -> Chapter? {
        guard let name, let startTicks = startPositionTicks else { return nil }
        let start = Double(startTicks) / 10_000_000
        let end: TimeInterval
        if let endTicks {
            end = Double(endTicks) / 10_000_000
        } else {
            end = start + 90
        }
        return Chapter(
            id: Int(abs(startTicks % 1_000_000)),
            title: name,
            startTime: CMTime(seconds: start, preferredTimescale: 600),
            endTime: CMTime(seconds: max(end, start + 1), preferredTimescale: 600)
        )
    }
}

private struct PlexMarkerPayload: Decodable {
    let mediaContainer: PlexMarkerContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct PlexMarkerContainer: Decodable {
    let metadata: [PlexMarkerMetadata]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

private struct PlexMarkerMetadata: Decodable {
    let markers: [PlexMarker]?

    enum CodingKeys: String, CodingKey {
        case markers = "Marker"
    }
}

private struct PlexMarker: Decodable {
    let type: String?
    let startTimeOffset: Int?
    let endTimeOffset: Int?

    var isIntro: Bool {
        (type ?? "").lowercased() == "intro"
    }

    var window: IntroSkipWindow? {
        guard let startMs = startTimeOffset, let endMs = endTimeOffset else { return nil }
        let start = Double(startMs) / 1000
        let end = Double(endMs) / 1000
        guard end > start + 1 else { return nil }
        return IntroSkipWindow(start: start, end: end)
    }
}
