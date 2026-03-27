import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Combine
import UIKit

final class FFmpegPlayerEngine: PlayerEngine {

    // MARK: - Publishers

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let durationSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let bufferProgressSubject = CurrentValueSubject<Double, Never>(0)

    var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { currentTimeSubject.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<CMTime, Never> { durationSubject.eraseToAnyPublisher() }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { bufferProgressSubject.eraseToAnyPublisher() }

    var state: PlaybackState { stateSubject.value }
    var currentTime: CMTime { currentTimeSubject.value }
    var duration: CMTime { durationSubject.value }

    var playbackRate: Float = 1.0 {
        didSet {
            audioRenderer?.setRate(playbackRate)
        }
    }

    // MARK: - Components

    private let demuxer = MKVDemuxer()
    private var videoRenderer: VideoRenderer?

    // MARK: - Render View Access

    var renderView: VideoRenderer? { videoRenderer }

    // MARK: - Chapters

    var availableChapters: [Chapter] {
        demuxer.chapters.map { ch in
            Chapter(
                id: ch.id,
                title: ch.title,
                startTime: CMTime(seconds: ch.startTime, preferredTimescale: 600),
                endTime: CMTime(seconds: ch.endTime, preferredTimescale: 600)
            )
        }
    }

    #if FFMPEG_ENABLED

    // MARK: - FFmpeg Components

    private var videoDecoder: HardwareDecoder?
    private var audioRenderer: AudioRenderer?

    private var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private var audioCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitleCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private var swsContext: OpaquePointer?
    private var swrContext: OpaquePointer?

    // MARK: - Threading

    private var demuxThread: Thread?
    private var videoDecodeThread: Thread?
    private var audioDecodeThread: Thread?
    private var isRunning = false
    private var isPaused = false
    private let pauseLock = NSCondition()

    private let videoPacketQueue = PacketQueue()
    private let audioPacketQueue = PacketQueue()

    // MARK: - Sync

    private var audioClock: Double = 0
    private var videoClock: Double = 0
    private var seekRequested = false
    private var seekTarget: Double = 0
    private var currentURL: URL?
    private let noPTSValue = Int64.min

    // MARK: - Frame Reorder Buffer & Display Link

    private var frameBuffer: [DecodedVideoFrame] = []
    private let frameBufferLock = NSLock()
    private let maxFrameBufferSize = 16
    private var displayLink: CADisplayLink?
    private var lastDisplayedPTS: Double = -1

    deinit {
        stop()
    }

    // MARK: - PlayerEngine Protocol

    func load(url: URL, startPosition: CMTime? = nil) async throws {
        VanmoLogger.player.info("[FFmpeg] load() called, url: \(url.absoluteString)")
        stop()
        stateSubject.send(.loading)
        currentURL = url

        do {
            VanmoLogger.player.info("[FFmpeg] opening demuxer...")
            try demuxer.open(url: url)
            VanmoLogger.player.info("[FFmpeg] demuxer opened, videoStreamIndex: \(self.demuxer.videoStreamIndex), audioStreamIndex: \(self.demuxer.audioStreamIndex)")
        } catch {
            VanmoLogger.player.error("[FFmpeg] demuxer open failed: \(error.localizedDescription)")
            stateSubject.send(.error(error.localizedDescription))
            throw error
        }

        guard demuxer.videoStreamIndex >= 0 else {
            let err = DemuxerError.noVideoStream
            VanmoLogger.player.error("[FFmpeg] no video stream found")
            stateSubject.send(.error(err.localizedDescription))
            throw err
        }

        let totalDuration = CMTime(seconds: demuxer.duration, preferredTimescale: 600)
        durationSubject.send(totalDuration)
        VanmoLogger.player.info("[FFmpeg] duration: \(self.demuxer.duration)s")

        VanmoLogger.player.info("[FFmpeg] setting up video decoder...")
        try setupVideoDecoder()
        VanmoLogger.player.info("[FFmpeg] video decoder ready, hw=\(self.videoDecoder?.isHardwareAccelerated ?? false), swCodecCtx=\(self.videoCodecContext != nil)")

        VanmoLogger.player.info("[FFmpeg] setting up audio decoder...")
        setupAudioDecoder()
        VanmoLogger.player.info("[FFmpeg] audio decoder ready, audioCodecCtx=\(self.audioCodecContext != nil), audioRenderer=\(self.audioRenderer != nil)")

        VanmoLogger.player.info("[FFmpeg] creating VideoRenderer on main thread...")
        videoRenderer = await MainActor.run { VideoRenderer() }
        setupVideoDecoderCallback()

        if let startPosition, startPosition.seconds > 0 {
            VanmoLogger.player.info("[FFmpeg] seeking to start position: \(startPosition.seconds)s")
            try demuxer.seek(to: startPosition.seconds)
        }

        VanmoLogger.player.info("[FFmpeg] starting decode threads...")
        startThreads()
        stateSubject.send(.paused)

        VanmoLogger.player.info("[FFmpeg] load complete: \(url.lastPathComponent)")
    }

    func play() {
        VanmoLogger.player.info("[FFmpeg] play() called, current state: \(String(describing: self.state))")
        guard state != .playing else {
            VanmoLogger.player.info("[FFmpeg] already playing, ignoring")
            return
        }
        isPaused = false
        pauseLock.lock()
        pauseLock.broadcast()
        pauseLock.unlock()
        audioRenderer?.resume()
        stateSubject.send(.playing)
        VanmoLogger.player.info("[FFmpeg] now playing")
    }

    func pause() {
        VanmoLogger.player.info("[FFmpeg] pause() called")
        guard state == .playing else { return }
        isPaused = true
        audioRenderer?.pause()
        stateSubject.send(.paused)
    }

    func seek(to time: CMTime) async {
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0 else { return }

        seekRequested = true
        seekTarget = seconds

        videoPacketQueue.flush()
        audioPacketQueue.flush()
        flushFrameBuffer()

        videoDecoder?.flush()
        if let ctx = videoCodecContext { avcodec_flush_buffers(ctx) }
        if let ctx = audioCodecContext { avcodec_flush_buffers(ctx) }

        audioRenderer?.flush()

        do {
            try demuxer.seek(to: seconds)
        } catch {
            VanmoLogger.player.error("Seek failed: \(error.localizedDescription)")
        }

        seekRequested = false
        currentTimeSubject.send(time)
    }

    func stop() {
        isRunning = false
        isPaused = false

        pauseLock.lock()
        pauseLock.broadcast()
        pauseLock.unlock()

        stopDisplayLink()
        flushFrameBuffer()

        videoPacketQueue.abort()
        audioPacketQueue.abort()

        demuxThread?.cancel()
        videoDecodeThread?.cancel()
        audioDecodeThread?.cancel()
        demuxThread = nil
        videoDecodeThread = nil
        audioDecodeThread = nil

        audioRenderer?.stop()
        videoDecoder?.invalidate()
        cleanupCodecContexts()
        demuxer.close()

        videoRenderer?.clear()
        videoRenderer = nil
        audioRenderer = nil
        videoDecoder = nil

        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
        bufferProgressSubject.send(0)
    }

    func selectAudioTrack(index: Int) {
        let audioStreams = demuxer.audioStreams()
        guard index < audioStreams.count else { return }
        demuxer.selectAudio(streamIndex: audioStreams[index].index)
        setupAudioDecoder()
    }

    func selectSubtitleTrack(index: Int?) {
        if let index {
            let subtitleStreams = demuxer.subtitleStreams()
            guard index < subtitleStreams.count else { return }
            demuxer.selectSubtitle(streamIndex: subtitleStreams[index].index)
        } else {
            demuxer.selectSubtitle(streamIndex: nil)
        }
    }

    func availableAudioTracks() -> [AudioTrackInfo] {
        demuxer.audioStreams().enumerated().map { index, stream in
            AudioTrackInfo(
                id: index,
                language: stream.language,
                title: stream.title ?? stream.codecName,
                codec: stream.codecName.uppercased(),
                channels: Int(stream.channels)
            )
        }
    }

    func availableSubtitleTracks() -> [SubtitleTrackInfo] {
        demuxer.subtitleStreams().enumerated().map { index, stream in
            SubtitleTrackInfo(
                id: index,
                language: stream.language,
                title: stream.title ?? stream.subtitleCodecName,
                isEmbedded: true,
                fileURL: nil
            )
        }
    }

    // MARK: - Codec Setup

    private func setupVideoDecoder() throws {
        let videoStreams = demuxer.videoStreams()
        VanmoLogger.player.info("[FFmpeg] setupVideoDecoder: found \(videoStreams.count) video stream(s)")
        guard let videoStream = videoStreams.first else {
            throw DemuxerError.noVideoStream
        }
        VanmoLogger.player.info("[FFmpeg] video stream: codec=\(videoStream.codecName), codecID=\(videoStream.codecID), \(videoStream.width)x\(videoStream.height), fps=\(videoStream.frameRate)")

        let codecID = AVCodecID(rawValue: videoStream.codecID)
        guard let codec = avcodec_find_decoder(codecID) else {
            VanmoLogger.player.error("[FFmpeg] avcodec_find_decoder failed for codecID=\(videoStream.codecID)")
            throw PlayerError.unsupportedFormat
        }
        VanmoLogger.player.info("[FFmpeg] found decoder: \(String(cString: codec.pointee.name))")

        let codecCtx = avcodec_alloc_context3(codec)
        guard let codecCtx,
              let fmtCtx = demuxer.formatContext else {
            VanmoLogger.player.error("[FFmpeg] avcodec_alloc_context3 or formatContext is nil")
            throw PlayerError.loadFailed("无法创建视频解码器上下文")
        }
        guard let stream = fmtCtx.pointee.streams?[videoStream.index] else {
            VanmoLogger.player.error("[FFmpeg] stream at index \(videoStream.index) is nil")
            throw PlayerError.loadFailed("无法创建视频解码器上下文")
        }
        avcodec_parameters_to_context(codecCtx, stream.pointee.codecpar)

        let hwCodecType = mapToVideoToolboxCodec(codecID)
        let hwSupported = HardwareDecoder.isCodecSupported(hwCodecType)
        VanmoLogger.player.info("[FFmpeg] hwCodecType=\(hwCodecType), hwSupported=\(hwSupported)")

        var useHardware = false
        if hwSupported {
            do {
                let hwDec = HardwareDecoder()
                let extradata = demuxer.extradata(for: videoStream.index)
                VanmoLogger.player.info("[FFmpeg] configuring HW decoder, extradata size=\(extradata?.count ?? 0)")
                try hwDec.configure(
                    codec: hwCodecType,
                    width: videoStream.width,
                    height: videoStream.height,
                    extradata: extradata
                )
                videoDecoder = hwDec
                useHardware = true
                VanmoLogger.player.info("[FFmpeg] hardware decode configured for \(videoStream.codecName)")
            } catch {
                VanmoLogger.player.warning("[FFmpeg] hardware decoder setup failed: \(error.localizedDescription), falling back to software decode")
                videoDecoder = nil
            }
        }

        if !useHardware {
            VanmoLogger.player.info("[FFmpeg] using software decode for \(videoStream.codecName)")
            let ret = avcodec_open2(codecCtx, codec, nil)
            guard ret >= 0 else {
                VanmoLogger.player.error("[FFmpeg] avcodec_open2 failed: \(ret)")
                avcodec_free_context(&videoCodecContext)
                throw PlayerError.loadFailed("无法打开视频解码器")
            }
            self.videoCodecContext = codecCtx
            VanmoLogger.player.info("[FFmpeg] software decoder opened successfully")
        }
    }

    private func setupAudioDecoder() {
        VanmoLogger.player.info("[FFmpeg] setupAudioDecoder: audioStreamIndex=\(self.demuxer.audioStreamIndex)")
        if audioCodecContext != nil {
            avcodec_free_context(&audioCodecContext)
        }

        let selectedIndex = demuxer.audioStreamIndex
        guard selectedIndex >= 0,
              let audioStream = demuxer.audioStreams().first(where: { $0.index == selectedIndex }) else {
            VanmoLogger.player.warning("[FFmpeg] no audio stream selected or available")
            return
        }
        VanmoLogger.player.info("[FFmpeg] audio stream: codec=\(audioStream.codecName), codecID=\(audioStream.codecID), sampleRate=\(audioStream.sampleRate), channels=\(audioStream.channels)")

        let codecID = AVCodecID(rawValue: audioStream.codecID)
        guard let codec = avcodec_find_decoder(codecID) else {
            VanmoLogger.player.error("[FFmpeg] avcodec_find_decoder failed for audio codecID=\(audioStream.codecID)")
            return
        }
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            VanmoLogger.player.error("[FFmpeg] avcodec_alloc_context3 failed for audio")
            return
        }
        guard let fmtCtx = demuxer.formatContext else {
            VanmoLogger.player.error("[FFmpeg] formatContext is nil during audio setup")
            return
        }
        guard let stream = fmtCtx.pointee.streams?[audioStream.index] else {
            VanmoLogger.player.error("[FFmpeg] audio stream at index \(audioStream.index) is nil")
            return
        }

        avcodec_parameters_to_context(codecCtx, stream.pointee.codecpar)
        let openRet = avcodec_open2(codecCtx, codec, nil)
        guard openRet >= 0 else {
            VanmoLogger.player.error("[FFmpeg] avcodec_open2 failed for audio: \(openRet)")
            return
        }
        audioCodecContext = codecCtx

        let sampleRate = Double(audioStream.sampleRate > 0 ? audioStream.sampleRate : 44100)
        let outputChannels: UInt32 = 2
        VanmoLogger.player.info("[FFmpeg] creating AudioRenderer: sampleRate=\(sampleRate), outputChannels=\(outputChannels), sourceChannels=\(audioStream.channels)")
        audioRenderer = AudioRenderer(sampleRate: sampleRate, channels: outputChannels)
        audioRenderer?.setRate(playbackRate)
        audioRenderer?.start()

        setupSwrContext(codecCtx: codecCtx, outSampleRate: Int32(sampleRate), outChannels: Int32(outputChannels))
        VanmoLogger.player.info("[FFmpeg] audio decoder setup complete, swrContext=\(self.swrContext != nil)")
    }

