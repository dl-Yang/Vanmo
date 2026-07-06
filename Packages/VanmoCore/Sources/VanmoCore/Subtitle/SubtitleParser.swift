import Foundation

public protocol SubtitleParser {
    func parse(data: Data, encoding: String.Encoding?) throws -> [SubtitleCue]
}

public struct SubtitleCue: Identifiable, Equatable {
    public let id: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    public let attributedText: AttributedString?

    public init(id: Int, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.attributedText = try? AttributedString(markdown: text)
    }

    public func contains(time: TimeInterval) -> Bool {
        time >= startTime && time <= endTime
    }
}

public enum SubtitleError: LocalizedError {
    case invalidFormat
    case encodingDetectionFailed
    case parseError(String)
    case assRenderingUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "无效的字幕格式"
        case .encodingDetectionFailed: return "无法检测字幕编码"
        case .parseError(let msg): return "字幕解析错误: \(msg)"
        case .assRenderingUnavailable: return "ASS/SSA 特效字幕需要专用渲染引擎"
        }
    }
}

public enum SubtitleFormat: Equatable, Sendable {
    case srt
    case vtt
    case ass
    case unknown

    public var isRichTextFormat: Bool {
        self == .ass
    }

    public static func detect(from url: URL) -> SubtitleFormat {
        switch url.pathExtension.lowercased() {
        case "srt": return .srt
        case "vtt", "webvtt": return .vtt
        case "ass", "ssa": return .ass
        default: return .unknown
        }
    }

    public static func detect(from data: Data) -> SubtitleFormat {
        guard let header = String(data: data.prefix(50), encoding: .utf8) else {
            return .unknown
        }
        if header.contains("WEBVTT") { return .vtt }
        if header.contains("[Script Info]") { return .ass }
        if header.trimmingCharacters(in: .whitespacesAndNewlines).first?.isNumber == true {
            return .srt
        }
        return .unknown
    }
}
