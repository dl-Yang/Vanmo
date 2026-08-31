import Foundation
import VanmoCore

enum PlayerEngineFactory {
    static func engine(for url: URL) -> PlayerEngine {
        let ext = url.pathExtension.lowercased()
        let format = SupportedFormat.detect(from: url)
        VanmoLogger.player.info("[EngineFactory] URL: \(url.safePlaybackLogDescription), ext: \(ext), format: \(format.logName)")

        if format == .discImage {
            VanmoLogger.player.info("[EngineFactory] 检测到原盘/ISO 候选，先交给 KSPlayerEngine PoC")
            return KSPlayerEngine()
        }

        // Local downloads and remote HTTP remuxes in .mp4/.mov often fail in
        // AVPlayer on Simulator and some device profiles. HLS stays native.
        if SupportedFormat.prefersKSPlayer(for: url) {
            VanmoLogger.player.info("[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)")
            return KSPlayerEngine()
        }

        VanmoLogger.player.info("[EngineFactory] 选择 AVPlayerEngine (原生格式)")
        return AVPlayerEngine()
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
