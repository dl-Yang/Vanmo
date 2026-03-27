import Foundation
import CoreMedia

// MARK: - Stream Info Models

struct DemuxerStreamInfo {
    let index: Int
    let type: DemuxerStreamType
    let codecID: UInt32
    let codecName: String
    let language: String?
    let title: String?
    let isDefault: Bool

    let width: Int32
    let height: Int32
    let frameRate: Double

    let sampleRate: Int32
    let channels: Int32
    let channelLayout: UInt64

    let subtitleCodecName: String?
}

enum DemuxerStreamType: Int {
    case video = 0
    case audio = 1
    case subtitle = 3
    case attachment = 4
    case unknown = -1
}

struct DemuxerPacket {
    let streamIndex: Int
    let data: Data
    let pts: Int64
    let dts: Int64
    let duration: Int64
    let isKeyframe: Bool
    let timeBase: CMTime
}

struct DemuxerChapter {
    let id: Int
    let title: String
    let startTime: Double
    let endTime: Double
}

// MARK: - DemuxerError

enum DemuxerError: LocalizedError {
    case openFailed(String)
    case streamInfoFailed(String)
    case notOpen
    case readFailed(String)
    case seekFailed(String)
    case noVideoStream
    case ffmpegNotAvailable

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "无法打开文件: \(msg)"
        case .streamInfoFailed(let msg): return "流信息解析失败: \(msg)"
        case .notOpen: return "文件未打开"
        case .readFailed(let msg): return "读取失败: \(msg)"
        case .seekFailed(let msg): return "跳转失败: \(msg)"
        case .noVideoStream: return "未找到视频流"
        case .ffmpegNotAvailable: return "FFmpeg 未集成，暂不支持此格式"
        }
    }
}

// MARK: - MKVDemuxer

final class MKVDemuxer {

    #if FFMPEG_ENABLED

    var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private(set) var streams: [DemuxerStreamInfo] = []
    private(set) var chapters: [DemuxerChapter] = []
    private(set) var duration: Double = 0

    private(set) var videoStreamIndex: Int = -1
    private(set) var audioStreamIndex: Int = -1
    private(set) var subtitleStreamIndex: Int = -1

    private let demuxQueue = DispatchQueue(label: "com.vanmo.demuxer", qos: .userInitiated)
    private var isOpen = false

    deinit {
        close()
    }

    // MARK: - Open / Close

    func open(url: URL) throws {
        close()

        let path = url.isFileURL ? url.path : url.absoluteString
        let isNetwork = !url.isFileURL
        VanmoLogger.player.info("[Demuxer] opening: \(path), isFileURL=\(url.isFileURL)")

        if isNetwork {
            try openNetworkStream(url: url)
        } else {
            try openLocalFile(path: path)
        }

        let infoRet = avformat_find_stream_info(formatContext, nil)
        guard infoRet >= 0 else {
            let errStr = ffmpegErrorString(infoRet)
            VanmoLogger.player.error("[Demuxer] avformat_find_stream_info failed: \(errStr) (code: \(infoRet))")
            close()
            throw DemuxerError.streamInfoFailed(errStr)
        }

        parseStreams()
        parseChapters()
        parseDuration()
        selectDefaultStreams()

        isOpen = true

        for stream in streams {
            VanmoLogger.player.info("[Demuxer] stream[\(stream.index)]: type=\(stream.type.rawValue), codec=\(stream.codecName), lang=\(stream.language ?? "nil"), \(stream.width)x\(stream.height), sampleRate=\(stream.sampleRate), channels=\(stream.channels)")
        }
        VanmoLogger.player.info("[Demuxer] opened: \(self.streams.count) streams, duration=\(String(format: "%.1f", self.duration))s, \(self.chapters.count) chapters, videoIdx=\(self.videoStreamIndex), audioIdx=\(self.audioStreamIndex), subIdx=\(self.subtitleStreamIndex)")
    }

    private func openNetworkStream(url: URL) throws {
        var opts: OpaquePointer?
        setupHTTPOptions(&opts)

        var cleanURLString = url.absoluteString
        if let user = url.user, let password = url.password {
            let credentials = "\(user):\(password)"
            let base64 = Data(credentials.utf8).base64EncodedString()
            av_dict_set(&opts, "headers", "Authorization: Basic \(base64)\r\n", 0)
            VanmoLogger.player.info("[Demuxer] extracted credentials from URL, using Authorization header")

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.user = nil
            components?.password = nil
            if let clean = components?.string {
                cleanURLString = clean
            }
        }

        VanmoLogger.player.info("[Demuxer] opening network stream: \(cleanURLString)")

        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let ret = avformat_open_input(&ctx, cleanURLString, nil, &opts)
        if opts != nil { av_dict_free(&opts) }

        guard ret >= 0 else {
            let errStr = ffmpegErrorString(ret)
            VanmoLogger.player.error("[Demuxer] avformat_open_input failed: \(errStr) (code: \(ret))")
            throw DemuxerError.openFailed(errStr)
        }
        formatContext = ctx

        if let pb = ctx?.pointee.pb {
            VanmoLogger.player.info("[Demuxer] avformat_open_input succeeded (network), seekable=\(pb.pointee.seekable)")
        } else {
            VanmoLogger.player.info("[Demuxer] avformat_open_input succeeded (network)")
        }
    }

