import Foundation

/// Emby/Jellyfin 的 VOD `master.m3u8` 会列出整片全部分段。
/// 播放器从中间起播时，服务器才按该分段的 `runtimeTicks` 启动 ffmpeg，
/// 分段文件要等下一段出现才算写完。第一次读到未写完的分段会音画错位，
/// 同一位置再次打开时文件已经完整，所以是同步的。
/// 开播前先把目标时间所在分段下载完。Plex 的 HLS 分段同样适用。
public enum HlsTranscodePrimer {
    public struct SegmentTarget: Equatable, Sendable {
        public var url: URL
        public var start: TimeInterval
    }

    public enum PlaylistStep: Equatable, Sendable {
        case variant(URL)
        case segment(SegmentTarget)
    }

    public static func step(playlist: String, baseURL: URL, startTime: TimeInterval) -> PlaylistStep? {
        let lines = playlist.components(separatedBy: .newlines)
        if lines.contains(where: { $0.uppercased().hasPrefix("#EXT-X-STREAM-INF") }) {
            guard let variant = firstReference(after: "#EXT-X-STREAM-INF", in: lines, baseURL: baseURL) else {
                return nil
            }
            return .variant(variant)
        }

        var cursor: TimeInterval = 0
        var pendingDuration: TimeInterval?
        var selected: SegmentTarget?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.uppercased().hasPrefix("#EXTINF:") {
                let number = line.dropFirst("#EXTINF:".count).prefix { $0 != "," }
                pendingDuration = Double(number)
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#"), pendingDuration != nil else { continue }
            let url = absolute(line, baseURL: baseURL)
            let start = runtimeStart(url) ?? cursor
            if start <= startTime + 0.05 {
                selected = SegmentTarget(url: url, start: start)
            }
            cursor += pendingDuration ?? 0
            pendingDuration = nil
            if start > startTime {
                break
            }
        }
        return selected.map(PlaylistStep.segment)
    }

    /// 只预下载 HLS 列表。原画直链是整段视频，按列表去读会把文件下完才开播。
    public static func shouldPrime(playlistURL: URL, startTime: TimeInterval) -> Bool {
        startTime > 1 && playlistURL.path.lowercased().contains(".m3u8")
    }

    public static func prime(playlistURL: URL, startTime: TimeInterval) async {
        guard shouldPrime(playlistURL: playlistURL, startTime: startTime) else { return }
        var current = playlistURL
        for _ in 0..<3 {
            guard let playlist = await fetchText(current) else { return }
            switch step(playlist: playlist, baseURL: current, startTime: startTime) {
            case .variant(let variant):
                current = variant
            case .segment(let target):
                await download(target)
                return
            case nil:
                return
            }
        }
    }

    private static func firstReference(after marker: String, in lines: [String], baseURL: URL) -> URL? {
        var armed = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.uppercased().hasPrefix(marker.uppercased()) {
                armed = true
                continue
            }
            if armed, !line.isEmpty, !line.hasPrefix("#") {
                return absolute(line, baseURL: baseURL)
            }
        }
        return nil
    }

    private static func runtimeStart(_ url: URL) -> TimeInterval? {
        guard let ticks = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("runtimeTicks") == .orderedSame })?
            .value,
              let value = Double(ticks) else {
            return nil
        }
        return value / 10_000_000
    }

    private static func absolute(_ reference: String, baseURL: URL) -> URL {
        if let url = URL(string: reference), url.scheme != nil {
            return url
        }
        return URL(string: reference, relativeTo: baseURL)?.absoluteURL
            ?? URL(string: reference)
            ?? baseURL
    }

    private static func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else {
#if DEBUG
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPrime status=\(status, privacy: .public) stage=playlist")
#endif
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
#if DEBUG
            let nsError = error as NSError
            VanmoLogger.player.info("[Debug][Player] event=videoQualityPrime status=transport stage=playlist domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
            return nil
        }
    }

    private static func download(_ target: SegmentTarget) async {
        var previousCount = -1
        var previousLead: MpegTsTiming.StreamTiming?
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: target.url)
                request.timeoutInterval = 45
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let timing = MpegTsTiming.measurement(in: data)
#if DEBUG
                let startText = timing.map { String($0.startLeadMilliseconds) } ?? "none"
                let overlapText = timing?.overlapLeadMilliseconds.map(String.init) ?? "none"
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPrime status=\(status, privacy: .public) segmentStart=\(target.start, privacy: .public) bytes=\(data.count, privacy: .public) startLeadMs=\(startText, privacy: .public) overlapLeadMs=\(overlapText, privacy: .public) attempt=\(attempt, privacy: .public)")
#endif
                let aligned = timing.map { sample in
                    let overlapAligned = sample.overlapLeadMilliseconds.map { abs($0) <= 150 } ?? false
                    return abs(sample.startLeadMilliseconds) <= 150 && overlapAligned
                } ?? false
                let stable = data.count == previousCount && timing == previousLead
                if status != 200 || aligned || stable || attempt == 2 {
                    return
                }
                previousCount = data.count
                previousLead = timing
                try? await Task.sleep(nanoseconds: 400_000_000)
            } catch {
#if DEBUG
                let nsError = error as NSError
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPrime status=transport segmentStart=\(target.start, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
                return
            }
        }
    }
}

