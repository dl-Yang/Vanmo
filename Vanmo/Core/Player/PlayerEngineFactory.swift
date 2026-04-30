import Foundation

enum SupportedFormat {
    case native
    case ffmpeg

    static let nativeExtensions: Set<String> = ["mp4", "mov", "m4v", "mp3", "m4a", "aac", "wav", "caf"]

    static let ffmpegExtensions: Set<String> = [
        "mkv", "avi", "wmv", "flv", "rmvb", "rm", "ts", "m2ts",
        "webm", "ogv", "3gp", "asf", "vob", "mpg", "mpeg"
    ]

    static func detect(from url: URL) -> SupportedFormat {
        let ext = url.pathExtension.lowercased()
        if nativeExtensions.contains(ext) {
            return .native
        }
        return .ffmpeg
    }
}

enum PlayerEngineFactory {

    static func engine(for url: URL) -> PlayerEngine {
        let ext = url.pathExtension.lowercased()
        let format = SupportedFormat.detect(from: url)
        VanmoLogger.player.info("[EngineFactory] URL: \(url.absoluteString), ext: \(ext), format: \(format == .native ? "native" : "ffmpeg")")

        switch format {
        case .native:
            VanmoLogger.player.info("[EngineFactory] 选择 AVPlayerEngine (原生格式)")
            return AVPlayerEngine()
        case .ffmpeg:
            VanmoLogger.player.info("[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)")
            return KSPlayerEngine()
        }
    }
}
