import Foundation

/// 媒体服务器清晰度地址。原画返回现有直链；低档返回转码 HLS。
/// 密钥留在 URL 查询里，调用方只能记录 `safePlaybackLogDescription`。
public enum PlaybackQualityStream {
    public static func playbackURL(
        directURL: URL,
        serverItemID: String?,
        connectionType: ConnectionType,
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) -> URL {
        guard quality != .original else { return directURL }
        switch connectionType {
        case .emby, .jellyfin:
            return embyTranscodeURL(
                directURL: directURL,
                serverItemID: serverItemID,
                quality: quality,
                startTime: startTime
            )
        case .plex:
            return plexTranscodeURL(
                directURL: directURL,
                serverItemID: serverItemID,
                quality: quality,
                startTime: startTime
            )
        default:
            return directURL
        }
    }

    /// 只包含清晰度参数和路径，不含 `api_key` 或 token。
    public static func debugSummary(of url: URL) -> String {
        let allowed = [
            "static", "Container", "MaxHeight", "MaxWidth", "VideoBitrate",
            "MaxStreamingBitrate", "AllowVideoStreamCopy", "SegmentContainer",
            "TranscodingProtocol", "maxVideoBitrate", "videoResolution",
            "BreakOnNonKeyFrames", "CopyTimestamps", "MinSegments", "X-Plex-Incomplete-Segments"
        ]
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fields = items.compactMap { item -> String? in
            guard allowed.contains(item.name), let value = item.value else { return nil }
            return "\(item.name)=\(value)"
        }
        let path = url.safePlaybackLogDescription
        guard !fields.isEmpty else { return "direct path=\(path)" }
        return "path=\(path) " + fields.joined(separator: " ")
    }

    private static func embyTranscodeURL(
        directURL: URL,
        serverItemID: String?,
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) -> URL {
        guard let size = transcodeSize(for: quality),
              let bitrate = quality.preferredPeakBitRate,
              var components = URLComponents(url: directURL, resolvingAgainstBaseURL: false) else {
            return directURL
        }
        let itemID = normalized(serverItemID) ?? videoItemID(in: components.path)
        guard let itemID else { return directURL }
        components.path = masterPath(from: components.path, itemID: itemID)
        let apiKey = queryValue("api_key", in: components)
        let videoBitrate = Int(bitrate)
        var items = [
            URLQueryItem(name: "MediaSourceId", value: itemID),
            URLQueryItem(name: "DeviceId", value: PlatformDeviceInfo.deviceIdentifier),
            URLQueryItem(name: "PlaySessionId", value: UUID().uuidString),
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "MaxHeight", value: String(size.height)),
            URLQueryItem(name: "MaxWidth", value: String(size.width)),
            URLQueryItem(name: "VideoBitrate", value: String(videoBitrate)),
            URLQueryItem(name: "AudioBitrate", value: "128000"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(videoBitrate + 128_000)),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "SegmentContainer", value: "ts"),
            URLQueryItem(name: "MinSegments", value: "1"),
            URLQueryItem(name: "BreakOnNonKeyFrames", value: "true"),
            URLQueryItem(name: "StartTimeTicks", value: String(startTicks(startTime)))
        ]
        if let apiKey {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = items
        return components.url ?? directURL
    }

    private static func plexTranscodeURL(
        directURL: URL,
        serverItemID: String?,
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) -> URL {
        guard let itemID = normalized(serverItemID),
              let size = transcodeSize(for: quality),
              let bitrate = quality.preferredPeakBitRate,
              var origin = URLComponents(url: directURL, resolvingAgainstBaseURL: false) else {
            return directURL
        }
        let token = queryValue("X-Plex-Token", in: origin)
        origin.path = ""
        origin.query = nil
        origin.fragment = nil
        guard let originString = origin.string else { return directURL }
        var query = URLComponents()
        var items = [
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "maxVideoBitrate", value: String(Int(bitrate / 1_000))),
            URLQueryItem(name: "videoResolution", value: "\(size.width)x\(size.height)"),
            URLQueryItem(name: "offset", value: String(Int(max(0, startTime).rounded()))),
            URLQueryItem(name: "path", value: "/library/metadata/\(itemID)"),
            URLQueryItem(name: "X-Plex-Incomplete-Segments", value: "0")
        ]
        if let token {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        items.append(URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexCredentialStore.clientIdentifier))
        items.append(URLQueryItem(name: "X-Plex-Product", value: "Vanmo"))
        items.append(URLQueryItem(name: "X-Plex-Platform", value: Self.plexPlatform))
        items.append(URLQueryItem(name: "session", value: UUID().uuidString))
        query.queryItems = items
        guard let encodedQuery = query.percentEncodedQuery else { return directURL }
        let raw = "\(originString)/video/:/transcode/universal/start.m3u8?\(encodedQuery)"
        return URL(string: raw) ?? directURL
    }

    private static func transcodeSize(for quality: PlaybackVideoQuality) -> (width: Int, height: Int)? {
        guard let height = quality.maxHeight else { return nil }
        var width = (height * 16) / 9
        if width % 2 != 0 { width += 1 }
        return (width, height)
    }

    private static func startTicks(_ startTime: TimeInterval) -> Int64 {
        Int64((max(0, startTime) * 10_000_000).rounded())
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func videoItemID(in path: String) -> String? {
        let parts = path.split(separator: "/")
        guard let index = parts.firstIndex(where: { $0.caseInsensitiveCompare("Videos") == .orderedSame }),
              parts.index(after: index) < parts.endIndex else {
            return nil
        }
        let itemID = String(parts[parts.index(after: index)])
        return itemID.isEmpty ? nil : itemID
    }

    private static func masterPath(from path: String, itemID: String) -> String {
        let marker = "/Videos/\(itemID)"
        if let range = path.range(of: marker, options: [.caseInsensitive]) {
            return String(path[..<range.upperBound]) + "/master.m3u8"
        }
        return "/Videos/\(itemID)/master.m3u8"
    }

    private static var plexPlatform: String {
        #if os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #else
        "Unknown"
        #endif
    }

    private static func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
