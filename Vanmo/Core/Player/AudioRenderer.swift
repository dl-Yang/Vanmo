import Foundation
import AVFoundation
import Combine

final class AudioRenderer {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat

    private var isPaused = false
    private let lock = NSLock()

    private(set) var currentPTS: TimeInterval = 0
    private var basePTS: TimeInterval = 0
    private var hasBasePTS = false

    private static let machTimebaseNanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    var audioClock: TimeInterval {
        lock.lock()
        let base = basePTS
        let hasBase = hasBasePTS
        lock.unlock()
        guard hasBase, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return base
        }
        var clock = base + Double(playerTime.sampleTime) / playerTime.sampleRate

        if nodeTime.isHostTimeValid {
            let renderNanos = Double(nodeTime.hostTime) * Self.machTimebaseNanosPerTick
            let nowNanos = Double(mach_absolute_time()) * Self.machTimebaseNanosPerTick
            let elapsed = (nowNanos - renderNanos) / 1_000_000_000
            if elapsed > 0 && elapsed < 0.5 {
                clock += elapsed
            }
        }

        return clock
    }

    init(sampleRate: Double = 44100, channels: UInt32 = 2) {
        self.format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        setupEngine()
    }

    // MARK: - Public Methods

    func start() {
        do {
            VanmoLogger.player.info("[AudioRenderer] starting engine, format: \(self.format.sampleRate)Hz, \(self.format.channelCount)ch")
            try engine.start()
            playerNode.play()
            isPaused = false
            VanmoLogger.player.info("[AudioRenderer] started successfully, isRunning=\(self.engine.isRunning), playerNode.isPlaying=\(self.playerNode.isPlaying)")
        } catch {
            VanmoLogger.player.error("[AudioRenderer] start failed: \(error.localizedDescription)")
        }
    }

    func pause() {
        playerNode.pause()
        isPaused = true
    }

    func resume() {
        playerNode.play()
        isPaused = false
    }

    func stop() {
        VanmoLogger.player.info("[AudioRenderer] stop(), enqueued \(self.enqueueCount) buffers total")
        playerNode.stop()
        engine.stop()
        isPaused = false
        lock.lock()
        currentPTS = 0
        basePTS = 0
        hasBasePTS = false
        lock.unlock()
    }

    func flush() {
        playerNode.stop()
        lock.lock()
        hasBasePTS = false
        basePTS = 0
        currentPTS = 0
        lock.unlock()
        playerNode.play()
    }

    /// Enqueue PCM audio samples for playback.
    /// - Parameters:
    ///   - data: Interleaved PCM float32 sample data
    ///   - sampleCount: Number of samples per channel
    ///   - pts: Presentation timestamp in seconds
    private var enqueueCount = 0
    private var enqueueFailCount = 0

    func enqueue(data: UnsafePointer<Float>, sampleCount: Int, pts: TimeInterval) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            enqueueFailCount += 1
            if enqueueFailCount <= 3 {
                VanmoLogger.player.warning("[AudioRenderer] AVAudioPCMBuffer creation failed, sampleCount=\(sampleCount), format=\(self.format)")
            }
            return
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            guard let channelData = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<sampleCount {
                channelData[i] = data[i * channelCount + ch]
            }
        }

        lock.lock()
        if !hasBasePTS {
            basePTS = pts
            hasBasePTS = true
        }
        currentPTS = pts
        lock.unlock()

        enqueueCount += 1
        if enqueueCount == 1 {
            VanmoLogger.player.info("[AudioRenderer] first audio buffer enqueued: \(sampleCount) samples, pts=\(pts)s, channels=\(channelCount)")
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Enqueue an AVAudioPCMBuffer directly.
    func enqueue(buffer: AVAudioPCMBuffer, pts: TimeInterval) {
        lock.lock()
        if !hasBasePTS {
            basePTS = pts
            hasBasePTS = true
        }
        currentPTS = pts
        lock.unlock()

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    func reconfigure(sampleRate: Double, channels: UInt32) {
        let currentRate = timePitch.rate
        stop()

        engine.detach(playerNode)
        engine.detach(timePitch)

        guard let newFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            VanmoLogger.player.error("AudioRenderer: unsupported format \(sampleRate)Hz \(channels)ch")
            return
        }

        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.connect(playerNode, to: timePitch, format: newFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: newFormat)
        timePitch.rate = currentRate

        start()
    }

    // MARK: - Private

    func setRate(_ rate: Float) {
        timePitch.rate = rate
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }
}
