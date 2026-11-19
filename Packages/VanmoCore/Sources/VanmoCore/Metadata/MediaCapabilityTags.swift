import Foundation

/// 详情页分辨率标签。只在已有宽高时产出，避免假数据。
public enum VideoResolutionLabel: String, Sendable {
    case low = "LOW"
    case p1080 = "1080P"
    case k2 = "2K"
    case k4 = "4K"

    public static func classify(width: Int?, height: Int?) -> VideoResolutionLabel? {
        let resolvedWidth = width ?? 0
        let resolvedHeight = height ?? 0
        guard resolvedWidth > 0 || resolvedHeight > 0 else { return nil }

        if resolvedWidth >= 3840 || resolvedHeight >= 2160 {
            return .k4
        }
        if resolvedWidth >= 2560 || resolvedHeight >= 1440 {
            return .k2
        }
        if resolvedWidth >= 1920 || resolvedHeight >= 1080 {
            return .p1080
        }
        return .low
    }

    public static func classify(fileName: String?) -> VideoResolutionLabel? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let source = fileName.lowercased()
        if source.contains("2160") || source.contains("4320") || source.contains("4k") || source.contains("uhd") {
            return .k4
        }
        if source.contains("1440") || source.contains("2k") {
            return .k2
        }
        if source.contains("1080") || source.contains("fhd") {
            return .p1080
        }
        if source.contains("720") || source.contains("480") || source.contains("540") || source.contains("360") {
            return .low
        }
        return nil
    }

    /// Plex `videoResolution` 等离散值在缺宽高时的回退。
    public static func dimensions(fromResolutionToken token: String?) -> (width: Int, height: Int)? {
        guard let token else { return nil }
        switch token.lowercased() {
        case "4k", "2160", "uhd":
            return (3840, 2160)
        case "1440", "2k":
            return (2560, 1440)
        case "1080", "fhd":
            return (1920, 1080)
        case "720", "hd":
            return (1280, 720)
        case "480", "sd":
            return (720, 480)
        default:
            return nil
        }
    }
}

/// 详情页能力标签：分级、分辨率、杜比检测（不实现杜比播放）。
public enum MediaCapabilityTags {
    public static func displayTags(
        contentRating: String?,
        width: Int?,
        height: Int?,
        dynamicRange: String?,
        audioTracks: [AudioTrackInfo],
        fileName: String?
    ) -> [String] {
        var tags: [String] = []
        if let rating = normalizedContentRating(contentRating) {
            tags.append(rating)
        }
        if let resolution = VideoResolutionLabel.classify(width: width, height: height)
            ?? VideoResolutionLabel.classify(fileName: fileName) {
            tags.append(resolution.rawValue)
        }
        if detectsDolby(dynamicRange: dynamicRange, audioTracks: audioTracks, fileName: fileName) {
            tags.append("DOLBY")
        }
        return tags
    }

