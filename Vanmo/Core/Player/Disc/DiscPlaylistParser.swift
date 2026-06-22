import Foundation
import CoreMedia

/// 原盘 / 蓝光结构类型。
enum DiscStructureKind: Equatable {
    /// `.iso` 镜像文件
    case isoImage
    /// 已解包的 BDMV 目录结构
    case bdmvFolder
    case unknown
}

/// 单个原盘 playlist（蓝光 `.mpls`）。
struct DiscPlaylist: Identifiable, Equatable {
    /// playlist 标识，如 `00800.mpls`
    let id: String
    let title: String?
    let duration: TimeInterval
    let chapters: [DiscChapter]
    let audioTracks: [DiscTrackRef]
    let subtitleTracks: [DiscTrackRef]
    /// 按播放顺序引用的媒体流片段（m2ts）。
    let segments: [DiscSegmentRef]
}

struct DiscChapter: Equatable {
    let index: Int
    let startTime: TimeInterval
}

struct DiscTrackRef: Equatable {
    let id: Int
    let language: String?
    let codec: String?
}

struct DiscSegmentRef: Equatable {
    /// 片段在原盘内的相对路径（如 `BDMV/STREAM/00801.m2ts`）。
    let relativePath: String
    let duration: TimeInterval
}

/// 解析得到的原盘结构。
struct DiscStructure: Equatable {
    let kind: DiscStructureKind
    /// 推荐主片（通常为时长最长的 playlist）。
    let mainPlaylist: DiscPlaylist?
    let playlists: [DiscPlaylist]
}

enum DiscParsingError: LocalizedError {
    case notImplemented
    case unsupportedStructure
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "原盘解析尚未实现"
        case .unsupportedStructure: return "不支持的原盘结构"
        case .unreadable(let detail): return "无法读取原盘: \(detail)"
        }
    }
}

/// 原盘结构解析层抽象。后续可由 libbluray 封装或自研 `.mpls` 解析实现。
///
/// 设计目标（详见 `doc/disc-playlist-parsing-design.md`）：
/// - 识别 ISO 镜像与 BDMV 目录结构；
/// - 解析 `.mpls` 并选出主片（playlist 选择）；
/// - 映射章节 / 音轨 / 字幕；
/// - 支持远程 Range 读取（边读边解，无需整盘下载）。
protocol DiscStructureParsing {
    /// 探测给定 URL 是否为可识别的原盘结构。
    func detectStructureKind(at url: URL) -> DiscStructureKind

    /// 解析原盘结构与可播放 playlist 列表。
    func parseStructure(at url: URL) async throws -> DiscStructure
}

/// 主片选择策略。
protocol DiscPlaylistSelecting {
    func selectMainPlaylist(from structure: DiscStructure) -> DiscPlaylist?
}

/// 占位实现：仅按现有启发式识别结构种类，真正的 playlist 解析留待 P1 落地。
struct PlaceholderDiscParser: DiscStructureParsing, DiscPlaylistSelecting {
    func detectStructureKind(at url: URL) -> DiscStructureKind {
        if url.pathExtension.lowercased() == "iso" {
            return .isoImage
        }
        if url.path.uppercased().contains("/BDMV/") {
            return .bdmvFolder
        }
        return .unknown
    }

    func parseStructure(at url: URL) async throws -> DiscStructure {
        // TODO(P1): 接入 .mpls 解析 / libbluray，返回真实 playlist 列表与片段映射。
        throw DiscParsingError.notImplemented
    }

    /// 默认主片选择：取时长最长的 playlist（蓝光主电影通常最长）。
    func selectMainPlaylist(from structure: DiscStructure) -> DiscPlaylist? {
        structure.playlists.max(by: { $0.duration < $1.duration })
    }
}
