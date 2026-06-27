import Foundation

enum SupportedFormat {
    case native
    case ffmpeg
    case discImage

    static func detect(from url: URL) -> SupportedFormat {
        if MediaFormatProbe.isDiscImage(url) {
            return .discImage
        }
        let ext = url.pathExtension.lowercased()
        if MediaFormatProbe.nativeVideoExtensions.contains(ext)
            || MediaFormatProbe.nativeAudioExtensions.contains(ext)
            // HLS（m3u8/m3u）由 AVFoundation 原生处理，直播自适应码率与稳定性更好。
            || MediaFormatProbe.playlistExtensions.contains(ext) {
            return .native
        }
        return .ffmpeg
    }
}

enum PlayerEngineFactory {

    static func engine(for url: URL) -> PlayerEngine {
        let ext = url.pathExtension.lowercased()
        let format = SupportedFormat.detect(from: url)
        VanmoLogger.player.info("[EngineFactory] URL: \(url.absoluteString), ext: \(ext), format: \(format.logName)")

        switch format {
        case .native:
            VanmoLogger.player.info("[EngineFactory] 选择 AVPlayerEngine (原生格式)")
            return AVPlayerEngine()
        case .ffmpeg:
            VanmoLogger.player.info("[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)")
            return KSPlayerEngine()
        case .discImage:
            VanmoLogger.player.info("[EngineFactory] 检测到原盘/ISO 候选，先交给 KSPlayerEngine PoC")
            return KSPlayerEngine()
        }
    }
}

private extension SupportedFormat {
    var logName: String {
        switch self {
        case .native: return "native"
        case .ffmpeg: return "ffmpeg"
        case .discImage: return "discImage"
        }
    }
}
