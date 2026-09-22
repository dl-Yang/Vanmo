import Foundation
import AVFoundation
import AVKit
import Combine
import KSPlayer
import SwiftUI
import UIKit
import VanmoCore

final class KSPlayerEngine: NSObject, PlayerEngine {

    // MARK: - Publishers

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let durationSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let bufferProgressSubject = CurrentValueSubject<Double, Never>(0)
    private let subtitleContentSubject = CurrentValueSubject<SubtitleContent?, Never>(nil)
    private let pictureInPictureActiveSubject = CurrentValueSubject<Bool, Never>(false)

    var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { currentTimeSubject.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<CMTime, Never> { durationSubject.eraseToAnyPublisher() }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { bufferProgressSubject.eraseToAnyPublisher() }
    var subtitleContentPublisher: AnyPublisher<SubtitleContent?, Never> { subtitleContentSubject.eraseToAnyPublisher() }
    var pictureInPictureActivePublisher: AnyPublisher<Bool, Never> {
        pictureInPictureActiveSubject.eraseToAnyPublisher()
    }

    var state: PlaybackState { stateSubject.value }
    var currentTime: CMTime { currentTimeSubject.value }
    var duration: CMTime { durationSubject.value }

    var playbackRate: Float = 1.0 {
        didSet {
            player?.playbackRate = playbackRate
        }
    }

    // MARK: - KSPlayer

    private var player: KSMEPlayer?
    private let libavformatGateLock = NSLock()
    private var holdsLibavformatGate = false
    private let seekGenerationLock = NSLock()
    private var seekGeneration: UInt64 = 0
    private var timeUpdateTimer: Timer?
    private var shouldResumeAfterBuffering = false
    private var lastPlayableTime: CFAbsoluteTime = 0
    private var selectedSubtitleSearchable: (any KSSubtitleProtocol)?
    private var externalRichSubtitle: URLSubtitleInfo?
    private var externalRichSubtitleDelay: TimeInterval = 0
    private var subtitleLogCounter: Int = 0
    private var cachedSubtitleParts: [SubtitlePart] = []
    private weak var configuredPictureInPictureController: AVPictureInPictureController?
    private var retainedActivePictureInPictureControllers: [AVPictureInPictureController] = []

#if DEBUG
    private var performanceLoadStartedAt: CFAbsoluteTime?
    private var performanceBufferingStartedAt: CFAbsoluteTime?
    private var performanceBufferingCount = 0
    private var performanceLastSampleAt: CFAbsoluteTime = 0
    private var performanceLastBytesRead: Int64 = 0
    private var performanceLastDroppedFrames: UInt32 = 0
    private var performanceDidLogFirstFrame = false
    private var performanceThermalState = ProcessInfo.processInfo.thermalState
#endif

    // MARK: - Video View

    var videoView: UIView? { player?.view }

    @MainActor
    var isPictureInPictureSupported: Bool {
        if #available(iOS 15.0, tvOS 15.0, *) {
            return AVPictureInPictureController.isPictureInPictureSupported() && player?.pipController != nil
        }
        return false
    }

