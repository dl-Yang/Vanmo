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
