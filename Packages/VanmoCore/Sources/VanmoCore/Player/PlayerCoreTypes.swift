import Foundation
import CoreMedia

public enum PlaybackState: Equatable {
    case idle, loading, playing, paused, buffering, error(String), ended
    public var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering: return true
        default: return false
        }
    }
}

public enum VideoScaleMode: String, CaseIterable, Sendable {
    case fit, fill, stretch
    public var displayName: String {
        switch self {
        case .fit: return "适应"
        case .fill: return "填充"
        case .stretch: return "拉伸"
        }
    }
    public var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.up.left"
        case .stretch: return "rectangle.expand.vertical"
        }
    }
}

public struct PlayerConfig: Sendable {
    public var playbackRate: Float = 1.0
    public var scaleMode: VideoScaleMode = .fit
    public var selectedAudioTrack: Int = 0
    public var selectedSubtitleTrack: Int? = nil
    public var subtitleDelay: TimeInterval = 0
    public var brightness: Float? = nil
    public var volume: Float = 1.0
    public var isMuted: Bool = false
    public static let minimumRate: Float = 0.5
    public static let maximumRate: Float = 2.0
    public static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    public static func clampedRate(_ rate: Float) -> Float { max(minimumRate, min(maximumRate, rate)) }
    public init() {}
}

public enum PlaybackPreferences {
    public static let hardwareDecodingKey = "playback.hardwareDecoding"
    public static let audioOutputModeKey = "audio.outputMode"
    public static var hardwareDecodingEnabled: Bool {
        UserDefaults.standard.object(forKey: hardwareDecodingKey) as? Bool ?? true
    }
}

public enum AudioOutputMode: String, CaseIterable, Sendable {
    case auto, stereo, surround
    public var displayName: String {
        switch self {
        case .auto: return "自动"
        case .stereo: return "立体声"
        case .surround: return "环绕声 / 空间音频"
        }
    }
    public var icon: String {
        switch self {
        case .auto: return "waveform"
        case .stereo: return "speaker.wave.2"
        case .surround: return "hifispeaker.2"
        }
    }
    public static var current: AudioOutputMode {
        AudioOutputMode(rawValue: UserDefaults.standard.string(forKey: PlaybackPreferences.audioOutputModeKey) ?? "auto") ?? .auto
    }
}

public struct Chapter: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let startTime: CMTime
    public let endTime: CMTime
    public init(id: Int, title: String, startTime: CMTime, endTime: CMTime) {
        self.id = id; self.title = title; self.startTime = startTime; self.endTime = endTime
    }
    public var displayTime: String {
        let seconds = startTime.seconds
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let hours = mins / 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, mins % 60, secs) }
        return String(format: "%d:%02d", mins, secs)
    }
}

public enum SupportedFormat: Sendable {
    case native, ffmpeg, discImage
    public static func detect(from url: URL) -> SupportedFormat {
        if MediaFormatProbe.isDiscImage(url) { return .discImage }
        let ext = url.pathExtension.lowercased()
        if MediaFormatProbe.nativeVideoExtensions.contains(ext)
            || MediaFormatProbe.nativeAudioExtensions.contains(ext)
            || MediaFormatProbe.playlistExtensions.contains(ext) { return .native }
        return .ffmpeg
    }
}
