import Foundation
import VanmoCore

enum MacPlayerEngineKind: Sendable {
    case avFoundation
    case ksPlayer
    case unsupportedDisc
}

enum MacPlayerEngineFactory {
    static func engineKind(for url: URL) -> MacPlayerEngineKind {
        let format = SupportedFormat.detect(from: url)
        VanmoLogger.player.info(
            "[MacEngineFactory] URL: \(url.safePlaybackLogDescription), ext: \(url.pathExtension.lowercased()), format: \(format.logName)"
        )

        if format == .discImage {
            VanmoLogger.player.info("[MacEngineFactory] 检测到原盘/ISO，当前 macOS 公开路径不支持")
            return .unsupportedDisc
        }

        if SupportedFormat.prefersKSPlayer(for: url) {
            VanmoLogger.player.info("[MacEngineFactory] 选择 MacKSPlayerEngine (KSPlayer/FFmpeg)")
            return .ksPlayer
        }

        VanmoLogger.player.info("[MacEngineFactory] 选择 AVPlayer (原生格式)")
        return .avFoundation
    }
}

enum MacPlayerPlaybackError: LocalizedError {
    case unsupportedDiscFormat
    case fileNotAccessible(String)
    case ffmpegLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDiscFormat:
            return """
            当前 macOS 版本暂不支持蓝光原盘/ISO 完整播放。
            请尝试直接播放 BDMV/STREAM 内的 .m2ts 文件，或使用专用原盘播放工具。
            """
        case .fileNotAccessible(let message):
            return message
        case .ffmpegLoadFailed(let message):
            return "该格式需要 FFmpeg 解码，但当前 macOS KSPlayer 加载失败：\(message)"
        }
    }
}

private extension URL {
    var safePlaybackLogDescription: String {
        if isFileURL {
            return "file://\(lastPathComponent)"
        }
        let host = host ?? ""
        let path = path.isEmpty ? "/" : path
        return "\(scheme ?? "")://\(host)\(path)"
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
