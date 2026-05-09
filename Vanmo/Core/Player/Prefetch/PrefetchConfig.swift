import Foundation

/// 本地 HTTP 代理预缓存配置（会话级临时缓存，退出播放即清理）。
enum PrefetchConfig {
    /// 单块大小（字节）
    /// 256KB 是综合考虑：
    /// - 单 chunk 下载耗时 ~400ms（vs 1MB 的 ~1.5-2s），首屏更快
    /// - 4 路并发可填满 ~10Mbps 带宽
    /// - 256K 也是 PrefetchSession 当前 yield 给 NW 的 slice 粒度，对齐
    static let chunkSize = 256 * 1024

    /// 主动预读窗口：当前 Range 结束后继续下载的字节数
    static let prefetchWindow = 32 * 1024 * 1024

    /// 内存中保留的最大缓存字节（超出部分 spill 到 tmp）
    static let maxMemoryCache = 64 * 1024 * 1024

    /// 同时回源的最大并发数（FetchLimiter 全局上限）
    /// 16 路：稳定阶段每 TCP ~232 KB/s × 16 ≈ 3.7 MB/s，足够覆盖 ~3.6 MB/s 视频码率。
    static let maxConcurrentFetches = 16

    /// tmp 根目录名（位于 temporaryDirectory 下）
    static let prefetchDirectoryName = "prefetch"

    /// 代理路径前缀
    static let streamPathPrefix = "/stream/"
}