public enum MpegTsTiming {
    /// 起点差是第一包音频 PTS 减第一包视频 PTS。
    /// 重叠差是第一帧视频之后，音频 PTS 减文件顺序里上一包视频 PTS 的中位数。
    public struct StreamTiming: Equatable, Sendable {
        public var startLeadMilliseconds: Int
        /// 第一帧视频之后、按文件顺序紧挨着的视频 PTS 之差。没有重叠样本时为 nil。
        public var overlapLeadMilliseconds: Int?
    }

    public struct AudioAlignment: Equatable, Sendable {
        public enum Action: String, Equatable, Sendable {
            case trim
            case shift
        }

        public var data: Data
        public var action: Action
        public var startLeadMilliseconds: Int
        public var overlapLeadMilliseconds: Int?
        /// 平移时是加到音频 PTS 上的毫秒。裁剪前导音频时为 0。
        public var shiftMilliseconds: Int
    }

    /// 重叠部分有稳定唇形误差时平移音频。只有开头音频早于视频时，删掉那段前导音频。
    /// 整段音频都早于第一帧视频时改为平移，避免把这一分段的声音裁光。
    public static func aligningAudioToVideo(_ data: Data) -> AudioAlignment? {
        guard let timing = measurement(in: data) else { return nil }
        let shiftLead: Int?
        let action: AudioAlignment.Action
        if let overlap = timing.overlapLeadMilliseconds, abs(overlap) > 150 {
            shiftLead = overlap
            action = .shift
        } else if timing.overlapLeadMilliseconds == nil, abs(timing.startLeadMilliseconds) > 150 {
            shiftLead = timing.startLeadMilliseconds
            action = .shift
        } else if abs(timing.startLeadMilliseconds) > 150 {
            shiftLead = nil
            action = .trim
        } else {
            return nil
        }
        var bytes = [UInt8](data)
        if let shiftLead {
            let delta = Int64((Double(-shiftLead) / 1000 * 90_000).rounded())
            guard shiftAudioTimestamps(&bytes, delta90k: delta) else { return nil }
        }
        if let videoPTS = firstPTS(in: Data(bytes), isVideo: true),
           let trimmed = trimLeadingAudio(bytes, firstVideoPTS: videoPTS) {
            bytes = trimmed
        } else if shiftLead == nil {
            return nil
        }
        return AudioAlignment(
            data: Data(bytes),
            action: action,
            startLeadMilliseconds: timing.startLeadMilliseconds,
            overlapLeadMilliseconds: timing.overlapLeadMilliseconds,
            shiftMilliseconds: -(shiftLead ?? 0)
        )
    }

