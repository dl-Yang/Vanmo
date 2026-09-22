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

    /// Emby / Jellyfin 已提供可用的 HTTP Range 直链。再套一层 localhost
    /// prefetch 会把首包截成数 KB，4K 首帧出不来。
    public static func isMediaServerStreamURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        guard path.contains("/videos/") else { return false }
        return path.contains("/stream")
    }

    /// Prefetch 二次 GET 会掐掉第一条 body；Emby/Jellyfin 直连上
    /// `isSecondOpen` 也会对 4K 再打一轮探测，拖长首帧。
    public static func shouldDisableSecondOpen(for url: URL) -> Bool {
        isProxyURL(url) || isMediaServerStreamURL(url)
    }
}
