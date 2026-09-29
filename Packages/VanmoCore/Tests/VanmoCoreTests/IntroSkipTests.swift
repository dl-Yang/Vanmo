import CoreMedia
import XCTest
@testable import VanmoCore

final class IntroSkipTests: XCTestCase {
    func testIntroChapterTitles() {
        XCTAssertTrue(IntroSkipResolver.isIntroChapterTitle("Opening"))
        XCTAssertTrue(IntroSkipResolver.isIntroChapterTitle("INTRO"))
        XCTAssertTrue(IntroSkipResolver.isIntroChapterTitle("片头"))
        XCTAssertTrue(IntroSkipResolver.isIntroChapterTitle("OP"))
        XCTAssertTrue(IntroSkipResolver.isIntroChapterTitle("op: cold open"))
        XCTAssertFalse(IntroSkipResolver.isIntroChapterTitle("Chapter 1"))
        XCTAssertFalse(IntroSkipResolver.isIntroChapterTitle("Operation"))
        XCTAssertFalse(IntroSkipResolver.isIntroChapterTitle(""))
    }

    func testWindowPrefersManualMark() {
        let chapters = [
            Chapter(
                id: 0,
                title: "Opening",
                startTime: CMTime(seconds: 0, preferredTimescale: 600),
                endTime: CMTime(seconds: 80, preferredTimescale: 600)
            )
        ]
        let server = IntroSkipWindow(start: 0, end: 70)
        let window = IntroSkipResolver.window(chapters: chapters, serverWindow: server, manualEnd: 42)
        XCTAssertEqual(window, IntroSkipWindow(start: 0, end: 42))
    }

    func testWindowUsesServerThenChapter() {
        let chapters = [
            Chapter(
                id: 0,
                title: "Opening",
                startTime: CMTime(seconds: 0, preferredTimescale: 600),
                endTime: CMTime(seconds: 80, preferredTimescale: 600)
            )
        ]
        let server = IntroSkipWindow(start: 2, end: 65)
        XCTAssertEqual(
            IntroSkipResolver.window(chapters: chapters, serverWindow: server, manualEnd: nil),
            server
        )
        XCTAssertEqual(
            IntroSkipResolver.window(chapters: chapters, serverWindow: nil, manualEnd: nil),
            IntroSkipWindow(start: 0, end: 80)
        )
    }

    func testContainsRequiresRemainingGrace() {
        let window = IntroSkipWindow(start: 0, end: 80)
        XCTAssertTrue(window.contains(10))
        XCTAssertFalse(window.contains(79))
        XCTAssertFalse(window.contains(80))
    }

    func testEmbyChapterParserUsesNextStartAsEnd() throws {
        let json = """
        {
          "Chapters": [
            {"StartPositionTicks": 0, "Name": "Opening", "MarkerType": "Intro"},
            {"StartPositionTicks": 900000000, "Name": "Main"}
          ]
        }
        """.data(using: .utf8)!
        let window = try IntroMarkerParser.embyWindow(from: json)
        XCTAssertEqual(window?.start, 0)
        XCTAssertEqual(window?.end, 90)
    }

