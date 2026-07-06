import Foundation
import CoreMedia

/// 原盘 / 蓝光结构类型。
public enum DiscStructureKind: Equatable {
    /// `.iso` 镜像文件
    case isoImage
    /// 已解包的 BDMV 目录结构
    case bdmvFolder
    case unknown
}

/// 单个原盘 playlist（蓝光 `.mpls`）。
public struct DiscPlaylist: Identifiable, Equatable {
    /// playlist 标识，如 `00800.mpls`
    public let id: String
    public let title: String?
    public let duration: TimeInterval
    public let chapters: [DiscChapter]
    public let audioTracks: [DiscTrackRef]
    public let subtitleTracks: [DiscTrackRef]
    /// 按播放顺序引用的媒体流片段（m2ts）。
    public let segments: [DiscSegmentRef]
}

public struct DiscChapter: Equatable {
    public let index: Int
    public let startTime: TimeInterval
}

public struct DiscTrackRef: Equatable {
    public let id: Int
    public let language: String?
    public let codec: String?
}

public struct DiscSegmentRef: Equatable {
    /// 片段在原盘内的相对路径（如 `BDMV/STREAM/00801.m2ts`）。
    public let relativePath: String
    public let duration: TimeInterval
}

/// 解析得到的原盘结构。
public struct DiscStructure: Equatable {
    public let kind: DiscStructureKind
    /// 推荐主片（通常为时长最长的 playlist）。
    public let mainPlaylist: DiscPlaylist?
    public let playlists: [DiscPlaylist]
}

public enum DiscParsingError: LocalizedError {
    case notImplemented
    case unsupportedStructure
    case unreadable(String)