    @MainActor
    var isPictureInPictureActive: Bool {
        if #available(iOS 15.0, tvOS 15.0, *) {
            return pictureInPictureActiveSubject.value
                || player?.pipController?.isPictureInPictureActive == true
        }
        return false
    }

    @MainActor
    var isPictureInPicturePossible: Bool {
        if #available(iOS 15.0, tvOS 15.0, *) {
            return player?.pipController?.isPictureInPicturePossible == true
        }
        return false
    }

    // MARK: - Chapters

    var availableChapters: [VanmoCore.Chapter] {
        guard let ksChapters = player?.chapters else { return [] }
        return ksChapters.enumerated().map { index, ch in
            VanmoCore.Chapter(
                id: index,
                title: ch.title,
                startTime: CMTime(seconds: ch.start, preferredTimescale: 600),
                endTime: CMTime(seconds: ch.end, preferredTimescale: 600)
            )
        }
    }

    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        stopTimeUpdateTimer()
        player?.shutdown()
        if consumeLibavformatGateHold() {
            Task {
                await LibavformatOpenGate.shared.releaseAfterProtocolCloseDrain()
            }
        }
    }

    // MARK: - PlayerEngine Protocol

    func load(url: URL, startPosition: CMTime? = nil) async throws {
        try await load(url: url, startPosition: startPosition, headers: [:])
    }

    func load(url: URL, startPosition: CMTime?, headers: [String: String]) async throws {
        VanmoLogger.player.info("[KSEngine] load() called, url: \(url.safePlaybackLogDescription)")
        await MainActor.run { stopPlaybackResources() }
        await releaseLibavformatGateIfHeld()
#if DEBUG
        resetPerformanceDiagnostics()
        performanceLoadStartedAt = CFAbsoluteTimeGetCurrent()
#endif
        stateSubject.send(.loading)

        let hardwareDecode = PlaybackPreferences.hardwareDecodingEnabled
        // KSPlayer already falls back from VideoToolbox to its FFmpeg decoder at
        // the decoder level. Retrying every open/auth/network failure with
        // hardware decoding disabled can turn a transient source failure into a
        // successful but needlessly hot full-software playback session.
        do {
            try await loadPlayer(
                url: url,
                startPosition: startPosition,
                hardwareDecode: hardwareDecode,
                headers: headers
            )
        } catch {
            await MainActor.run {
                stopPlaybackResources()
            }
            readyContinuation = nil
            await releaseLibavformatGateIfHeld()
            throw error
        }
    }

    private func loadPlayer(
        url: URL,
        startPosition: CMTime?,
        hardwareDecode: Bool,
        headers: [String: String]
    ) async throws {
        let options = KSOptions()
        if let startPosition, startPosition.seconds > 0 {
            options.startPlayTime = startPosition.seconds
        }
        options.isAccurateSeek = true
        // 缓冲水位：吸收稳态吞吐略低于码率时的抖动，降低 buffering 次数。
        // Prefetch 代理会在第二次 GET 时取消第一条 body；KS isSecondOpen
        // 正好会打出探测连接，导致满缓冲条假死直到用户 seek。
        let disableSecondOpen = PrefetchConfig.shouldDisableSecondOpen(for: url)
        options.isSecondOpen = !disableSecondOpen
        options.preferredForwardBufferDuration = 10
        options.maxBufferDuration = 60
        options.formatContextOptions["buffer_size"] = 8 * 1024 * 1024

        // 接通设置页「硬件解码优先」开关（VideoToolbox 硬解）。
        // HDR 显示标准（preferredDisplayCriteria）由 KSPlayer 依据内容动态范围内部自动配置。
        options.hardwareDecode = hardwareDecode
        VanmoLogger.player.info("[KSEngine] hardwareDecode: \(hardwareDecode) isSecondOpen: \(!disableSecondOpen)")

        if !headers.isEmpty {
            options.appendHeader(headers)
        }

        Self.configureAudioOptions(options)

        if LibavformatOpenGate.needsExclusiveOpen(url) {
            await LibavformatOpenGate.shared.acquire()
            markLibavformatGateHeld()
        }

        let mePlayer = await MainActor.run {
            let player = KSMEPlayer(url: url, options: options)
            player.delegate = self
            self.player = player
            self.refreshPictureInPictureController(for: player)
            player.prepareToPlay()
            return player
        }

        try await waitForReady()

        let duration = mePlayer.duration
        if duration > 0 {
            durationSubject.send(CMTime(seconds: duration, preferredTimescale: 600))
        }
        VanmoLogger.player.info("[KSEngine] duration: \(duration)s")

        await MainActor.run { startTimeUpdateTimer() }
        stateSubject.send(.paused)
        VanmoLogger.player.info("[KSEngine] load complete: \(url.lastPathComponent)")
#if DEBUG
        if let startedAt = performanceLoadStartedAt {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
            VanmoLogger.player.info("[Debug][PlaybackPerf] event=ready platform=ios engine=ks elapsedMs=\(elapsedMs, privacy: .public) hardware=\(hardwareDecode, privacy: .public)")
        }
#endif
    }

    func play() {
        VanmoLogger.player.info("[KSEngine] play()")
        player?.play()
        stateSubject.send(.playing)
    }

    func pause() {
        VanmoLogger.player.info("[KSEngine] pause()")
        player?.pause()
        stateSubject.send(.paused)
    }

    func seek(to time: CMTime) async {
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0, let player else { return }

        let wasPlaying = state == .playing || state == .buffering
        shouldResumeAfterBuffering = wasPlaying
        let generation = beginSeek()
#if DEBUG
        let startedAt = CFAbsoluteTimeGetCurrent()
#endif

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = PlaybackSeekCompletionGate(continuation)
            player.seek(time: seconds) { _ in
                gate.resume()
            }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(3))
                if gate.resume() {
                    VanmoLogger.player.error("[KSEngine] seek callback timed out after 3s")
                }
            }
            gate.installTimeout(timeout)
        }
        guard isCurrentSeek(generation) else { return }
        currentTimeSubject.send(time)