    func testPlexMarkerParserReadsIntroOffsets() throws {
        let json = """
        {
          "MediaContainer": {
            "Metadata": [
              {
                "Marker": [
                  {"type": "intro", "startTimeOffset": 1500, "endTimeOffset": 72500}
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let window = try IntroMarkerParser.plexWindow(from: json)
        XCTAssertEqual(window?.start, 1.5)
        XCTAssertEqual(window?.end, 72.5)
    }
}

final class PlaybackVideoQualityTests: XCTestCase {
    func testAvailabilityFallsBackWhenSourceIsSmaller() {
        XCTAssertFalse(PlaybackVideoQuality.p1080.isAvailable(sourceHeight: 720))
        XCTAssertTrue(PlaybackVideoQuality.p1080.isAvailable(sourceHeight: 1080))
        XCTAssertTrue(PlaybackVideoQuality.p720.isAvailable(sourceHeight: 1080))
        XCTAssertEqual(
            PlaybackVideoQuality.resolved(requested: .p1080, sourceHeight: 720),
            .original
        )
        XCTAssertEqual(
            PlaybackVideoQuality.resolved(requested: .p1080, sourceHeight: 1080),
            .p1080
        )
        XCTAssertEqual(
            PlaybackVideoQuality.resolved(requested: .p720, sourceHeight: 2160),
            .p720
        )
    }

    func testScaleFilterAndBitrate() {
        XCTAssertEqual(PlaybackVideoQuality.p720.ffmpegScaleFilter, "scale=-2:720")
        XCTAssertNil(PlaybackVideoQuality.original.ffmpegScaleFilter)
        XCTAssertEqual(PlaybackVideoQuality.p720.preferredMaximumResolution?.height, 720)
        XCTAssertEqual(PlaybackVideoQuality.p360.preferredPeakBitRate, 1_000_000)
        XCTAssertNil(PlaybackVideoQuality.original.preferredPeakBitRate)
    }
}

final class PlaybackQualityStreamTests: XCTestCase {
    func testOriginalKeepsDirectURL() throws {
        let direct = try XCTUnwrap(URL(string: "https://emby.example:8920/emby/Videos/253013/stream?static=true&api_key=SECRET"))
        let result = PlaybackQualityStream.playbackURL(
            directURL: direct,
            serverItemID: "253013",
            connectionType: .emby,
            quality: .original,
            startTime: 12.5
        )
        XCTAssertEqual(result, direct)
    }

    func testEmby360IncludesHeightBitrateAndStartTicks() throws {
        let direct = try XCTUnwrap(URL(string: "https://emby.example:8920/emby/Videos/253013/stream?static=true&api_key=SECRET"))
        let result = PlaybackQualityStream.playbackURL(
            directURL: direct,
            serverItemID: "253013",
            connectionType: .jellyfin,
            quality: .p360,
            startTime: 12.5
        )
        XCTAssertTrue(result.path.hasSuffix("/Videos/253013/master.m3u8"))
        let items = try queryItems(result)
        XCTAssertEqual(items["MaxHeight"], "360")
        XCTAssertEqual(items["MaxWidth"], "640")
        XCTAssertEqual(items["VideoBitrate"], "1000000")
        XCTAssertEqual(items["MaxStreamingBitrate"], "1128000")
        XCTAssertEqual(items["SegmentContainer"], "ts")
        XCTAssertEqual(items["TranscodingProtocol"], "hls")
        XCTAssertEqual(items["AudioBitrate"], "128000")
        XCTAssertEqual(items["VideoCodec"], "h264")
        XCTAssertEqual(items["AudioCodec"], "aac")
        XCTAssertEqual(items["StartTimeTicks"], "125000000")
        XCTAssertEqual(items["DeviceId"], PlatformDeviceInfo.deviceIdentifier)
        XCTAssertFalse(items["PlaySessionId"]?.isEmpty ?? true)
        XCTAssertEqual(items["api_key"], "SECRET")
        XCTAssertFalse(result.safePlaybackLogDescription.contains("api_key"))
        XCTAssertFalse(result.safePlaybackLogDescription.contains("SECRET"))
        let summary = PlaybackQualityStream.debugSummary(of: result)
        XCTAssertTrue(summary.contains("TranscodingProtocol=hls"))
        XCTAssertTrue(summary.contains("MaxHeight=360"))
        XCTAssertTrue(summary.contains("VideoBitrate=1000000"))
        XCTAssertFalse(summary.contains("api_key"))
        XCTAssertFalse(summary.contains("SECRET"))
        XCTAssertTrue(PrefetchConfig.isMediaServerStreamURL(result))
    }

    func testPlex360UsesTranscodePlaylist() throws {
        let direct = try XCTUnwrap(URL(string: "https://plex.example:32400/library/parts/1/file.mkv?X-Plex-Token=TOKEN"))
        let result = PlaybackQualityStream.playbackURL(
            directURL: direct,
            serverItemID: "4242",
            connectionType: .plex,
            quality: .p360,
            startTime: 12.4
        )
        XCTAssertEqual(result.path, "/video/:/transcode/universal/start.m3u8")
        let items = try queryItems(result)
        XCTAssertEqual(items["directPlay"], "0")
        XCTAssertEqual(items["directStream"], "0")
        XCTAssertEqual(items["protocol"], "hls")
        XCTAssertEqual(items["maxVideoBitrate"], "1000")
        XCTAssertEqual(items["videoResolution"], "640x360")
        XCTAssertEqual(items["offset"], "12")
        XCTAssertEqual(items["X-Plex-Incomplete-Segments"], "0")
        XCTAssertEqual(items["path"], "/library/metadata/4242")
        XCTAssertEqual(items["X-Plex-Token"], "TOKEN")
        XCTAssertEqual(items["X-Plex-Product"], "Vanmo")
        XCTAssertEqual(items["X-Plex-Platform"], "macOS")
        XCTAssertEqual(items["X-Plex-Client-Identifier"], PlexCredentialStore.clientIdentifier)
        XCTAssertFalse(items["session"]?.isEmpty ?? true)
        XCTAssertFalse(result.safePlaybackLogDescription.contains("X-Plex-Token"))
        XCTAssertFalse(result.safePlaybackLogDescription.contains("TOKEN"))
        XCTAssertTrue(PrefetchConfig.isMediaServerStreamURL(result))
    }

    func testEmbyPlaybackInfoBodyForcesTranscode() throws {
        let data = try XCTUnwrap(EmbyTranscodeClient.requestBody(quality: .p360, startTime: 12.5))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["MaxStreamingBitrate"] as? Int, 1_128_000)
        XCTAssertEqual(json["StartTimeTicks"] as? Int, 125_000_000)
        let profile = try XCTUnwrap(json["DeviceProfile"] as? [String: Any])
        let direct = try XCTUnwrap(profile["DirectPlayProfiles"] as? [Any])
        XCTAssertTrue(direct.isEmpty)
        let transcodes = try XCTUnwrap(profile["TranscodingProfiles"] as? [[String: Any]])
        XCTAssertEqual(transcodes.first?["Protocol"] as? String, "hls")
        XCTAssertEqual(transcodes.first?["VideoCodec"] as? String, "h264")
        XCTAssertEqual(transcodes.first?["Container"] as? String, "ts")
        XCTAssertNil(transcodes.first?["CopyTimestamps"])
        XCTAssertEqual(transcodes.first?["BreakOnNonKeyFrames"] as? Bool, true)
        XCTAssertEqual(transcodes.first?["MinSegments"] as? Int, 2)
    }

    func testEmbyTranscodingURLBecomesAbsolute() throws {
        let direct = try XCTUnwrap(URL(string: "https://emby.example:8920/emby/Videos/253013/stream?static=true&api_key=SECRET"))
        let absolute = try XCTUnwrap(EmbyTranscodeClient.absoluteURL(
            transcodingURL: "/emby/videos/253013/master.m3u8?MediaSourceId=253013",
            directURL: direct,
            apiKey: "SECRET"
        ))
        XCTAssertEqual(absolute.host, "emby.example")
        XCTAssertTrue(absolute.path.hasSuffix("/master.m3u8"))
        let items = try queryItems(absolute)
        XCTAssertEqual(items["api_key"], "SECRET")
        XCTAssertFalse(absolute.safePlaybackLogDescription.contains("SECRET"))
    }

    func testMuxedMasterDropsSeparateAudio() {
        let base = URL(string: "https://emby.example/videos/253013/master.m3u8?MediaSourceId=1")!
        let playlist = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="JP",URI="hls/0.m3u8?a=1"
        #EXT-X-STREAM-INF:BANDWIDTH=2438412,AUDIO="audio"
        hls/main.m3u8?v=1
        """
        let rewritten = EmbyHlsPlaylist.muxedMaster(playlist: playlist, baseURL: base)
        XCTAssertEqual(rewritten.removedAudioGroups, 1)
        XCTAssertFalse(rewritten.playlist.uppercased().contains("TYPE=AUDIO"))
        XCTAssertFalse(rewritten.playlist.uppercased().contains("AUDIO="))
        XCTAssertTrue(rewritten.playlist.contains("https://emby.example/videos/253013/hls/main.m3u8?v=1"))
    }