    private func openLocalFile(path: String) throws {
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let ret = avformat_open_input(&ctx, path, nil, nil)
        guard ret >= 0 else {
            let errStr = ffmpegErrorString(ret)
            VanmoLogger.player.error("[Demuxer] avformat_open_input failed: \(errStr) (code: \(ret))")
            throw DemuxerError.openFailed(errStr)
        }
        formatContext = ctx
        VanmoLogger.player.info("[Demuxer] avformat_open_input succeeded (local)")
    }

    private func setupHTTPOptions(_ opts: inout OpaquePointer?) {
        av_dict_set(&opts, "timeout", "15000000", 0)
        av_dict_set(&opts, "reconnect", "1", 0)
        av_dict_set(&opts, "reconnect_streamed", "1", 0)
        av_dict_set(&opts, "reconnect_delay_max", "5", 0)
        av_dict_set(&opts, "user_agent", "Vanmo/1.0", 0)
        av_dict_set(&opts, "seekable", "1", 0)
        av_dict_set(&opts, "multiple_requests", "1", 0)
        av_dict_set(&opts, "http_persistent", "1", 0)
    }

    func close() {
        if formatContext != nil {
            avformat_close_input(&formatContext)
            formatContext = nil
        }
        streams.removeAll()
        chapters.removeAll()
        duration = 0
        videoStreamIndex = -1
        audioStreamIndex = -1
        subtitleStreamIndex = -1
        isOpen = false
    }

    // MARK: - Read Packets

    func readPacket() throws -> DemuxerPacket? {
        guard let ctx = formatContext else {
            throw DemuxerError.notOpen
        }

        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        let ret = av_read_frame(ctx, packet)
        if ret == Int32(bitPattern: 0xDFB9B0BB) { // AVERROR_EOF
            return nil
        }
        guard ret >= 0 else {
            throw DemuxerError.readFailed(ffmpegErrorString(ret))
        }

        guard let pkt = packet?.pointee else {
            throw DemuxerError.readFailed("Empty packet")
        }

        let streamIndex = Int(pkt.stream_index)
        let stream = ctx.pointee.streams[streamIndex]!.pointee
        let timeBase = CMTime(
            value: CMTimeValue(stream.time_base.num),
            timescale: CMTimeScale(stream.time_base.den)
        )

        let data = Data(bytes: pkt.data, count: Int(pkt.size))

        return DemuxerPacket(
            streamIndex: streamIndex,
            data: data,
            pts: pkt.pts,
            dts: pkt.dts,
            duration: pkt.duration,
            isKeyframe: (pkt.flags & AV_PKT_FLAG_KEY) != 0,
            timeBase: timeBase
        )
    }

    // MARK: - Seek

    func seek(to seconds: Double) throws {
        guard let ctx = formatContext else {
            throw DemuxerError.notOpen
        }

        let timestamp = Int64(seconds * 1_000_000) // AV_TIME_BASE
        let ret = avformat_seek_file(ctx, -1, Int64.min, timestamp, Int64.max, 1)

        guard ret >= 0 else {
            throw DemuxerError.seekFailed(ffmpegErrorString(ret))
        }
        avformat_flush(ctx)
    }

    // MARK: - Track Selection

    func selectAudio(streamIndex: Int) {
        guard streams.indices.contains(streamIndex),
              streams[streamIndex].type == .audio else { return }
        audioStreamIndex = streamIndex
    }

    func selectSubtitle(streamIndex: Int?) {
        if let index = streamIndex,
           streams.indices.contains(index),
           streams[index].type == .subtitle {
            subtitleStreamIndex = index
        } else {
            subtitleStreamIndex = -1
        }
    }

    // MARK: - Track Queries

    func audioStreams() -> [DemuxerStreamInfo] {
        streams.filter { $0.type == .audio }
    }

    func subtitleStreams() -> [DemuxerStreamInfo] {
        streams.filter { $0.type == .subtitle }
    }

    func videoStreams() -> [DemuxerStreamInfo] {
        streams.filter { $0.type == .video }
    }

    func extradata(for streamIndex: Int) -> Data? {
        guard let ctx = formatContext,
              streamIndex >= 0,
              streamIndex < ctx.pointee.nb_streams else { return nil }

        let stream = ctx.pointee.streams[streamIndex]!.pointee
        let codecpar = stream.codecpar.pointee
        guard codecpar.extradata != nil, codecpar.extradata_size > 0 else { return nil }
        return Data(bytes: codecpar.extradata, count: Int(codecpar.extradata_size))
    }