#if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        VanmoLogger.player.info("[Debug][PlaybackPerf] event=seekEnd platform=ios engine=ks elapsedMs=\(elapsedMs, privacy: .public)")
#endif

        if wasPlaying {
            player.play()
            stateSubject.send(.playing)
        }
    }

    func stop() {
        VanmoLogger.player.info("[KSEngine] stop()")
        stopPlaybackResources()
        if consumeLibavformatGateHold() {
            Task {
                await LibavformatOpenGate.shared.releaseAfterProtocolCloseDrain()
            }
        }
    }

    private func stopPlaybackResources() {
        invalidateSeeks()
        stopTimeUpdateTimer()
        if #available(iOS 15.0, tvOS 15.0, *) {
            let controllers = retainedActivePictureInPictureControllers
                + [configuredPictureInPictureController].compactMap { $0 }
            for controller in controllers {
                controller.canStartPictureInPictureAutomaticallyFromInline = false
                controller.delegate = nil
                controller.stopPictureInPicture()
            }
        }
        configuredPictureInPictureController = nil
        retainedActivePictureInPictureControllers.removeAll()
        pictureInPictureActiveSubject.send(false)
        player?.shutdown()
        player = nil
        selectedSubtitleSearchable = nil
        externalRichSubtitle = nil
        externalRichSubtitleDelay = 0
        cachedSubtitleParts = []
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
        bufferProgressSubject.send(0)
        subtitleContentSubject.send(nil)
    }

    private func beginSeek() -> UInt64 {
        seekGenerationLock.lock()
        seekGeneration &+= 1
        let generation = seekGeneration
        seekGenerationLock.unlock()
        return generation
    }

    private func invalidateSeeks() {
        seekGenerationLock.lock()
        seekGeneration &+= 1
        seekGenerationLock.unlock()
    }

    private func isCurrentSeek(_ generation: UInt64) -> Bool {
        seekGenerationLock.lock()
        defer { seekGenerationLock.unlock() }
        return seekGeneration == generation
    }

    private func markLibavformatGateHeld() {
        libavformatGateLock.lock()
        holdsLibavformatGate = true
        libavformatGateLock.unlock()
    }

    private func consumeLibavformatGateHold() -> Bool {
        libavformatGateLock.lock()
        defer { libavformatGateLock.unlock() }
        guard holdsLibavformatGate else { return false }
        holdsLibavformatGate = false
        return true
    }

    private func releaseLibavformatGateIfHeld() async {
        guard consumeLibavformatGateHold() else { return }
        await LibavformatOpenGate.shared.releaseAfterProtocolCloseDrain()
    }

    // MARK: - Track Selection

    func selectAudioTrack(index: Int) async {
        guard let player else { return }
        let audioTracks = player.tracks(mediaType: .audio)
        guard index < audioTracks.count else { return }
        for (i, track) in audioTracks.enumerated() {
            track.isEnabled = (i == index)
        }
    }

    func selectSubtitleTrack(index: Int?) async {
        guard let player else { return }
        let subtitleTracks = player.tracks(mediaType: .subtitle)
        externalRichSubtitle = nil
        externalRichSubtitleDelay = 0

        if let index, index < subtitleTracks.count {
            let track = subtitleTracks[index]

            for t in subtitleTracks { t.isEnabled = false }
            player.select(track: track)

            if !track.isEnabled {
                track.isEnabled = true
            }

            selectedSubtitleSearchable = track as? (any KSSubtitleProtocol)
            cachedSubtitleParts = []
            subtitleLogCounter = 0
            VanmoLogger.player.info("[KSEngine] subtitle track selected: name=\(track.name), isImageSubtitle=\(track.isImageSubtitle)")
        } else {
            for t in subtitleTracks { t.isEnabled = false }
            selectedSubtitleSearchable = nil
            cachedSubtitleParts = []
            subtitleContentSubject.send(nil)
        }
    }

    func selectExternalRichSubtitle(url: URL, delay: TimeInterval) async throws {
        guard player != nil else { throw SubtitleError.assRenderingUnavailable }
        let subtitle = URLSubtitleInfo(url: url)
        try await subtitle.parse(url: url)
        for track in player?.tracks(mediaType: .subtitle) ?? [] {
            track.isEnabled = false
        }
        externalRichSubtitle = subtitle
        externalRichSubtitleDelay = delay
        selectedSubtitleSearchable = subtitle
        cachedSubtitleParts = []
        subtitleContentSubject.send(nil)
        VanmoLogger.subtitle.info("[KSEngine] external rich subtitle selected: \(url.lastPathComponent)")
    }

    func clearExternalRichSubtitle() {
        externalRichSubtitle = nil
        externalRichSubtitleDelay = 0
        if selectedSubtitleSearchable is URLSubtitleInfo {
            selectedSubtitleSearchable = nil
            cachedSubtitleParts = []
            subtitleContentSubject.send(nil)
        }
    }

    func setExternalRichSubtitleDelay(_ delay: TimeInterval) {
        externalRichSubtitleDelay = delay
    }

    func availableAudioTracks() async -> [AudioTrackInfo] {
        guard let player else { return [] }
        return player.tracks(mediaType: .audio).enumerated().map { index, track in
            let parsed = Self.parseTrackDescription(track.description)
            return AudioTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                codec: parsed.codec,
                channels: parsed.channels
            )
        }
    }

    private static func parseTrackDescription(_ raw: String) -> (codec: String, channels: Int?) {
        let lower = raw.lowercased()

        let codec: String
        if lower.contains("truehd") || lower.contains("mlp") {
            codec = "TrueHD"
        } else if lower.contains("eac3") || lower.contains("e-ac-3") || lower.contains("eac-3") {
            codec = "Dolby Digital Plus"
        } else if lower.contains("ac3") || lower.contains("ac-3") {
            codec = "Dolby Digital"
        } else if lower.contains("dts-hd ma") || lower.contains("dts_hd_ma") {
            codec = "DTS-HD MA"
        } else if lower.contains("dts-hd") || lower.contains("dtshd") {
            codec = "DTS-HD"
        } else if lower.contains("dts") || lower.contains("dca") {
            codec = "DTS"
        } else if lower.contains("aac") {
            codec = "AAC"
        } else if lower.contains("flac") {
            codec = "FLAC"
        } else if lower.contains("opus") {
            codec = "Opus"
        } else if lower.contains("pcm") || lower.contains("lpcm") {
            codec = "LPCM"
        } else if lower.contains("mp3") || lower.contains("mp2") {
            codec = "MP3"
        } else if lower.contains("vorbis") {
            codec = "Vorbis"
        } else {
            codec = raw.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? raw
        }

        var channels: Int?
        if lower.contains("7.1") {
            channels = 8
        } else if lower.contains("5.1") {
            channels = 6
        } else if lower.contains("stereo") || lower.contains("2.0") {
            channels = 2
        } else if lower.contains("mono") || lower.contains("1.0") {
            channels = 1
        }

        return (codec, channels)
    }

    func availableSubtitleTracks() async -> [SubtitleTrackInfo] {
        guard let player else { return [] }
        let tracks = player.tracks(mediaType: .subtitle)
        return tracks.enumerated().map { index, track in
            SubtitleTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                isEmbedded: true,
                fileURL: nil
            )
        }
    }

    // MARK: - Content Mode

    @MainActor
    func setContentMode(_ contentMode: UIView.ContentMode) {
        player?.contentMode = contentMode
    }

    @MainActor
    func disableAutomaticPictureInPicture() {
        guard #available(iOS 15.0, tvOS 15.0, *) else { return }
        let controllers = retainedActivePictureInPictureControllers
            + [configuredPictureInPictureController].compactMap { $0 }
        for controller in controllers {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            if controller.isPictureInPictureActive {
                controller.stopPictureInPicture()
            }
        }
        pictureInPictureActiveSubject.send(false)
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] action=disableAutomatic engine=ksplayer")
#endif
    }

    @MainActor
    func togglePictureInPicture() -> Bool {
        guard isPictureInPictureSupported else { return false }
        refreshPictureInPictureController()
        guard let controller = player?.pipController else { return false }
        if controller.isPictureInPictureActive {
#if DEBUG
            VanmoLogger.player.info("[Debug][PiP] action=stop engine=ksplayer")
#endif
            controller.stopPictureInPicture()
            return true
        }
        guard controller.isPictureInPicturePossible else { return false }
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] action=start engine=ksplayer")
#endif
        controller.startPictureInPicture()
        return true
    }

    private func refreshPictureInPictureController(for player: KSMEPlayer? = nil) {
        guard let player = player ?? self.player else { return }
        if #available(iOS 15.0, tvOS 15.0, *), let controller = player.pipController {
            guard configuredPictureInPictureController !== controller else { return }
            if let previous = configuredPictureInPictureController {
                if previous.isPictureInPictureActive {
                    if !retainedActivePictureInPictureControllers.contains(where: { $0 === previous }) {
                        retainedActivePictureInPictureControllers.append(previous)
                    }
                } else {
                    previous.delegate = nil
                }
            }
            configuredPictureInPictureController = controller
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureActiveSubject.send(
                controller.isPictureInPictureActive
                    || retainedActivePictureInPictureControllers.contains {
                        $0.isPictureInPictureActive
                    }
            )
#if DEBUG
            let possible = controller.isPictureInPicturePossible
            let automatic = controller.canStartPictureInPictureAutomaticallyFromInline
            VanmoLogger.player.info("[Debug][PiP] configured engine=ksplayer possible=\(possible, privacy: .public) automatic=\(automatic, privacy: .public)")
#endif
        }
    }

    private func publishPictureInPictureActivity() {
        let isActive = configuredPictureInPictureController?.isPictureInPictureActive == true
            || retainedActivePictureInPictureControllers.contains {
                $0.isPictureInPictureActive
            }
        pictureInPictureActiveSubject.send(isActive)
    }

    // MARK: - Audio Configuration

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormAudio,
                options: []
            )
            try session.setActive(true)

            let maxChannels = session.maximumOutputNumberOfChannels
            let routeChannels = session.currentRoute.outputs.compactMap { $0.channels?.count }.max() ?? 2
            VanmoLogger.player.info("[KSEngine] audio session configured, maxChannels: \(maxChannels), routeChannels: \(routeChannels)")
        } catch {
            VanmoLogger.player.error("[KSEngine] audio session setup failed: \(error.localizedDescription)")
        }
    }

    private static func configureAudioOptions(_ options: KSOptions) {
        let audioMode = AudioOutputMode.current
        let session = AVAudioSession.sharedInstance()
        let maxHWChannels = session.maximumOutputNumberOfChannels

        switch audioMode {
        case .auto:
            if maxHWChannels <= 2 {
                options.audioFilters = ["aformat=channel_layouts=stereo"]
            }
        case .stereo:
            options.audioFilters = ["aformat=channel_layouts=stereo"]
        case .surround:
            try? session.setSupportsMultichannelContent(true)
            if maxHWChannels > 2 {
                try? session.setPreferredOutputNumberOfChannels(maxHWChannels)
            }
        }

        VanmoLogger.player.info("[KSEngine] audio options: mode=\(audioMode.rawValue), maxHWChannels=\(maxHWChannels)")
    }

    // MARK: - Private

    private var readyContinuation: CheckedContinuation<Void, Error>?

    private func waitForReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
        }
    }

    private func startTimeUpdateTimer() {
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.refreshPictureInPictureController(for: player)
            let time = player.currentPlaybackTime
            guard time.isFinite, !time.isNaN else { return }
            self.currentTimeSubject.send(CMTime(seconds: time, preferredTimescale: 600))
            self.updateSubtitleText(at: time)
#if DEBUG
            self.logPerformanceSampleIfNeeded(player: player)
#endif
        }
    }