    public static func measurement(in data: Data) -> StreamTiming? {
        let stamps = collectPTS(in: data)
        guard let videoPTS = stamps.video.first, let audioPTS = stamps.audio.first else { return nil }
        let startLead = Int(((audioPTS - videoPTS) * 1000).rounded())
        return StreamTiming(
            startLeadMilliseconds: startLead,
            overlapLeadMilliseconds: overlapLeadMilliseconds(in: stamps.events, firstVideoPTS: videoPTS)
        )
    }

    /// 音频 PTS 减去视频 PTS。负数表示音频时间戳更早。
    public static func videoLeadMilliseconds(in data: Data) -> Int? {
        measurement(in: data)?.startLeadMilliseconds
    }

    private struct TimedPacket {
        var isVideo: Bool
        var pts: TimeInterval
    }

    private struct CollectedPTS {
        var audio: [TimeInterval]
        var video: [TimeInterval]
        var events: [TimedPacket]
    }

    private static func collectPTS(in data: Data) -> CollectedPTS {
        let bytes = [UInt8](data)
        guard bytes.count >= 188 else { return CollectedPTS(audio: [], video: [], events: []) }
        var audio: [TimeInterval] = []
        var video: [TimeInterval] = []
        var events: [TimedPacket] = []
        var offset = syncOffset(in: bytes)
        while offset + 188 <= bytes.count {
            if bytes[offset] == 0x47 {
                if let pts = pts(in: bytes, packet: offset, isVideo: true) {
                    video.append(pts)
                    events.append(TimedPacket(isVideo: true, pts: pts))
                } else if let pts = pts(in: bytes, packet: offset, isVideo: false) {
                    audio.append(pts)
                    events.append(TimedPacket(isVideo: false, pts: pts))
                }
            }
            offset += 188
        }
        return CollectedPTS(audio: audio, video: video, events: events)
    }

    /// 第一帧视频之后的音频，减去文件顺序里上一包视频的 PTS。没有这种样本时返回 nil。
    private static func overlapLeadMilliseconds(in events: [TimedPacket], firstVideoPTS: TimeInterval) -> Int? {
        var lastVideo: TimeInterval?
        var leads: [Int] = []
        for event in events {
            if event.isVideo {
                lastVideo = event.pts
                continue
            }
            guard let lastVideo, event.pts + 0.000_001 >= firstVideoPTS else { continue }
            leads.append(Int(((event.pts - lastVideo) * 1000).rounded()))
        }
        guard !leads.isEmpty else { return nil }
        let sorted = leads.sorted()
        return sorted[sorted.count / 2]
    }

    /// 去掉早于第一帧视频 150ms 以上的音频 PES。保留原始 continuity counter。
    private static func trimLeadingAudio(_ bytes: [UInt8], firstVideoPTS: TimeInterval) -> [UInt8]? {
        guard bytes.count >= 188 else { return nil }
        let cutoff = firstVideoPTS - 0.150
        var dropping: Set<UInt16> = []
        var removedPIDs: Set<UInt16> = []
        var kept = [UInt8]()
        kept.reserveCapacity(bytes.count)
        var offset = syncOffset(in: bytes)
        if offset > 0 {
            kept.append(contentsOf: bytes[..<offset])
        }
        while offset + 188 <= bytes.count {
            guard bytes[offset] == 0x47 else {
                kept.append(contentsOf: bytes[offset..<(offset + 188)])
                offset += 188
                continue
            }
            let pid = packetPID(bytes, packet: offset)
            if bytes[offset + 1] & 0x40 != 0 {
                if let audioPTS = pts(in: bytes, packet: offset, isVideo: false) {
                    if audioPTS < cutoff {
                        dropping.insert(pid)
                        removedPIDs.insert(pid)
                        offset += 188
                        continue
                    }
                    dropping.remove(pid)
                } else if let streamID = pesStreamID(in: bytes, packet: offset), (streamID & 0xF0) == 0xC0 {
                    dropping.remove(pid)
                }
            }
            if dropping.contains(pid) {
                removedPIDs.insert(pid)
                offset += 188
                continue
            }
            kept.append(contentsOf: bytes[offset..<(offset + 188)])
            offset += 188
        }
        if offset < bytes.count {
            kept.append(contentsOf: bytes[offset...])
        }
        guard !removedPIDs.isEmpty else { return nil }
        markFirstDiscontinuity(&kept, pids: removedPIDs)
        return kept
    }

