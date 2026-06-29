import Foundation
import UniformTypeIdentifiers

/// 媒体格式探测的单一事实源：集中维护视频 / 音频 / 字幕 / 原盘扩展名，
/// 供媒体库扫描、远程浏览器、播放引擎选型统一调用，避免各处扩展名列表漂移。
enum MediaFormatProbe {
    /// AVFoundation 原生可直接播放的视频容器
    static let nativeVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// 需要 KSPlayer / FFmpeg 的视频容器
    static let ffmpegVideoExtensions: Set<String> = [
        "mkv", "avi", "wmv", "flv", "rmvb", "rm", "ts", "m2ts",
        "webm", "ogv", "3gp", "asf", "vob", "mpg", "mpeg"
    ]

    /// 原盘镜像 / ISO
    static let discImageExtensions: Set<String> = ["iso"]

    /// 蓝光原盘 playlist（BDMV）
    static let discPlaylistExtensions: Set<String> = ["mpls"]

    /// 直播 / 点播播放列表
    static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    /// AVFoundation 原生可直接播放的音频
    static let nativeAudioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "caf"]

    /// 媒体库 / 浏览器归类用的音频扩展名
    static let audioExtensions: Set<String> = ["mp3", "flac", "aac", "wav", "ogg", "m4a", "caf"]

    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup"]

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]

    /// 媒体库 / 浏览器视为「视频」的扩展名（含原盘镜像与播放列表）
    static var videoExtensions: Set<String> {
        nativeVideoExtensions
            .union(ffmpegVideoExtensions)
            .union(discImageExtensions)
            .union(discPlaylistExtensions)
            .union(playlistExtensions)
    }

    static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }
    static func isSubtitle(_ url: URL) -> Bool { subtitleExtensions.contains(url.pathExtension.lowercased()) }
    static func isAudio(_ url: URL) -> Bool { audioExtensions.contains(url.pathExtension.lowercased()) }
    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }

    /// 是否为蓝光原盘 / ISO 镜像 / BDMV 结构（路径含 /BDMV/ 或为 .mpls playlist）。
    static func isDiscImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if discImageExtensions.contains(ext) || discPlaylistExtensions.contains(ext) {
            return true
        }
        let uppercasedPath = url.path.uppercased()
        return uppercasedPath.contains("/BDMV/") || url.lastPathComponent.uppercased() == "BDMV"
    }
}

extension URL {
    var isVideoFile: Bool { MediaFormatProbe.isVideo(self) }

    var isSubtitleFile: Bool { MediaFormatProbe.isSubtitle(self) }

    var fileSizeString: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