#if DEBUG
    private func resetPerformanceDiagnostics() {
        performanceLoadStartedAt = nil
        performanceBufferingStartedAt = nil
        performanceBufferingCount = 0
        performanceLastSampleAt = 0
        performanceLastBytesRead = 0
        performanceLastDroppedFrames = 0
        performanceDidLogFirstFrame = false
        performanceThermalState = ProcessInfo.processInfo.thermalState
    }

    private func logPerformanceSampleIfNeeded(player: KSMEPlayer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - performanceLastSampleAt >= 5, let info = player.dynamicInfo else { return }
        performanceLastSampleAt = now

        let droppedFrames = info.droppedVideoFrameCount + info.droppedVideoPacketCount
        let droppedDelta = droppedFrames >= performanceLastDroppedFrames
            ? droppedFrames - performanceLastDroppedFrames
            : droppedFrames
        performanceLastDroppedFrames = droppedFrames

        let bytesRead = info.bytesRead
        let bytesDelta = max(bytesRead - performanceLastBytesRead, 0)
        performanceLastBytesRead = bytesRead

        if !performanceDidLogFirstFrame, info.displayFPS >= 1 {
            performanceDidLogFirstFrame = true
            let elapsedMs = performanceLoadStartedAt.map {
                Int((now - $0) * 1_000)
            } ?? -1
            VanmoLogger.player.info("[Debug][PlaybackPerf] event=firstFrame platform=ios engine=ks elapsedMs=\(elapsedMs, privacy: .public)")
        }

        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState != performanceThermalState {
            performanceThermalState = thermalState
            let thermal = thermalState.rawValue
            VanmoLogger.player.info("[Debug][PlaybackPerf] event=thermal platform=ios state=\(thermal, privacy: .public)")
        }

        let fps = String(format: "%.2f", info.displayFPS)
        let avSyncMs = Int(info.audioVideoSyncDiff * 1_000)
        let videoBitrate = info.videoBitrate
        let bufferingCount = performanceBufferingCount
        VanmoLogger.player.info("[Debug][PlaybackPerf] event=sample platform=ios engine=ks fps=\(fps, privacy: .public) avSyncMs=\(avSyncMs, privacy: .public) droppedDelta=\(droppedDelta, privacy: .public) bytesDelta=\(bytesDelta, privacy: .public) videoBitrate=\(videoBitrate, privacy: .public) bufferingCount=\(bufferingCount, privacy: .public)")
    }