    private func setupSwrContext(codecCtx: UnsafeMutablePointer<AVCodecContext>, outSampleRate: Int32, outChannels: Int32) {
        if swrContext != nil { swr_free(&swrContext) }

        var outLayout = AVChannelLayout()
        av_channel_layout_default(&outLayout, outChannels)

        var swrCtx: OpaquePointer?
        swr_alloc_set_opts2(
            &swrCtx, &outLayout, AV_SAMPLE_FMT_FLT, outSampleRate,
            &codecCtx.pointee.ch_layout, codecCtx.pointee.sample_fmt,
            codecCtx.pointee.sample_rate, 0, nil
        )

        if let swrCtx {
            swr_init(swrCtx)
            swrContext = swrCtx
        }
    }

    private var hwFrameCallbackCount = 0

    private func setupVideoDecoderCallback() {
        VanmoLogger.player.info("[FFmpeg] setupVideoDecoderCallback, videoDecoder=\(self.videoDecoder != nil)")
        videoDecoder?.onFrameDecoded = { [weak self] frame in
            guard let self else { return }
            self.hwFrameCallbackCount += 1
            if self.hwFrameCallbackCount == 1 {
                VanmoLogger.player.info("[FFmpeg][HWCallback] first decoded frame received: \(frame.width)x\(frame.height), pts=\(frame.pts.seconds)s")
            }
            let seconds = frame.pts.seconds
            guard seconds.isFinite else { return }

            self.enqueueToFrameBuffer(frame)
        }
    }

