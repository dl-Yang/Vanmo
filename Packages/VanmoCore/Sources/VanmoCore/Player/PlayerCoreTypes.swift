import CoreGraphics
import CoreMedia
import Foundation

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
        case .fit: return L10n.tr("适应")
        case .fill: return L10n.tr("填充")
        case .stretch: return L10n.tr("拉伸")
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

public enum PlaybackVideoQuality: String, CaseIterable, Sendable {
    case p360
    case p480
    case p720
    case p1080
    case original

    public var displayName: String {
        switch self {
        case .p360: return "360p"
        case .p480: return "480p"
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .original: return L10n.tr("原画")
        }
    }

    public var maxHeight: Int? {
        switch self {
        case .p360: return 360
        case .p480: return 480
        case .p720: return 720
        case .p1080: return 1080
        case .original: return nil
        }
    }

    public var ffmpegScaleFilter: String? {
        guard let maxHeight else { return nil }
        return "scale=-2:\(maxHeight)"
    }

    public var preferredMaximumResolution: CGSize? {
        guard let maxHeight else { return nil }
        return CGSize(width: (maxHeight * 16) / 9, height: maxHeight)
    }

    public var preferredPeakBitRate: Double? {
        switch self {
        case .p360: return 1_000_000
        case .p480: return 2_500_000
        case .p720: return 5_000_000
        case .p1080: return 8_000_000
        case .original: return nil
        }
    }

    public func isAvailable(sourceHeight: Int?) -> Bool {
        guard let maxHeight, let sourceHeight, sourceHeight > 0 else { return true }
        return sourceHeight >= maxHeight
    }

    public static func resolved(
        requested: PlaybackVideoQuality,
        sourceHeight: Int?
    ) -> PlaybackVideoQuality {
        guard !requested.isAvailable(sourceHeight: sourceHeight) else { return requested }
        return .original
    }
}

public enum PlaybackPreferences {
    public static let hardwareDecodingKey = "playback.hardwareDecoding"
    public static let audioOutputModeKey = "audio.outputMode"
    public static let videoQualityKey = "playback.videoQuality"
    public static var hardwareDecodingEnabled: Bool {
        UserDefaults.standard.object(forKey: hardwareDecodingKey) as? Bool ?? true
    }
    public static var videoQuality: PlaybackVideoQuality {
        get {
            let raw = UserDefaults.standard.string(forKey: videoQualityKey) ?? PlaybackVideoQuality.original.rawValue
            return PlaybackVideoQuality(rawValue: raw) ?? .original
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: videoQualityKey)
        }
    }

#if DEBUG
    public enum DebugNativeVideoEngine: String {
        case avFoundation = "av"
    }

    public static var debugNativeVideoEngine: DebugNativeVideoEngine? {
        guard let value = ProcessInfo.processInfo.environment["VANMO_NATIVE_VIDEO_ENGINE"]?.lowercased() else {
            return nil
        }
        return DebugNativeVideoEngine(rawValue: value)
    }
#endif
}

public final class PlaybackSeekCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    public func installTimeout(_ task: Task<Void, Never>) {
        lock.lock()
        let isCompleted = continuation == nil
        if !isCompleted {
            timeoutTask = task
        }
        lock.unlock()

        if isCompleted {
            task.cancel()
        }
    }

    @discardableResult
    public func resume() -> Bool {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let timeoutTask = timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        guard let continuation else { return false }
        timeoutTask?.cancel()
        continuation.resume()
        return true
    }
}

public enum AudioOutputMode: String, CaseIterable, Sendable {
    case auto, stereo, surround
    public var displayName: String {
        switch self {
        case .auto: return L10n.tr("自动")
        case .stereo: return L10n.tr("立体声")
        case .surround: return L10n.tr("环绕声 / 空间音频")
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
        if url.usesSMBScheme || url.usesFTPScheme || url.usesSFTPScheme { return .ffmpeg }
        if MediaFormatProbe.isDiscImage(url) { return .discImage }
        let ext = url.pathExtension.lowercased()
        if MediaFormatProbe.nativeVideoExtensions.contains(ext)
            || MediaFormatProbe.nativeAudioExtensions.contains(ext)
            || MediaFormatProbe.playlistExtensions.contains(ext) { return .native }
        return .ffmpeg
    }

    /// 本地下载和远程 HTTP remux（常见 HEVC/HDR 封进 `.mp4`）在 AVPlayer 上会 Cannot Open。
    /// HLS 播放列表仍留给 AVPlayer。
    public static func prefersKSPlayer(for url: URL) -> Bool {
        if detect(from: url) == .ffmpeg { return true }
        let ext = url.pathExtension.lowercased()
        return MediaFormatProbe.nativeVideoExtensions.contains(ext)
    }
}

public extension URL {
    var usesSMBScheme: Bool {
        scheme?.lowercased() == "smb"
    }

    var usesFTPScheme: Bool {
        scheme?.lowercased() == "ftp"
    }

    var usesSFTPScheme: Bool {
        scheme?.lowercased() == "sftp"
    }

    /// Host and path only. Never include userinfo.
    var safePlaybackLogDescription: String {
        if isFileURL {
            return "file://\(lastPathComponent)"
        }
        let scheme = scheme ?? ""
        let host = host ?? ""
        let port = port.map { ":\($0)" } ?? ""
        let path = path.isEmpty ? "/" : path
        return "\(scheme)://\(host)\(port)\(path)"
    }
}