#endif

    private func updateSubtitleText(at time: TimeInterval) {
        guard let searchable = selectedSubtitleSearchable else {
            if subtitleContentSubject.value != nil {
                cachedSubtitleParts = []
                subtitleContentSubject.send(nil)
            }
            return
        }

        let searchTime = searchable is URLSubtitleInfo ? time + externalRichSubtitleDelay : time
        let newParts = searchable.search(for: searchTime)

        if !newParts.isEmpty {
            cachedSubtitleParts = newParts
        } else {
            cachedSubtitleParts = cachedSubtitleParts.filter { $0 == searchTime }
        }

        let shouldUseAttributedText = searchable is URLSubtitleInfo
            || cachedSubtitleParts.contains { $0.textPosition != nil || $0.image != nil }
        let attributedText = shouldUseAttributedText ? Self.joinAttributedSubtitleParts(cachedSubtitleParts) : nil
        let text = attributedText == nil
            ? cachedSubtitleParts.compactMap { $0.text?.string }.joined(separator: "\n")
            : ""
        let image = cachedSubtitleParts.compactMap { $0.image }.first
        let placement = cachedSubtitleParts.compactMap { Self.subtitlePlacement(from: $0.textPosition) }.first
        let content: SubtitleContent? = (text.isEmpty && attributedText == nil && image == nil)
            ? nil
            : SubtitleContent(
                text: text.isEmpty ? nil : text,
                attributedText: attributedText,
                image: image,
                placement: placement
            )

        if content != subtitleContentSubject.value {
            subtitleContentSubject.send(content)
        }
    }

    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private static func joinAttributedSubtitleParts(_ parts: [SubtitlePart]) -> NSAttributedString? {
        let attributedParts = parts.compactMap(\.text)
        guard !attributedParts.isEmpty else { return nil }
        let joined = NSMutableAttributedString(string: "")
        for (index, attributedPart) in attributedParts.enumerated() {
            if index > 0 {
                joined.append(NSAttributedString(string: "\n"))
            }
            joined.append(attributedPart)
        }
        return joined
    }

    private static func subtitlePlacement(from position: TextPosition?) -> SubtitlePlacement? {
        guard let position else { return nil }

        let vertical: SubtitlePlacement.Vertical
        if position.verticalAlign == .top {
            vertical = .top
        } else if position.verticalAlign == .center {
            vertical = .center
        } else {
            vertical = .bottom
        }

        let horizontal: SubtitlePlacement.Horizontal
        if position.horizontalAlign == .leading {
            horizontal = .leading
        } else if position.horizontalAlign == .trailing {
            horizontal = .trailing
        } else {
            horizontal = .center
        }

        return SubtitlePlacement(
            vertical: vertical,
            horizontal: horizontal,
            verticalMargin: position.verticalMargin,
            leadingMargin: position.leftMargin,
            trailingMargin: position.rightMargin
        )
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension KSPlayerEngine: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pictureInPictureActiveSubject.send(true)
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] event=willStart engine=ksplayer")
#endif
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        pictureInPictureActiveSubject.send(true)
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] event=didStart engine=ksplayer")
#endif
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        retainedActivePictureInPictureControllers.removeAll {
            $0 === pictureInPictureController
        }
        publishPictureInPictureActivity()