    public static func normalizedContentRating(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func detectsDolby(
        dynamicRange: String?,
        audioTracks: [AudioTrackInfo],
        fileName: String?
    ) -> Bool {
        if let dynamicRange, isDolbyToken(dynamicRange) {
            return true
        }

        for track in audioTracks {
            let blob = [track.codec, track.title]
                .compactMap { $0 }
                .joined(separator: " ")
            if isDolbyToken(blob) {
                return true
            }
        }

        if let fileName, isDolbyToken(fileName) {
            return true
        }
        return false
    }

    /// 仅识别视频杜比视界范围，供持久化 `dynamicRange` 使用。
    public static func isDolbyVisionRange(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let token = raw.lowercased()
        return token.contains("dolbyvision")
            || token.contains("dolby vision")
            || token.contains("dovi")
            || token == DynamicRange.dolbyVision.rawValue
    }

    /// 识别更细分的动态范围（Dolby Vision / HDR10 / HLG / HDR）。
    public static func detectDynamicRangeValue(
        videoRange: String?,
        videoRangeType: String? = nil,
        colorTransfer: String? = nil
    ) -> DynamicRange? {
        let combined = [videoRangeType, videoRange, colorTransfer]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        guard !combined.isEmpty else { return nil }

        if isDolbyVisionRange(combined) {
            return .dolbyVision
        }
        if combined.contains("hdr10") || combined.contains("smpte2084") || combined.contains("smpte_st_2084") {
            return .hdr10
        }
        if combined.contains("hlg") || combined.contains("arib-std-b67") || combined.contains("itu_r_2100_hlg") {
            return .hlg
        }
        if combined.contains("hdr") {
            return .hdr
        }
        if combined.contains("sdr") || combined.contains("bt709") {
            return .sdr
        }
        return nil
    }

    /// 详情页顶部能力徽章（如 `4K`, `Dolby Vision`, `HDR10`, `TV-MA`）。
    public static func detailCapabilityBadges(
        contentRating: String?,
        width: Int?,
        height: Int?,
        dynamicRange: String?,
        audioTracks: [AudioTrackInfo],
        fileName: String?
    ) -> [String] {
        var badges: [String] = []
        if let resolution = VideoResolutionLabel.classify(width: width, height: height)
            ?? VideoResolutionLabel.classify(fileName: fileName) {
            badges.append(resolution.rawValue)
        }

        if let range = resolvedDynamicRange(dynamicRange: dynamicRange, fileName: fileName),
           let displayName = range.displayName {
            badges.append(displayName)
            if range == .dolbyVision,
               let fileName,
               fileName.lowercased().contains("hdr10"),
               !badges.contains("HDR10") {
                badges.append("HDR10")
            }
        } else if detectsDolby(dynamicRange: dynamicRange, audioTracks: audioTracks, fileName: fileName) {
            badges.append("Dolby Audio")
        }

        if let rating = normalizedContentRating(contentRating) {
            badges.append(rating)
        }

        return badges
    }

    /// 详情页底部 `MEDIA SPECIFICATIONS` 芯片（视频编码 / 位深 / 音轨规格 / 码率）。
    public static func mediaSpecificationChips(
        videoCodec: String?,
        bitDepth: Int?,
        audioTracks: [AudioTrackInfo],
        bitRate: Int?,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0
    ) -> [String] {
        var chips: [String] = []

        if let formattedCodec = normalizedVideoCodec(videoCodec) {
            chips.append(formattedCodec)
        }

        if let bitDepth, bitDepth > 0 {
            chips.append("\(bitDepth)-bit")
        }

        if let audioChip = primaryAudioSpecification(from: audioTracks) {
            chips.append(audioChip)
        }

        let resolvedBitRate: Int? = {
            if let bitRate, bitRate > 0 { return bitRate }
            if fileSize > 0, duration > 0 {
                return Int((Double(fileSize) * 8.0) / duration)
            }
            return nil
        }()
        if let resolvedBitRate, let formattedBitRate = formattedBitRateLabel(resolvedBitRate) {
            chips.append(formattedBitRate)
        }

        return chips
    }

    public static func normalizedVideoCodec(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "hevc" || lower == "h265" || lower == "h.265" || lower == "hev1" || lower == "hvc1" {
            return "HEVC"
        }
        if lower == "h264" || lower == "h.264" || lower == "avc" || lower == "avc1" {
            return "H.264"
        }
        if lower == "av1" || lower == "av01" {
            return "AV1"
        }
        if lower == "vp9" {
            return "VP9"
        }
        if lower == "mpeg4" || lower == "mp4v" {
            return "MPEG-4"
        }
        if lower == "mpeg2video" || lower == "mpeg2" {
            return "MPEG-2"
        }
        return trimmed.uppercased()
    }

    public static func primaryAudioSpecification(from tracks: [AudioTrackInfo]) -> String? {
        guard let track = tracks.first else { return nil }
        let codecName = normalizedAudioCodec(track.codec, title: track.title)
        let layout = track.channelLayoutName

        if let codecName, let layout {
            return codecName.contains(layout) ? codecName : "\(codecName) \(layout)"
        }
        if let codecName {
            return codecName
        }
        if let layout {
            return layout
        }
        return nil
    }

    public static func formattedBitRateLabel(_ bps: Int) -> String? {
        guard bps > 0 else { return nil }
        let mbps = Double(bps) / 1_000_000.0
        if mbps >= 1.0 {
            return String(format: "%.1f Mbps", mbps)
        }
        let kbps = max(1, Int((Double(bps) / 1_000.0).rounded()))
        return "\(kbps) kbps"
    }

    private static func resolvedDynamicRange(dynamicRange: String?, fileName: String?) -> DynamicRange? {
        if let dynamicRange, let parsed = DynamicRange(rawValue: dynamicRange), parsed != .sdr {
            return parsed
        }
        if let detected = detectDynamicRangeValue(videoRange: dynamicRange) {
            if detected != .sdr {
                return detected
            }
        }
        guard let fileName, !fileName.isEmpty else { return nil }
        let lower = fileName.lowercased()
        if isDolbyVisionRange(lower) {
            return .dolbyVision
        }
        if lower.contains("hdr10") {
            return .hdr10
        }
        if lower.contains("hlg") {
            return .hlg
        }
        if lower.contains("hdr") {
            return .hdr
        }
        return nil
    }

    private static func normalizedAudioCodec(_ raw: String?, title: String?) -> String? {
        let combined = [raw, title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !combined.isEmpty else { return nil }

        let lower = combined.lowercased()
        if lower.contains("truehd") || lower.contains("mlp") {
            return lower.contains("atmos") ? "Dolby TrueHD Atmos" : "Dolby TrueHD"
        }
        if lower.contains("eac3") || lower.contains("e-ac-3") || lower.contains("e-ac3") || lower.contains("dd+") {
            return lower.contains("atmos") ? "Dolby Digital+ Atmos" : "Dolby Digital+"
        }
        if lower.contains("ac3") || lower.contains("ac-3") {
            return "Dolby Digital"
        }
        if lower.contains("dts-hd ma") || lower.contains("dts:x") || lower.contains("dtshd") || lower.contains("dts-hd") {
            return lower.contains("dts:x") ? "DTS:X" : "DTS-HD MA"
        }
        if lower.contains("dts") {
            return "DTS"
        }
        if lower.contains("aac") {
            return "AAC"
        }
        if lower.contains("flac") {
            return "FLAC"
        }
        if lower.contains("opus") {
            return "Opus"
        }
        if lower.contains("pcm") || lower.contains("lpcm") {
            return "PCM"
        }
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return nil
    }

    private static func isDolbyToken(_ raw: String) -> Bool {
        let token = raw.lowercased()
        return token.contains("dolby")
            || token.contains("truehd")
            || token.contains("atmos")
            || token.contains("eac3")
            || token.contains("e-ac-3")
            || token.contains("e-ac3")
            || token.contains("dovi")
            || token.contains("dolbyvision")
            || token.contains(".dv.")
            || token == DynamicRange.dolbyVision.rawValue
    }
}
