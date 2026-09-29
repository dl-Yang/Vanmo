import Foundation

/// Emby 的 `master.m3u8` 常把声音拆成独立音轨，AVPlayer 从中间起播时画面会超前。
/// 去掉音频分组，并把相对地址补成绝对地址，让播放器使用分片里自带的声音。
public enum EmbyHlsPlaylist {
    public struct MasterRewrite: Equatable, Sendable {
        public var playlist: String
        public var removedAudioGroups: Int
    }

    public static func muxedMaster(playlist: String, baseURL: URL) -> MasterRewrite {
        var removedAudioGroups = 0
        var lines: [String] = []
        for rawLine in playlist.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAudioGroup(trimmed) {
                removedAudioGroups += 1
                continue
            }
            if trimmed.uppercased().hasPrefix("#EXT-X-STREAM-INF") {
                lines.append(absolutizeURIAttributes(in: stripAudioAttribute(trimmed), baseURL: baseURL))
                continue
            }
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                lines.append(absoluteReference(trimmed, baseURL: baseURL))
                continue
            }
            lines.append(absolutizeURIAttributes(in: rawLine, baseURL: baseURL))
        }
        return MasterRewrite(
            playlist: lines.joined(separator: "\n"),
            removedAudioGroups: removedAudioGroups
        )
    }

    /// 分段必须带 `.ts` 后缀。之前所有代理地址都写成 `/media.m3u8`，播放器把分段当播放列表解析，清晰度打开失败后回到原画。
    public static func playbackProxyPath(for url: URL) -> String {
        url.path.lowercased().contains(".ts") ? "/segment.ts" : "/media.m3u8"
    }

    /// 整片 VOD 列表从 0 开始。播放器若先请求片头分段，服务器会停掉已经在目标时间转码的任务。
    /// `#EXT-X-START` 让第一次请求就落在当前进度所在的分段上。
    public static func applyingStart(playlist: String, startTime: TimeInterval) -> String {
        guard startTime > 1 else { return playlist }
        let upper = playlist.uppercased()
        guard upper.contains("#EXTINF"), !upper.contains("#EXT-X-START") else { return playlist }
        let tag = String(format: "#EXT-X-START:TIME-OFFSET=%.3f,PRECISE=NO", startTime)
        var lines = playlist.components(separatedBy: "\n")
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("#EXTM3U")
        }) {
            lines.insert(tag, at: index + 1)
        } else {
            lines.insert(tag, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    private static func isAudioGroup(_ line: String) -> Bool {
        let upper = line.uppercased()
        return upper.hasPrefix("#EXT-X-MEDIA") && upper.contains("TYPE=AUDIO")
    }

    private static func stripAudioAttribute(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: ",AUDIO=\"[^\"]*\"", options: [.caseInsensitive]) else {
            return line
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
    }

    private static func absolutizeURIAttributes(in line: String, baseURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: "URI=\"([^\"]*)\"", options: [.caseInsensitive]) else {
            return line
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, options: [], range: range).reversed()
        var result = line
        for match in matches {
            guard match.numberOfRanges > 1,
                  let uriRange = Range(match.range(at: 1), in: result) else { continue }
            let absolute = absoluteReference(String(result[uriRange]), baseURL: baseURL)
            result.replaceSubrange(uriRange, with: absolute)
        }
        return result
    }

    private static func absoluteReference(_ reference: String, baseURL: URL) -> String {
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") {
            return reference
        }
        return URL(string: reference, relativeTo: baseURL)?.absoluteString ?? reference
    }
}