#if DEBUG
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        VanmoLogger.player.info("[Debug][PiP] event=failed engine=ksplayer domain=\(domain, privacy: .public) code=\(code, privacy: .public)")
#endif
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] event=willStop engine=ksplayer")
#endif
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        retainedActivePictureInPictureControllers.removeAll {
            $0 === pictureInPictureController
        }
        publishPictureInPictureActivity()
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] event=didStop engine=ksplayer")
#endif
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
#if DEBUG
        VanmoLogger.player.info("[Debug][PiP] event=restoreUI engine=ksplayer")
#endif
        completionHandler(true)
    }
}

// MARK: - MediaPlayerDelegate

extension KSPlayerEngine: MediaPlayerDelegate {
    func readyToPlay(player: some MediaPlayerProtocol) {
        VanmoLogger.player.info("[KSEngine] readyToPlay, duration: \(player.duration)s")
        let dur = player.duration
        if dur > 0 {
            durationSubject.send(CMTime(seconds: dur, preferredTimescale: 600))
        }
        readyContinuation?.resume()
        readyContinuation = nil
    }

    func changeLoadState(player: some MediaPlayerProtocol) {
        switch player.loadState {
        case .loading:
            let sinceLastPlayable = CFAbsoluteTimeGetCurrent() - lastPlayableTime
            if sinceLastPlayable < 0.5 { break }
            if state == .playing || state == .paused {
                stateSubject.send(.buffering)
#if DEBUG
                if performanceBufferingStartedAt == nil {
                    performanceBufferingStartedAt = CFAbsoluteTimeGetCurrent()
                    performanceBufferingCount += 1
                    let bufferingCount = performanceBufferingCount
                    VanmoLogger.player.info("[Debug][PlaybackPerf] event=bufferingStart platform=ios engine=ks count=\(bufferingCount, privacy: .public)")
                }
#endif
            }
        case .playable:
            lastPlayableTime = CFAbsoluteTimeGetCurrent()
#if DEBUG
            if let startedAt = performanceBufferingStartedAt {
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
                performanceBufferingStartedAt = nil
                VanmoLogger.player.info("[Debug][PlaybackPerf] event=bufferingEnd platform=ios engine=ks elapsedMs=\(elapsedMs, privacy: .public)")
            }
#endif
            if state == .buffering {
                if shouldResumeAfterBuffering || player.isPlaying {
                    player.play()
                    stateSubject.send(.playing)
                } else {
                    stateSubject.send(.paused)
                }
                shouldResumeAfterBuffering = false
            }
        default:
            break
        }
    }

    func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {
        bufferProgressSubject.send(Double(progress) / 100.0)
    }

    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {
        VanmoLogger.player.info("[KSEngine] loop count: \(loopCount)")
    }

    func finish(player: some MediaPlayerProtocol, error: Error?) {
        if let error {
            VanmoLogger.player.error("[KSEngine] finished with error: \(error.localizedDescription)")
            stateSubject.send(.error(error.localizedDescription))
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
        } else {
            VanmoLogger.player.info("[KSEngine] finished playback")
            stateSubject.send(.ended)
        }
    }
}
