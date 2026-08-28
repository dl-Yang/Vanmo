import Foundation
import VanmoCore

enum PlayerEngineFactory {
    static func engine(for url: URL) -> PlayerEngine {
        let ext = url.pathExtension.lowercased()
        let format = SupportedFormat.detect(from: url)
        VanmoLogger.player.info("[EngineFactory] URL: \(url.safePlaybackLogDescription), ext: \(ext), format: \(format.logName)")

        // Downloaded Emby/HTTP remuxes are often HEVC/HDR inside .mp4. AVPlayer
        // treats .mp4 as native and fails on Simulator (and some device profiles).
        if url.isFileURL, format != .discImage {
            VanmoLogger.player.info("[EngineFactory] 选择 KSPlayerEngine (本地文件)")
            return KSPlayerEngine()
        }

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