    func testMediaPlaylistStartsAtRequestedTime() {
        let playlist = """
        #EXTM3U
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:3.000,
        seg.ts?runtimeTicks=17220000000
        """
        let started = EmbyHlsPlaylist.applyingStart(playlist: playlist, startTime: 1722)
        XCTAssertTrue(started.contains("#EXT-X-START:TIME-OFFSET=1722.000,PRECISE=NO"))
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1
        main.m3u8
        """
        XCTAssertFalse(EmbyHlsPlaylist.applyingStart(playlist: master, startTime: 1722).contains("EXT-X-START"))
        XCTAssertEqual(EmbyHlsPlaylist.applyingStart(playlist: playlist, startTime: 0), playlist)
    }

    func testAlignedTranscodeURLForcesTimestampFlags() throws {
        let source = try XCTUnwrap(URL(string: "https://emby.example/videos/1/master.m3u8?MediaSourceId=1&VideoBitrate=1000"))
        let aligned = try XCTUnwrap(EmbyTranscodeClient.alignedTranscodeURL(source))
        let items = try queryItems(aligned)
        XCTAssertEqual(items["BreakOnNonKeyFrames"], "true")
        XCTAssertEqual(items["CopyTimestamps"], "false")
        XCTAssertEqual(items["MinSegments"], "2")
        XCTAssertEqual(items["VideoBitrate"], "1000")
        XCTAssertFalse(aligned.safePlaybackLogDescription.contains("api_key"))
    }

    func testPrimerSelectsSegmentAtRuntimeTicks() throws {
        let base = URL(string: "https://emby.example/videos/1/main.m3u8")!
        let playlist = """
        #EXTM3U
        #EXTINF:3.000000,
        seg0.ts?runtimeTicks=0&actualSegmentLengthTicks=30000000
        #EXTINF:3.000000,
        seg1.ts?runtimeTicks=30000000&actualSegmentLengthTicks=30000000
        #EXTINF:3.000000,
        seg2.ts?runtimeTicks=10950000000&actualSegmentLengthTicks=30000000
        """
        guard case .segment(let target) = HlsTranscodePrimer.step(playlist: playlist, baseURL: base, startTime: 1095) else {
            return XCTFail("expected a segment")
        }
        XCTAssertEqual(target.start, 1095)
        XCTAssertTrue(target.url.absoluteString.contains("seg2.ts"))
    }

    func testPrimerSkipsDirectStream() {
        let stream = URL(string: "https://emby.example/emby/Videos/253013/stream?static=true")!
        let playlist = URL(string: "https://emby.example/videos/253013/master.m3u8")!
        XCTAssertFalse(HlsTranscodePrimer.shouldPrime(playlistURL: stream, startTime: 2233))
        XCTAssertTrue(HlsTranscodePrimer.shouldPrime(playlistURL: playlist, startTime: 2233))
        XCTAssertFalse(HlsTranscodePrimer.shouldPrime(playlistURL: playlist, startTime: 0))
    }

    func testMpegTsVideoLeadWhenAudioTimestampIsLater() throws {
        let data = Self.tsPacket(streamID: 0xE0, pid: 0x0100, pts: [0x21, 0x00, 0x01, 0x00, 0x01])
            + Self.tsPacket(streamID: 0xC0, pid: 0x0101, pts: [0x21, 0x00, 0x03, 0x19, 0x41])
        let timing = try XCTUnwrap(MpegTsTiming.measurement(in: data))
        XCTAssertEqual(timing.startLeadMilliseconds, 400)
        XCTAssertEqual(timing.overlapLeadMilliseconds, 400 as Int?)
        XCTAssertEqual(MpegTsTiming.videoLeadMilliseconds(in: data), 400)
        let aligned = try XCTUnwrap(MpegTsTiming.aligningAudioToVideo(data))
        XCTAssertEqual(aligned.action, .shift)
        XCTAssertEqual(aligned.shiftMilliseconds, -400)
        XCTAssertEqual(aligned.data.count, data.count)
        let shifted = try XCTUnwrap(MpegTsTiming.measurement(in: aligned.data))
        XCTAssertEqual(shifted.startLeadMilliseconds, 0)
        XCTAssertEqual(shifted.overlapLeadMilliseconds, 0 as Int?)
    }

    func testMpegTsShiftsWhenAudioNeverReachesVideo() throws {
        let data = Self.tsPacket(streamID: 0xC0, pid: 0x0101, pts: Self.ptsBytes(seconds: 0))
            + Self.tsPacket(streamID: 0xE0, pid: 0x0100, pts: Self.ptsBytes(seconds: 1))
        let timing = try XCTUnwrap(MpegTsTiming.measurement(in: data))
        XCTAssertEqual(timing.startLeadMilliseconds, -1000)
        XCTAssertNil(timing.overlapLeadMilliseconds)
        let aligned = try XCTUnwrap(MpegTsTiming.aligningAudioToVideo(data))
        XCTAssertEqual(aligned.action, .shift)
        XCTAssertEqual(aligned.shiftMilliseconds, 1000)
        XCTAssertEqual(aligned.data.count, data.count)
        XCTAssertEqual(Array([UInt8](aligned.data)[13..<18]), Self.ptsBytes(seconds: 1))
    }

    func testMpegTsTrimsLeadingAudioWithoutShiftingOverlap() throws {
        let early = Self.tsPacket(streamID: 0xC0, pid: 0x0101, pts: Self.ptsBytes(seconds: 0), continuity: 0)
        let earlyContinue = Self.tsContinuation(pid: 0x0101, continuity: 1)
        let video = Self.tsPacket(streamID: 0xE0, pid: 0x0100, pts: Self.ptsBytes(seconds: 1), continuity: 0)
        let overlapAudio = Self.tsPacket(
            streamID: 0xC0,
            pid: 0x0101,
            pts: Self.ptsBytes(seconds: 1),
            continuity: 2
        )
        let data = early + earlyContinue + video + overlapAudio
        let timing = try XCTUnwrap(MpegTsTiming.measurement(in: data))
        XCTAssertEqual(timing.startLeadMilliseconds, -1000)
        XCTAssertEqual(timing.overlapLeadMilliseconds, 0 as Int?)
        let aligned = try XCTUnwrap(MpegTsTiming.aligningAudioToVideo(data))
        XCTAssertEqual(aligned.action, .trim)
        XCTAssertEqual(aligned.shiftMilliseconds, 0)
        XCTAssertEqual(aligned.startLeadMilliseconds, -1000)
        XCTAssertEqual(aligned.overlapLeadMilliseconds, 0 as Int?)
        XCTAssertEqual(aligned.data.count, 188 * 2)
        let keptAudio = [UInt8](aligned.data.dropFirst(188))
        XCTAssertEqual(Array(keptAudio[13..<18]), Self.ptsBytes(seconds: 1))
        XCTAssertEqual(keptAudio[3] & 0x0F, 2)
        let after = try XCTUnwrap(MpegTsTiming.measurement(in: aligned.data))
        XCTAssertEqual(after.startLeadMilliseconds, 0)
        XCTAssertEqual(after.overlapLeadMilliseconds, 0 as Int?)
    }

    func testSegmentProxyPathKeepsTransportExtension() {
        let segment = URL(string: "https://emby.example/videos/1/hls/0.ts?runtimeTicks=1")!
        let playlist = URL(string: "https://emby.example/videos/1/main.m3u8?id=1")!
        XCTAssertEqual(EmbyHlsPlaylist.playbackProxyPath(for: segment), "/segment.ts")
        XCTAssertEqual(EmbyHlsPlaylist.playbackProxyPath(for: playlist), "/media.m3u8")
    }

    private static func tsPacket(
        streamID: UInt8,
        pid: UInt16,
        pts: [UInt8],
        continuity: UInt8 = 0
    ) -> Data {
        var packet = [UInt8](repeating: 0xFF, count: 188)
        packet[0] = 0x47
        packet[1] = 0x40 | UInt8((pid >> 8) & 0x1F)
        packet[2] = UInt8(pid & 0xFF)
        packet[3] = 0x10 | (continuity & 0x0F)
        let pes: [UInt8] = [0x00, 0x00, 0x01, streamID, 0x00, 0x08, 0x80, 0x80, 0x05]
        for (index, byte) in pes.enumerated() {
            packet[4 + index] = byte
        }
        for (index, byte) in pts.enumerated() {
            packet[13 + index] = byte
        }
        return Data(packet)
    }

    private static func tsContinuation(pid: UInt16, continuity: UInt8) -> Data {
        var packet = [UInt8](repeating: 0xFF, count: 188)
        packet[0] = 0x47
        packet[1] = UInt8((pid >> 8) & 0x1F)
        packet[2] = UInt8(pid & 0xFF)
        packet[3] = 0x10 | (continuity & 0x0F)
        return Data(packet)
    }

    private static func ptsBytes(seconds: Double) -> [UInt8] {
        let ticks = UInt64((seconds * 90_000).rounded()) & 0x1FFFFFFFF
        let high = (ticks >> 30) & 0x7
        let middle = (ticks >> 15) & 0x7FFF
        let low = ticks & 0x7FFF
        return [
            0x20 | UInt8(high << 1) | 0x01,
            UInt8((middle >> 7) & 0xFF),
            UInt8(((middle & 0x7F) << 1) | 0x01),
            UInt8((low >> 7) & 0xFF),
            UInt8(((low & 0x7F) << 1) | 0x01)
        ]
    }

    func testLocalFileStaysDirect() throws {
        let direct = try XCTUnwrap(URL(string: "file:///tmp/movie.mkv"))
        let result = PlaybackQualityStream.playbackURL(
            directURL: direct,
            serverItemID: nil,
            connectionType: .smb,
            quality: .p360,
            startTime: 10
        )
        XCTAssertEqual(result, direct)
    }

    private func queryItems(_ url: URL) throws -> [String: String] {
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