    public var errorDescription: String? {
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
public protocol DiscStructureParsing {
    /// 探测给定 URL 是否为可识别的原盘结构。
    func detectStructureKind(at url: URL) -> DiscStructureKind

    /// 解析原盘结构与可播放 playlist 列表。
    func parseStructure(at url: URL) async throws -> DiscStructure
}

/// 主片选择策略。
public protocol DiscPlaylistSelecting {
    func selectMainPlaylist(from structure: DiscStructure) -> DiscPlaylist?
}

/// 占位实现：仅按现有启发式识别结构种类，真正的 playlist 解析留待 P1 落地。
public struct PlaceholderDiscParser: DiscStructureParsing, DiscPlaylistSelecting {
    public func detectStructureKind(at url: URL) -> DiscStructureKind {
        if url.pathExtension.lowercased() == "iso" {
            return .isoImage
        }
        if url.path.uppercased().contains("/BDMV/") {
            return .bdmvFolder
        }
        return .unknown
    }

    public func parseStructure(at url: URL) async throws -> DiscStructure {
        // TODO(P1): 接入 .mpls 解析 / libbluray，返回真实 playlist 列表与片段映射。
        throw DiscParsingError.notImplemented
    }

    /// 默认主片选择：取时长最长的 playlist（蓝光主电影通常最长）。
    public func selectMainPlaylist(from structure: DiscStructure) -> DiscPlaylist? {
        structure.playlists.max(by: { $0.duration < $1.duration })
    }
}

public struct BDMVPlaylistParser: DiscStructureParsing, DiscPlaylistSelecting {
    public init() {}

    public func detectStructureKind(at url: URL) -> DiscStructureKind {
        if url.pathExtension.lowercased() == "iso" {
            return .isoImage
        }
        if bdmvRoot(for: url) != nil {
            return .bdmvFolder
        }
        return .unknown
    }

    public func parseStructure(at url: URL) async throws -> DiscStructure {
        let kind = detectStructureKind(at: url)
        guard kind != .isoImage else { throw DiscParsingError.unsupportedStructure }
        guard kind == .bdmvFolder, let root = bdmvRoot(for: url) else {
            throw DiscParsingError.unsupportedStructure
        }

        let playlistURLs = try playlistURLs(for: url, bdmvRoot: root)
        let playlists = try playlistURLs.compactMap { playlistURL in
            try parsePlaylist(at: playlistURL)
        }
        guard !playlists.isEmpty else {
            throw DiscParsingError.unreadable("未找到可播放 playlist")
        }

        return DiscStructure(
            kind: .bdmvFolder,
            mainPlaylist: selectMainPlaylist(from: DiscStructure(kind: .bdmvFolder, mainPlaylist: nil, playlists: playlists)),
            playlists: playlists
        )
    }

    public func selectMainPlaylist(from structure: DiscStructure) -> DiscPlaylist? {
        structure.playlists.max(by: { $0.duration < $1.duration })
    }

    private func playlistURLs(for url: URL, bdmvRoot: URL) throws -> [URL] {
        if url.pathExtension.lowercased() == "mpls" {
            return [url]
        }

        let playlistDirectory = bdmvRoot.appendingPathComponent("PLAYLIST", isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: playlistDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension.lowercased() == "mpls" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func parsePlaylist(at url: URL) throws -> DiscPlaylist? {
        let data = try Data(contentsOf: url)
        var reader = DiscBinaryReader(data: data)
        guard reader.readString(length: 4, at: 0) == "MPLS" else {
            throw DiscParsingError.unreadable("无效 MPLS: \(url.lastPathComponent)")
        }

        let playlistStart = Int(reader.readUInt32(at: 8))
        let markStart = Int(reader.readUInt32(at: 12))
        guard playlistStart > 0, playlistStart < data.count else {
            throw DiscParsingError.unreadable("MPLS 缺少 PlayList 段: \(url.lastPathComponent)")
        }

        reader.offset = playlistStart + 6
        let itemCount = Int(reader.readUInt16())
        _ = reader.readUInt16() // sub path count

        var segments: [DiscSegmentRef] = []
        var itemRanges: [(start: TimeInterval, inTime: UInt32, outTime: UInt32)] = []
        var timelineStart: TimeInterval = 0

        for _ in 0..<itemCount {
            let itemStart = reader.offset
            let itemLength = Int(reader.readUInt16())
            let itemEnd = itemStart + 2 + itemLength
            guard itemEnd <= data.count, itemLength >= 20 else {
                throw DiscParsingError.unreadable("MPLS PlayItem 越界: \(url.lastPathComponent)")
            }

            let clipID = reader.readString(length: 5)
            _ = reader.readString(length: 4) // codec identifier, usually M2TS
            _ = reader.readUInt8() // connection condition and angle flags
            _ = reader.readUInt8() // ref_to_STC_id
            let inTime = reader.readUInt32()
            let outTime = reader.readUInt32()
            let duration = max(0, TimeInterval(Int64(outTime) - Int64(inTime)) / 45_000.0)

            segments.append(
                DiscSegmentRef(
                    relativePath: "BDMV/STREAM/\(clipID).m2ts",
                    duration: duration
                )
            )
            itemRanges.append((timelineStart, inTime, outTime))
            timelineStart += duration
            reader.offset = itemEnd
        }

        guard !segments.isEmpty else { return nil }
        let chapters = parseChapters(
            data: data,
            markStart: markStart,
            itemRanges: itemRanges
        )

        return DiscPlaylist(
            id: url.lastPathComponent,
            title: url.deletingPathExtension().lastPathComponent,
            duration: segments.reduce(0) { $0 + $1.duration },
            chapters: chapters,
            audioTracks: [],
            subtitleTracks: [],
            segments: segments
        )
    }

    private func parseChapters(
        data: Data,
        markStart: Int,
        itemRanges: [(start: TimeInterval, inTime: UInt32, outTime: UInt32)]
    ) -> [DiscChapter] {
        guard markStart > 0, markStart + 6 < data.count else { return [] }
        var reader = DiscBinaryReader(data: data)
        reader.offset = markStart + 4
        let markCount = Int(reader.readUInt16())
        var chapters: [DiscChapter] = []

        for markIndex in 0..<markCount {
            guard reader.offset + 14 <= data.count else { break }
            _ = reader.readUInt8() // reserved
            let markType = reader.readUInt8()
            let playItemRef = Int(reader.readUInt16())
            let timestamp = reader.readUInt32()
            _ = reader.readUInt16() // entry ES PID
            _ = reader.readUInt32() // duration

            guard markType == 1 else { continue }
            guard playItemRef < itemRanges.count else { continue }
            let item = itemRanges[playItemRef]
            let seconds = item.start + max(0, TimeInterval(Int64(timestamp) - Int64(item.inTime)) / 45_000.0)
            chapters.append(DiscChapter(index: markIndex, startTime: seconds))
        }
        return chapters
    }

    private func bdmvRoot(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        guard let index = components.lastIndex(where: { $0.uppercased() == "BDMV" }) else {
            return standardized.lastPathComponent.uppercased() == "BDMV" ? standardized : nil
        }
        let rootPath = NSString.path(withComponents: Array(components[0...index]))
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }
}

private struct DiscBinaryReader {
    let data: Data
    var offset: Int = 0

    mutating func readUInt8() -> UInt8 {
        defer { offset += 1 }
        guard offset < data.count else { return 0 }
        return data[offset]
    }

    mutating func readUInt16() -> UInt16 {
        defer { offset += 2 }
        guard offset + 2 <= data.count else { return 0 }
        return data[offset..<offset + 2].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    mutating func readUInt32() -> UInt32 {
        defer { offset += 4 }
        return readUInt32(at: offset)
    }

    mutating func readString(length: Int) -> String {
        defer { offset += length }
        return readString(length: length, at: offset)
    }

    public func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    public func readString(length: Int, at offset: Int) -> String {
        guard offset + length <= data.count else { return "" }
        return String(data: data[offset..<offset + length], encoding: .ascii) ?? ""
    }
}