    /// 保留原始 continuity counter，让下一段仍能接上。已有 adaptation field 时标出不连续。
    private static func markFirstDiscontinuity(_ bytes: inout [UInt8], pids: Set<UInt16>) {
        var seen: Set<UInt16> = []
        var offset = syncOffset(in: bytes)
        while offset + 188 <= bytes.count {
            guard bytes[offset] == 0x47 else {
                offset += 188
                continue
            }
            let pid = packetPID(bytes, packet: offset)
            if pids.contains(pid), seen.insert(pid).inserted {
                let adaptation = (bytes[offset + 3] >> 4) & 0x03
                if adaptation == 2 || adaptation == 3 {
                    let lengthIndex = offset + 4
                    let length = Int(bytes[lengthIndex])
                    if length > 0, lengthIndex + 1 < offset + 188 {
                        bytes[lengthIndex + 1] |= 0x80
                    }
                }
            }
            offset += 188
        }
    }

    private static func packetPID(_ bytes: [UInt8], packet: Int) -> UInt16 {
        (UInt16(bytes[packet + 1] & 0x1F) << 8) | UInt16(bytes[packet + 2])
    }

    private static func pesStreamID(in bytes: [UInt8], packet: Int) -> UInt8? {
        guard bytes[packet] == 0x47, bytes[packet + 1] & 0x40 != 0 else { return nil }
        let adaptation = (bytes[packet + 3] >> 4) & 0x03
        var cursor = packet + 4
        if adaptation == 2 || adaptation == 3 {
            guard cursor < packet + 188 else { return nil }
            let length = Int(bytes[cursor])
            guard cursor + 1 + length <= packet + 188 else { return nil }
            cursor += 1 + length
        }
        guard adaptation == 1 || adaptation == 3,
              cursor + 3 < packet + 188,
              bytes[cursor] == 0, bytes[cursor + 1] == 0, bytes[cursor + 2] == 1 else {
            return nil
        }
        return bytes[cursor + 3]
    }

    private static func firstPTS(in data: Data, isVideo: Bool) -> TimeInterval? {
        let bytes = [UInt8](data)
        guard bytes.count >= 188 else { return nil }
        var offset = syncOffset(in: bytes)
        while offset + 188 <= bytes.count {
            if bytes[offset] == 0x47, let pts = pts(in: bytes, packet: offset, isVideo: isVideo) {
                return pts
            }
            offset += 188
        }
        return nil
    }

    private static func syncOffset(in bytes: [UInt8]) -> Int {
        if bytes[0] == 0x47 { return 0 }
        let limit = min(bytes.count - 188, 188)
        var index = 1
        while index < limit {
            if bytes[index] == 0x47, index + 188 < bytes.count, bytes[index + 188] == 0x47 {
                return index
            }
            index += 1
        }
        return 0
    }

    private static func pts(in bytes: [UInt8], packet: Int, isVideo: Bool) -> TimeInterval? {
        guard bytes[packet + 1] & 0x40 != 0 else { return nil }
        let adaptation = (bytes[packet + 3] >> 4) & 0x03
        var cursor = packet + 4
        if adaptation == 2 || adaptation == 3 {
            guard cursor < packet + 188 else { return nil }
            cursor += 1 + Int(bytes[cursor])
        }
        guard adaptation == 1 || adaptation == 3,
              cursor + 13 < packet + 188,
              bytes[cursor] == 0, bytes[cursor + 1] == 0, bytes[cursor + 2] == 1 else {
            return nil
        }
        let streamID = bytes[cursor + 3]
        let matches = isVideo ? (streamID & 0xF0) == 0xE0 : (streamID & 0xF0) == 0xC0
        guard matches, bytes[cursor + 7] & 0x80 != 0 else { return nil }
        let headerLength = Int(bytes[cursor + 8])
        let ptsAt = cursor + 9
        guard headerLength >= 5, ptsAt + 4 < packet + 188 else { return nil }
        return decodePTS(bytes, at: ptsAt) / 90_000
    }

