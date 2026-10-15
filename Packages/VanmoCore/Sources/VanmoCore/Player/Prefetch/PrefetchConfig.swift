import Foundation

/// 本地 HTTP 代理预缓存配置（会话级临时缓存，退出播放即清理）。
public enum PrefetchConfig {
    /// 单块大小（字节）
    /// 256KB 是综合考虑：
    /// - 单 chunk 下载耗时 ~400ms（vs 1MB 的 ~1.5-2s），首屏更快
    /// - 4 路并发可填满 ~10Mbps 带宽
    /// - 256K 也是 PrefetchSession 当前 yield 给 NW 的 slice 粒度，对齐
    public static let chunkSize = 256 * 1024

    /// 内存中保留的最大缓存字节（超出部分 spill 到 tmp）
    public static let maxMemoryCache = 64 * 1024 * 1024

    /// 同时回源的最大并发数（FetchLimiter 全局上限）
    /// 16 路：稳定阶段每 TCP ~232 KB/s × 16 ≈ 3.7 MB/s，足够覆盖 ~3.6 MB/s 视频码率。
    public static let maxConcurrentFetches = 16

    /// HTTP 默认保持已验证的 16 路吞吐。Debug 可用 4/8/16 做同源 A/B，
    /// 在真机证据支持前不改变 Release 的高码率兼容边界。
    public static var httpPipelineDepth: Int {
#if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["VANMO_PREFETCH_PIPELINE_DEPTH"],
           let value = Int(rawValue),
           [4, 8, 16].contains(value) {
            return value
        }
#endif
        return maxConcurrentFetches
    }

    /// 会话清理时等待片源关闭和在途读取的上限。SMB/FTP/SFTP 断连可能不响应取消。
    public static let cleanupDrainTimeout: Duration = .seconds(3)

    /// 从当前播放点向后预缓存的时间目标。
    public static let aheadTargetSeconds: TimeInterval = 180

    /// 续播和 seek 的关键帧在播放点之前。先缓存这一小段，避免解码追上时钟前一直黑屏。
    public static let lookbehindTargetSeconds: TimeInterval = 15

    /// 向前回看的字节上限。按片源平均码率换算，避免高码率把回看拉得太长。
    public static let maxLookbehindBytes: Int64 = 8 * 1024 * 1024

    /// 单个会话保留的预缓存字节上限。内存仍受 `maxMemoryCache` 约束，超出部分在 tmp。
    public static let maxSessionCacheBytes: Int64 = 256 * 1024 * 1024

    /// 用总长度和时长把「向后 180 秒」换成字节，并夹在单会话上限内。
    public static func aheadByteBudget(totalSize: Int64, duration: TimeInterval) -> Int64 {
        let cap = maxSessionCacheBytes
        guard totalSize > 0, duration > 0 else { return cap }
        let byTime = Int64((Double(totalSize) / duration) * aheadTargetSeconds)
        return max(Int64(chunkSize), min(cap, byTime))
    }

    /// 播放点之前要先备好的字节。没有时长时用上限，有时长时按平均码率取 15 秒。
    public static func lookbehindByteBudget(totalSize: Int64, duration: TimeInterval) -> Int64 {
        let cap = maxLookbehindBytes
        guard totalSize > 0, duration > 0 else { return cap }
        let byTime = Int64((Double(totalSize) / duration) * lookbehindTargetSeconds)
        return max(Int64(chunkSize), min(cap, byTime))
    }

    /// tmp 根目录名（位于 temporaryDirectory 下）
    public static let prefetchDirectoryName = "prefetch"

    /// 代理路径前缀
    public static let streamPathPrefix = "/stream/"

    /// 本地 prefetch 代理 URL（`http://127.0.0.1:<port>/stream/<token>`）。
    public static func isProxyURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        guard url.host == "127.0.0.1" || url.host?.lowercased() == "localhost" else { return false }
        return url.path.hasPrefix(streamPathPrefix)
    }

    /// Emby / Jellyfin `/Videos/.../stream` 与 Plex 转码地址。渐进直链走 localhost
    /// 文件预取；`.m3u8` 播放列表仍直连，因为代理只按字节区间缓存单个文件。
    public static func isMediaServerStreamURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/videos/"), path.contains("/stream") || path.contains("/master.m3u8") {
            return true
        }
        return path.contains("/transcode/universal/start.m3u8")
    }

    /// 媒体服务器的 HLS 播放列表不进入文件预取。`/Videos/.../stream` 与 Plex part 直链返回 false。
    public static func isMediaServerPlaylist(_ url: URL) -> Bool {
        isMediaServerStreamURL(url) && url.path.lowercased().contains(".m3u8")
    }

    /// Prefetch 二次 GET 会掐掉第一条 body；Emby/Jellyfin 直连上
    /// `isSecondOpen` 也会对 4K 再打一轮探测，拖长首帧。
    public static func shouldDisableSecondOpen(for url: URL) -> Bool {
        isProxyURL(url) || isMediaServerStreamURL(url)
    }
}

/// 续播 seek 完成前，引擎会先把播放头报成 0。这段时间用预定起点，避免向前填充从文件头开始。
public enum PrefetchResumePlayhead {
    public static func resolve(
        reported: TimeInterval,
        pendingStart: TimeInterval?
    ) -> (time: TimeInterval, pendingStart: TimeInterval?) {
        guard let pending = pendingStart, pending > 1 else {
            return (reported, pendingStart)
        }
        if reported < 1 {
            return (pending, pending)
        }
        return (reported, nil)
    }
}

/// 进度条上的本地缓存区间，按成片时长的比例表示，不是加载百分比。
public struct MediaCacheSpan: Sendable, Equatable {
    public var startFraction: Double
    public var endFraction: Double

    public static let empty = MediaCacheSpan(startFraction: 0, endFraction: 0)

    public init(startFraction: Double, endFraction: Double) {
        self.startFraction = startFraction
        self.endFraction = endFraction
    }
}