    // MARK: - Private

    private func parseStreams() {
        guard let ctx = formatContext else { return }

        let count = Int(ctx.pointee.nb_streams)
        var parsed: [DemuxerStreamInfo] = []

        for i in 0..<count {
            guard let stream = ctx.pointee.streams[i] else { continue }
            let codecpar = stream.pointee.codecpar.pointee
            let metadata = stream.pointee.metadata

            let streamType: DemuxerStreamType
            switch codecpar.codec_type {
            case AVMEDIA_TYPE_VIDEO:    streamType = .video
            case AVMEDIA_TYPE_AUDIO:    streamType = .audio
            case AVMEDIA_TYPE_SUBTITLE: streamType = .subtitle
            case AVMEDIA_TYPE_ATTACHMENT: streamType = .attachment
            default:                    streamType = .unknown
            }

            let codec = avcodec_find_decoder(codecpar.codec_id)
            let codecName = codec != nil ? String(cString: codec!.pointee.name) : "unknown"

            let info = DemuxerStreamInfo(
                index: i,
                type: streamType,
                codecID: codecpar.codec_id.rawValue,
                codecName: codecName,
                language: dictionaryValue(metadata, key: "language"),
                title: dictionaryValue(metadata, key: "title"),
                isDefault: (stream.pointee.disposition & AV_DISPOSITION_DEFAULT) != 0,
                width: codecpar.width,
                height: codecpar.height,
                frameRate: av_q2d(stream.pointee.avg_frame_rate),
                sampleRate: codecpar.sample_rate,
                channels: codecpar.ch_layout.nb_channels,
                channelLayout: codecpar.ch_layout.u.mask,
                subtitleCodecName: streamType == .subtitle ? codecName : nil
            )
            parsed.append(info)
        }

        streams = parsed
    }

    private func parseChapters() {
        guard let ctx = formatContext else { return }

        let count = Int(ctx.pointee.nb_chapters)
        var parsed: [DemuxerChapter] = []

        for i in 0..<count {
            guard let chapter = ctx.pointee.chapters[i] else { continue }
            let ch = chapter.pointee
            let timeBase = Double(ch.time_base.num) / Double(ch.time_base.den)
            let title = dictionaryValue(ch.metadata, key: "title") ?? "Chapter \(i + 1)"

            parsed.append(DemuxerChapter(
                id: i,
                title: title,
                startTime: Double(ch.start) * timeBase,
                endTime: Double(ch.end) * timeBase
            ))
        }

        chapters = parsed
    }

    private func parseDuration() {
        guard let ctx = formatContext else { return }
        if ctx.pointee.duration > 0 {
            duration = Double(ctx.pointee.duration) / 1_000_000.0
        }
    }

    private func selectDefaultStreams() {
        if let video = streams.first(where: { $0.type == .video }) {
            videoStreamIndex = video.index
        }

        let audioList = audioStreams()
        if let defaultAudio = audioList.first(where: { $0.isDefault }) {
            audioStreamIndex = defaultAudio.index
        } else if let firstAudio = audioList.first {
            audioStreamIndex = firstAudio.index
        }

        let subtitleList = subtitleStreams()
        if let defaultSub = subtitleList.first(where: { $0.isDefault }) {
            subtitleStreamIndex = defaultSub.index
        }
    }

    private func dictionaryValue(_ dict: OpaquePointer?, key: String) -> String? {
        guard let dict else { return nil }
        let entry = av_dict_get(dict, key, nil, 0)
        guard let entry else { return nil }
        return String(cString: entry.pointee.value)
    }

    private func ffmpegErrorString(_ errorCode: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        av_strerror(errorCode, &buffer, 1024)
        return String(cString: buffer)
    }

    #else

    // MARK: - Stub (FFmpeg not available)

    private(set) var streams: [DemuxerStreamInfo] = []
    private(set) var chapters: [DemuxerChapter] = []
    private(set) var duration: Double = 0
    private(set) var videoStreamIndex: Int = -1
    private(set) var audioStreamIndex: Int = -1
    private(set) var subtitleStreamIndex: Int = -1

    func open(url: URL) throws {
        throw DemuxerError.ffmpegNotAvailable
    }

    func close() {}

    func readPacket() throws -> DemuxerPacket? {
        throw DemuxerError.ffmpegNotAvailable
    }

    func seek(to seconds: Double) throws {
        throw DemuxerError.ffmpegNotAvailable
    }

    func selectAudio(streamIndex: Int) {}
    func selectSubtitle(streamIndex: Int?) {}

    func audioStreams() -> [DemuxerStreamInfo] { [] }
    func subtitleStreams() -> [DemuxerStreamInfo] { [] }
    func videoStreams() -> [DemuxerStreamInfo] { [] }
    func extradata(for streamIndex: Int) -> Data? { nil }

    #endif
}