    private static func shiftAudioTimestamps(_ bytes: inout [UInt8], delta90k: Int64) -> Bool {
        guard bytes.count >= 188 else { return false }
        var offset = syncOffset(in: bytes)
        var changed = false
        while offset + 188 <= bytes.count {
            if bytes[offset] == 0x47, stampAudioPacket(&bytes, packet: offset, delta90k: delta90k) {
                changed = true
            }
            offset += 188
        }
        return changed
    }

    private static func stampAudioPacket(_ bytes: inout [UInt8], packet: Int, delta90k: Int64) -> Bool {
        guard bytes[packet + 1] & 0x40 != 0 else { return false }
        let adaptation = (bytes[packet + 3] >> 4) & 0x03
        var cursor = packet + 4
        if adaptation == 2 || adaptation == 3 {
            guard cursor < packet + 188 else { return false }
            cursor += 1 + Int(bytes[cursor])
        }
        guard adaptation == 1 || adaptation == 3,
              cursor + 13 < packet + 188,
              bytes[cursor] == 0, bytes[cursor + 1] == 0, bytes[cursor + 2] == 1 else {
            return false
        }
        let streamID = bytes[cursor + 3]
        guard (streamID & 0xF0) == 0xC0, bytes[cursor + 7] & 0x80 != 0 else { return false }
        let headerLength = Int(bytes[cursor + 8])
        let ptsAt = cursor + 9
        guard headerLength >= 5, ptsAt + 4 < packet + 188 else { return false }
        writeTimestamp(&bytes, at: ptsAt, delta90k: delta90k)
        if bytes[cursor + 7] & 0x40 != 0, headerLength >= 10, ptsAt + 9 < packet + 188 {
            writeTimestamp(&bytes, at: ptsAt + 5, delta90k: delta90k)
        }
        return true
    }

    private static func writeTimestamp(_ bytes: inout [UInt8], at index: Int, delta90k: Int64) {
        let shifted = (Int64(decodePTSInteger(bytes, at: index)) + delta90k) & 0x1FFFFFFFF
        let pts = UInt64(shifted)
        let high = (pts >> 30) & 0x7
        let middle = (pts >> 15) & 0x7FFF
        let low = pts & 0x7FFF
        let marker = bytes[index] & 0xF0
        bytes[index] = marker | UInt8(high << 1) | 0x01
        bytes[index + 1] = UInt8((middle >> 7) & 0xFF)
        bytes[index + 2] = UInt8(((middle & 0x7F) << 1) | 0x01)
        bytes[index + 3] = UInt8((low >> 7) & 0xFF)
        bytes[index + 4] = UInt8(((low & 0x7F) << 1) | 0x01)
    }

    private static func decodePTSInteger(_ bytes: [UInt8], at index: Int) -> UInt64 {
        let b0 = UInt64(bytes[index] & 0x0E)
        let b1 = UInt64(bytes[index + 1])
        let b2 = UInt64(bytes[index + 2] & 0xFE)
        let b3 = UInt64(bytes[index + 3])
        let b4 = UInt64(bytes[index + 4] >> 1)
        return (b0 << 29) | (b1 << 22) | (b2 << 14) | (b3 << 7) | b4
    }

    private static func decodePTS(_ bytes: [UInt8], at index: Int) -> Double {
        let b0 = UInt64(bytes[index] & 0x0E)
        let b1 = UInt64(bytes[index + 1])
        let b2 = UInt64(bytes[index + 2] & 0xFE)
        let b3 = UInt64(bytes[index + 3])
        let b4 = UInt64(bytes[index + 4] >> 1)
        return Double((b0 << 29) | (b1 << 22) | (b2 << 14) | (b3 << 7) | b4)
    }
}
