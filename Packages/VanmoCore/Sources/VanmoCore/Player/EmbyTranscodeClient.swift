import Foundation

/// 向 Emby / Jellyfin 要一条指定码率的 HLS 转码地址。
/// 手写 `master.m3u8` 会被这台服务器回 HTTP 400。
public enum EmbyTranscodeClient {
    public static func requestBody(
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) -> Data? {
        guard let height = quality.maxHeight,
              let bitrate = quality.preferredPeakBitRate else { return nil }
        let maxRate = Int(bitrate) + 128_000
        var width = (height * 16) / 9
        if width % 2 != 0 { width += 1 }
        let json: [String: Any] = [
            "MaxStreamingBitrate": maxRate,
            "StartTimeTicks": Int64((max(0, startTime) * 10_000_000).rounded()),
            "AutoOpenLiveStream": true,
            "DeviceProfile": [
                "MaxStreamingBitrate": maxRate,
                "MaxStaticBitrate": maxRate,
                "DirectPlayProfiles": [Any](),
                "TranscodingProfiles": [[
                    "Container": "ts",
                    "Type": "Video",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac",
                    "Protocol": "hls",
                    "Context": "Streaming",
                    "MaxAudioChannels": "2",
                    "BreakOnNonKeyFrames": true,
                    "MinSegments": 2
                ]],
                "CodecProfiles": [[
                    "Type": "Video",
                    "Codec": "h264",
                    "Conditions": [
                        [
                            "Condition": "LessThanEqual",
                            "Property": "Height",
                            "Value": String(height),
                            "IsRequired": false
                        ],
                        [
                            "Condition": "LessThanEqual",
                            "Property": "Width",
                            "Value": String(width),
                            "IsRequired": false
                        ]
                    ]
                ]],
                "SubtitleProfiles": [Any]()
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: json)
    }

    public static func absoluteURL(
        transcodingURL: String,
        directURL: URL,
        apiKey: String?
    ) -> URL? {
        guard var components = URLComponents(url: directURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        components.path = ""
        guard let origin = components.string else { return nil }
        let absoluteString: String
        if transcodingURL.hasPrefix("http://") || transcodingURL.hasPrefix("https://") {
            absoluteString = transcodingURL
        } else if transcodingURL.hasPrefix("/") {
            absoluteString = origin + transcodingURL
        } else {
            let apiRoot = directURL.deletingLastPathComponent().deletingLastPathComponent().absoluteString
            absoluteString = apiRoot + transcodingURL
        }
        guard var url = URL(string: absoluteString) else { return nil }
        guard let apiKey, !apiKey.isEmpty,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) != true else {
            return url
        }
        if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = parts.queryItems ?? []
            items.append(URLQueryItem(name: "api_key", value: apiKey))
            parts.queryItems = items
            if let withKey = parts.url {
                url = withKey
            }
        }
        return url
    }

    public static func transcodeURL(
        directURL: URL,
        itemID: String,
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) async -> URL? {
        guard let body = requestBody(quality: quality, startTime: startTime),
              var endpoint = URLComponents(url: directURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let apiKey = endpoint.queryItems?.first { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }?.value
        let itemPath = "/Items/\(itemID)/PlaybackInfo"
        if let videos = endpoint.path.range(of: "/Videos/", options: [.caseInsensitive]) {
            endpoint.path = String(endpoint.path[..<videos.lowerBound]) + itemPath
        } else {
            endpoint.path = itemPath
        }
        endpoint.queryItems = [
            URLQueryItem(name: "MaxStreamingBitrate", value: String(Int(quality.preferredPeakBitRate ?? 0) + 128_000)),
            URLQueryItem(name: "StartTimeTicks", value: String(Int64((max(0, startTime) * 10_000_000).rounded())))
        ]
        if let apiKey {
            endpoint.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        guard let url = endpoint.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Emby-Token")
        }
        let deviceId = PlatformDeviceInfo.deviceIdentifier
        request.setValue(
            "MediaBrowser Client=\"Vanmo\", Device=\"\(PlatformDeviceInfo.model)\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\"",
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sources = json["MediaSources"] as? [[String: Any]],
                  let source = sources.first else {
#if DEBUG
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPlaybackInfo status=\(status, privacy: .public) \(Self.redactedBody(data), privacy: .public)")
#endif
                return nil
            }
            if let transcoding = source["TranscodingUrl"] as? String,
               let absolute = absoluteURL(transcodingURL: transcoding, directURL: directURL, apiKey: apiKey),
               let aligned = alignedTranscodeURL(absolute) {
#if DEBUG
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPlaybackInfo status=200 transcode=true path=\(absolute.safePlaybackLogDescription, privacy: .public)")
#endif
                return aligned
            }
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=videoQualityPlaybackInfo status=200 transcode=false")
#endif
            return nil
        } catch {
#if DEBUG
            let nsError = error as NSError
            VanmoLogger.player.info("[Debug][Player] event=videoQualityPlaybackInfo status=transport domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
            return nil
        }
    }

    /// Jellyfin `DynamicHlsController` 把缺省的 `breakOnNonKeyFrames` 和 `copyTimestamps` 都当成 false。
    /// iOS 官方设备配置只打开 `BreakOnNonKeyFrames`，并把 `MinSegments` 设为 2。
    /// `CopyTimestamps=true` 会加上 `-copyts -start_at_zero`，关键帧早于音频时画面会超前。
    public static func alignedTranscodeURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        func set(_ name: String, _ value: String) {
            if let index = items.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                items[index].value = value
            } else {
                items.append(URLQueryItem(name: name, value: value))
            }
        }
        set("BreakOnNonKeyFrames", "true")
        set("CopyTimestamps", "false")
        set("MinSegments", "2")
        components.queryItems = items
        return components.url
    }

    static func redactedBody(_ data: Data) -> String {
        let text = String(data: data.prefix(80), encoding: .utf8) ?? ""
        let lowered = text.lowercased()
        if lowered.contains("api_key") || lowered.contains("token") {
            return "body=redacted"
        }
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        return "body=\(collapsed)"
    }
}