    // MARK: - Thread Management

    private func startThreads() {
        isRunning = true
        isPaused = false

        demuxThread = Thread { [weak self] in self?.demuxLoop() }
        demuxThread?.name = "com.vanmo.demux"
        demuxThread?.qualityOfService = .userInitiated
        demuxThread?.start()

        videoDecodeThread = Thread { [weak self] in self?.videoDecodeLoop() }
        videoDecodeThread?.name = "com.vanmo.videoDecode"
        videoDecodeThread?.qualityOfService = .userInitiated
        videoDecodeThread?.start()

        audioDecodeThread = Thread { [weak self] in self?.audioDecodeLoop() }
        audioDecodeThread?.name = "com.vanmo.audioDecode"
        audioDecodeThread?.qualityOfService = .userInitiated
        audioDecodeThread?.start()

        startDisplayLink()
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(self.displayLinkFired))
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    private func stopDisplayLink() {
        DispatchQueue.main.async { [weak self] in
            self?.displayLink?.invalidate()
            self?.displayLink = nil
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard state == .playing else { return }
        let audioPTS = audioRenderer?.audioClock ?? 0
        guard audioPTS > 0 else { return }

        let videoDisplayLatency = max(link.targetTimestamp - CACurrentMediaTime(), 0)
        let audioOutputLatency = AVAudioSession.sharedInstance().outputLatency
        let syncTarget = audioPTS + videoDisplayLatency - audioOutputLatency

        frameBufferLock.lock()
        var frameToDisplay: DecodedVideoFrame?
        while let first = frameBuffer.first, first.pts.seconds <= syncTarget {
            frameToDisplay = frameBuffer.removeFirst()
        }
        frameBufferLock.unlock()

        guard let frame = frameToDisplay else { return }
        videoRenderer?.displayImmediately(frame.pixelBuffer)
        videoClock = frame.pts.seconds
        let pts = frame.pts.seconds
        if pts > lastDisplayedPTS {
            lastDisplayedPTS = pts
            currentTimeSubject.send(frame.pts)
        }
    }

    private func enqueueToFrameBuffer(_ frame: DecodedVideoFrame) {
        frameBufferLock.lock()
        let insertIndex = frameBuffer.firstIndex { $0.pts.seconds > frame.pts.seconds } ?? frameBuffer.endIndex
        frameBuffer.insert(frame, at: insertIndex)
        frameBufferLock.unlock()
    }

    private var frameBufferCount: Int {
        frameBufferLock.lock()
        defer { frameBufferLock.unlock() }
        return frameBuffer.count
    }

    private func flushFrameBuffer() {
        frameBufferLock.lock()
        frameBuffer.removeAll()
        frameBufferLock.unlock()
        lastDisplayedPTS = -1
    }

    // MARK: - Demux Loop

    private func demuxLoop() {
        VanmoLogger.player.info("[FFmpeg][Demux] demux loop started")
        var packetCount = 0
        var videoPackets = 0
        var audioPackets = 0

        while isRunning {
            if isPaused {
                pauseLock.lock()
                while isPaused && isRunning { pauseLock.wait() }
                pauseLock.unlock()
            }
            guard isRunning else { break }

            if seekRequested || videoPacketQueue.count > 100 || audioPacketQueue.count > 100 {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            do {
                guard let packet = try demuxer.readPacket() else {
                    VanmoLogger.player.info("[FFmpeg][Demux] EOF reached after \(packetCount) packets (video: \(videoPackets), audio: \(audioPackets))")
                    DispatchQueue.main.async { [weak self] in
                        self?.stateSubject.send(.ended)
                    }
                    break
                }
                packetCount += 1
                if packet.streamIndex == demuxer.videoStreamIndex {
                    videoPacketQueue.enqueue(packet)
                    videoPackets += 1
                } else if packet.streamIndex == demuxer.audioStreamIndex {
                    audioPacketQueue.enqueue(packet)
                    audioPackets += 1
                }
                if packetCount == 1 {
                    VanmoLogger.player.info("[FFmpeg][Demux] first packet read: stream=\(packet.streamIndex), size=\(packet.data.count), pts=\(packet.pts), keyframe=\(packet.isKeyframe)")
                }
                if packetCount % 500 == 0 {
                    VanmoLogger.player.debug("[FFmpeg][Demux] progress: \(packetCount) packets, vQueue=\(self.videoPacketQueue.count), aQueue=\(self.audioPacketQueue.count)")
                }
            } catch {
                VanmoLogger.player.error("[FFmpeg][Demux] error: \(error.localizedDescription)")
                break
            }
        }
        VanmoLogger.player.info("[FFmpeg][Demux] demux loop ended, total packets: \(packetCount)")
    }

    // MARK: - Video Decode Loop

    private var videoFPS: Double = 0

    private func videoDecodeLoop() {
        VanmoLogger.player.info("[FFmpeg][VideoDecode] video decode loop started, hwDecoder=\(self.videoDecoder != nil), swCodecCtx=\(self.videoCodecContext != nil)")
        var frame = av_frame_alloc()
        defer { av_frame_free(&frame) }
        var decodedFrames = 0

        if let vs = demuxer.videoStreams().first {
            videoFPS = vs.frameRate > 0 ? vs.frameRate : 30
        }

        while isRunning {
            if isPaused {
                pauseLock.lock()
                while isPaused && isRunning { pauseLock.wait() }
                pauseLock.unlock()
            }
            guard isRunning else { break }

            while frameBufferCount > maxFrameBufferSize && isRunning && !seekRequested {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard isRunning else { break }

            guard let packet = videoPacketQueue.dequeue() else {
                if !isRunning { break }
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }

            if let hwDecoder = videoDecoder, hwDecoder.isHardwareAccelerated {
                decodeVideoHardware(packet: packet)
            } else if let codecCtx = videoCodecContext {
                decodeVideoSoftware(codecCtx: codecCtx, packet: packet, frame: frame!)
            } else {
                if decodedFrames == 0 {
                    VanmoLogger.player.error("[FFmpeg][VideoDecode] no decoder available! hwDecoder=\(self.videoDecoder != nil), swCodecCtx=\(self.videoCodecContext != nil)")
                }
            }
            decodedFrames += 1
            if decodedFrames == 1 {
                VanmoLogger.player.info("[FFmpeg][VideoDecode] first video packet dequeued, size=\(packet.data.count), pts=\(packet.pts), keyframe=\(packet.isKeyframe)")
            }
        }
        VanmoLogger.player.info("[FFmpeg][VideoDecode] video decode loop ended, decoded \(decodedFrames) packets")
    }

    private var hwDecodeCount = 0
    private var hwDecodeErrorCount = 0

    private func decodeVideoHardware(packet: DemuxerPacket) {
        guard let hwDecoder = videoDecoder else {
            VanmoLogger.player.error("[FFmpeg][HWDecode] hwDecoder is nil!")
            return
        }
        let timeBaseSeconds = packet.timeBase.seconds
        let pts = CMTime(seconds: Double(packet.pts) * timeBaseSeconds, preferredTimescale: 600)
        let dts = CMTime(seconds: Double(packet.dts) * timeBaseSeconds, preferredTimescale: 600)
        let dur = CMTime(seconds: Double(packet.duration) * timeBaseSeconds, preferredTimescale: 600)

        do {
            try packet.data.withUnsafeBytes { raw in
                guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    VanmoLogger.player.error("[FFmpeg][HWDecode] packet data pointer is nil")
                    return
                }
                try hwDecoder.decode(data: ptr, size: packet.data.count,
                                     pts: pts, dts: dts, duration: dur,
                                     isKeyframe: packet.isKeyframe)
            }
            hwDecodeCount += 1
            if hwDecodeCount == 1 {
                VanmoLogger.player.info("[FFmpeg][HWDecode] first frame decoded successfully, pts=\(pts.seconds)s")
            }
        } catch {
            hwDecodeErrorCount += 1
            if hwDecodeErrorCount <= 5 {
                VanmoLogger.player.warning("[FFmpeg][HWDecode] decode error #\(self.hwDecodeErrorCount): \(error.localizedDescription), pts=\(pts.seconds)s, size=\(packet.data.count), keyframe=\(packet.isKeyframe)")
            }
        }
    }

    private var swDecodeCount = 0
    private var swDecodeErrorCount = 0

    private func decodeVideoSoftware(
        codecCtx: UnsafeMutablePointer<AVCodecContext>,
        packet: DemuxerPacket,
        frame: UnsafeMutablePointer<AVFrame>
    ) {
        var avPkt = av_packet_alloc()
        defer { av_packet_free(&avPkt) }
        guard let pkt = avPkt else {
            VanmoLogger.player.error("[FFmpeg][SWDecode] av_packet_alloc() returned nil")
            return
        }

        packet.data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            pkt.pointee.data = UnsafeMutablePointer(mutating: ptr.assumingMemoryBound(to: UInt8.self))
            pkt.pointee.size = Int32(packet.data.count)
            pkt.pointee.pts = packet.pts
            pkt.pointee.dts = packet.dts
        }

        let sendRet = avcodec_send_packet(codecCtx, pkt)
        guard sendRet >= 0 else {
            swDecodeErrorCount += 1
            if swDecodeErrorCount <= 5 {
                VanmoLogger.player.warning("[FFmpeg][SWDecode] avcodec_send_packet failed: \(sendRet), error #\(self.swDecodeErrorCount)")
            }
            return
        }

        while avcodec_receive_frame(codecCtx, frame) >= 0 {
            guard let pixelBuffer = convertFrameToPixelBuffer(frame) else {
                VanmoLogger.player.warning("[FFmpeg][SWDecode] convertFrameToPixelBuffer returned nil, w=\(frame.pointee.width), h=\(frame.pointee.height), fmt=\(frame.pointee.format)")
                continue
            }

            let bestEffortPTS = frame.pointee.best_effort_timestamp
            let timestamp = bestEffortPTS == noPTSValue ? packet.pts : bestEffortPTS
            let pktTimeBase = codecCtx.pointee.pkt_timebase
            let pktTimeBaseSeconds = av_q2d(pktTimeBase)
            let packetTimeBaseSeconds = packet.timeBase.seconds
            let timeBaseSeconds = pktTimeBaseSeconds > 0 ? pktTimeBaseSeconds : packetTimeBaseSeconds
            let pts = Double(timestamp) * timeBaseSeconds
            let cmPTS = CMTime(seconds: pts, preferredTimescale: 600)

            swDecodeCount += 1
            if swDecodeCount == 1 {
                VanmoLogger.player.info("[FFmpeg][SWDecode] first frame decoded, w=\(frame.pointee.width), h=\(frame.pointee.height), pts=\(pts)s")
            }

            let decodedFrame = DecodedVideoFrame(
                pixelBuffer: pixelBuffer,
                pts: cmPTS,
                duration: CMTime(seconds: Double(frame.pointee.duration) * timeBaseSeconds, preferredTimescale: 600),
                width: Int(frame.pointee.width),
                height: Int(frame.pointee.height)
            )
            enqueueToFrameBuffer(decodedFrame)
        }
    }

    // MARK: - Audio Decode Loop

    private func audioDecodeLoop() {
        VanmoLogger.player.info("[FFmpeg][AudioDecode] audio decode loop started, audioCodecCtx=\(self.audioCodecContext != nil)")
        var frame = av_frame_alloc()
        defer { av_frame_free(&frame) }
        var decodedFrames = 0

        while isRunning {
            if isPaused {
                pauseLock.lock()
                while isPaused && isRunning { pauseLock.wait() }
                pauseLock.unlock()
            }
            guard isRunning else { break }
            guard let packet = audioPacketQueue.dequeue() else {
                if !isRunning { break }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            guard let codecCtx = audioCodecContext else {
                if decodedFrames == 0 {
                    VanmoLogger.player.error("[FFmpeg][AudioDecode] audioCodecContext is nil!")
                }
                continue
            }

            var avPkt = av_packet_alloc()
            defer { av_packet_free(&avPkt) }
            guard let pkt = avPkt else { continue }

            packet.data.withUnsafeBytes { raw in
                guard let ptr = raw.baseAddress else { return }
                pkt.pointee.data = UnsafeMutablePointer(mutating: ptr.assumingMemoryBound(to: UInt8.self))
                pkt.pointee.size = Int32(packet.data.count)
                pkt.pointee.pts = packet.pts
                pkt.pointee.dts = packet.dts
            }

            let sendRet = avcodec_send_packet(codecCtx, pkt)
            guard sendRet >= 0 else {
                if decodedFrames < 5 {
                    VanmoLogger.player.warning("[FFmpeg][AudioDecode] avcodec_send_packet failed: \(sendRet)")
                }
                continue
            }

            while avcodec_receive_frame(codecCtx, frame) >= 0 {
                processAudioFrame(frame!, packet: packet, codecCtx: codecCtx)
                decodedFrames += 1
                if decodedFrames == 1 {
                    VanmoLogger.player.info("[FFmpeg][AudioDecode] first audio frame decoded, samples=\(frame!.pointee.nb_samples), pts=\(frame!.pointee.pts)")
                }
            }
        }
        VanmoLogger.player.info("[FFmpeg][AudioDecode] audio decode loop ended, decoded \(decodedFrames) frames")
    }

    private func processAudioFrame(
        _ frame: UnsafeMutablePointer<AVFrame>,
        packet: DemuxerPacket,
        codecCtx: UnsafeMutablePointer<AVCodecContext>
    ) {
        guard let swrCtx = swrContext, let audioRenderer else { return }

        let nbSamples = frame.pointee.nb_samples
        let channels = Int32(2)
        let outSamples = Int(swr_get_out_samples(swrCtx, nbSamples))

        var outputBuffer: UnsafeMutablePointer<UInt8>?
        guard av_samples_alloc(&outputBuffer, nil, channels, Int32(outSamples), AV_SAMPLE_FMT_FLT, 0) >= 0,
              outputBuffer != nil else { return }
        defer { av_freep(&outputBuffer) }

        let inputData = UnsafeRawPointer(frame.pointee.extended_data)?
            .assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
        let converted = swr_convert(
            swrCtx, &outputBuffer, Int32(outSamples),
            inputData, nbSamples
        )
        guard converted > 0 else { return }

        let bestEffortPTS = frame.pointee.best_effort_timestamp
        let timestamp = bestEffortPTS == noPTSValue ? packet.pts : bestEffortPTS
        let pktTimeBase = codecCtx.pointee.pkt_timebase
        let pktTimeBaseSeconds = av_q2d(pktTimeBase)
        let packetTimeBaseSeconds = packet.timeBase.seconds
        let timeBaseSeconds = pktTimeBaseSeconds > 0 ? pktTimeBaseSeconds : packetTimeBaseSeconds
        let pts = Double(timestamp) * timeBaseSeconds

        outputBuffer!.withMemoryRebound(to: Float.self, capacity: Int(converted) * Int(channels)) { floatPtr in
            audioRenderer.enqueue(data: floatPtr, sampleCount: Int(converted), pts: pts)
        }
        audioClock = pts
    }

    // MARK: - Pixel Buffer Conversion

    private func convertFrameToPixelBuffer(
        _ frame: UnsafeMutablePointer<AVFrame>
    ) -> CVPixelBuffer? {
        let w = Int(frame.pointee.width)
        let h = Int(frame.pointee.height)

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }

        if swsContext == nil {
            swsContext = sws_getContext(
                frame.pointee.width, frame.pointee.height,
                AVPixelFormat(rawValue: frame.pointee.format),
                frame.pointee.width, frame.pointee.height,
                AV_PIX_FMT_BGRA, SWS_BILINEAR, nil, nil, nil
            )
        }
        guard let swsCtx = swsContext else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        var dstData: [UnsafeMutablePointer<UInt8>?] = [
            CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self)
        ]
        var dstLinesize: [Int32] = [Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))]

        withUnsafePointer(to: &frame.pointee.data) { src in
            withUnsafePointer(to: &frame.pointee.linesize) { srcLs in
                sws_scale(
                    swsCtx,
                    src.withMemoryRebound(to: Optional<UnsafePointer<UInt8>>.self, capacity: 8) { $0 },
                    srcLs.withMemoryRebound(to: Int32.self, capacity: 8) { $0 },
                    0, frame.pointee.height,
                    &dstData, &dstLinesize
                )
            }
        }
        return pixelBuffer
    }

    // MARK: - Cleanup

    private func cleanupCodecContexts() {
        if videoCodecContext != nil { avcodec_free_context(&videoCodecContext) }
        if audioCodecContext != nil { avcodec_free_context(&audioCodecContext) }
        if subtitleCodecContext != nil { avcodec_free_context(&subtitleCodecContext) }
        if swsContext != nil { sws_freeContext(swsContext); swsContext = nil }
        if swrContext != nil { swr_free(&swrContext) }
    }

    private func mapToVideoToolboxCodec(_ codecID: AVCodecID) -> CMVideoCodecType {
        switch codecID {
        case AV_CODEC_ID_H264:  return kCMVideoCodecType_H264
        case AV_CODEC_ID_HEVC:  return kCMVideoCodecType_HEVC
        case AV_CODEC_ID_VP9:   return CMVideoCodecType(0x76703039)
        case AV_CODEC_ID_AV1:   return CMVideoCodecType(0x61763031)
        default:                return 0
        }
    }

    #else

    // MARK: - Stub (FFmpeg not available)

    deinit {
        stop()
    }

    func load(url: URL, startPosition: CMTime? = nil) async throws {
        stateSubject.send(.error(DemuxerError.ffmpegNotAvailable.localizedDescription))
        throw DemuxerError.ffmpegNotAvailable
    }

    func play() {}
    func pause() {}
    func stop() {
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
    }

    func seek(to time: CMTime) async {}

    func selectAudioTrack(index: Int) {}
    func selectSubtitleTrack(index: Int?) {}
    func availableAudioTracks() -> [AudioTrackInfo] { [] }
    func availableSubtitleTracks() -> [SubtitleTrackInfo] { [] }

    #endif
}

// MARK: - Packet Queue

private final class PacketQueue {
    private var queue: [DemuxerPacket] = []
    private let lock = NSCondition()
    private var isAborted = false

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count
    }

    func enqueue(_ packet: DemuxerPacket) {
        lock.lock()
        queue.append(packet)
        lock.signal()
        lock.unlock()
    }

    func dequeue() -> DemuxerPacket? {
        lock.lock()
        defer { lock.unlock() }
        while queue.isEmpty && !isAborted {
            lock.wait(until: Date(timeIntervalSinceNow: 0.05))
            if isAborted { return nil }
        }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    func flush() {
        lock.lock()
        queue.removeAll()
        lock.unlock()
    }

    func abort() {
        lock.lock()
        isAborted = true
        lock.broadcast()
        lock.unlock()
    }
}
