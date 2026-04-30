import Foundation
import AVFoundation
import Combine
import KSPlayer
import UIKit

final class KSPlayerEngine: NSObject, PlayerEngine {

    // MARK: - Publishers

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let durationSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let bufferProgressSubject = CurrentValueSubject<Double, Never>(0)
    private let subtitleContentSubject = CurrentValueSubject<SubtitleContent?, Never>(nil)

    var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { currentTimeSubject.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<CMTime, Never> { durationSubject.eraseToAnyPublisher() }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { bufferProgressSubject.eraseToAnyPublisher() }
    var subtitleContentPublisher: AnyPublisher<SubtitleContent?, Never> { subtitleContentSubject.eraseToAnyPublisher() }

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
    private var timeUpdateTimer: Timer?
    private var shouldResumeAfterBuffering = false
    private var lastPlayableTime: CFAbsoluteTime = 0
    private var selectedSubtitleSearchable: (any KSSubtitleProtocol)?
    private var subtitleLogCounter: Int = 0
    private var cachedSubtitleParts: [SubtitlePart] = []

    // MARK: - Video View

    var videoView: UIView? { player?.view }

    // MARK: - Chapters

    var availableChapters: [Chapter] {
        guard let ksChapters = player?.chapters else { return [] }
        return ksChapters.enumerated().map { index, ch in
            Chapter(
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
    }

    // MARK: - PlayerEngine Protocol

    func load(url: URL, startPosition: CMTime? = nil) async throws {
        VanmoLogger.player.info("[KSEngine] load() called, url: \(url.absoluteString)")
        await MainActor.run { stop() }
        stateSubject.send(.loading)

        let options = KSOptions()
        if let startPosition, startPosition.seconds > 0 {
            options.startPlayTime = startPosition.seconds
        }
        options.isAccurateSeek = true

        Self.configureAudioOptions(options)

        let mePlayer = await MainActor.run {
            let p = KSMEPlayer(url: url, options: options)
            p.delegate = self
            self.player = p
            p.prepareToPlay()
            return p
        }

        try await waitForReady()

        let dur = mePlayer.duration
        if dur > 0 {
            durationSubject.send(CMTime(seconds: dur, preferredTimescale: 600))
        }
        VanmoLogger.player.info("[KSEngine] duration: \(dur)s")

        await MainActor.run { startTimeUpdateTimer() }
        stateSubject.send(.paused)
        VanmoLogger.player.info("[KSEngine] load complete: \(url.lastPathComponent)")
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
        guard seconds.isFinite, seconds >= 0 else { return }

        let wasPlaying = state == .playing || state == .buffering
        shouldResumeAfterBuffering = wasPlaying

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player?.seek(time: seconds) { _ in
                continuation.resume()
            }
        }
        currentTimeSubject.send(time)

        if wasPlaying {
            player?.play()
            stateSubject.send(.playing)
        }
    }

    func stop() {
        VanmoLogger.player.info("[KSEngine] stop()")
        stopTimeUpdateTimer()
        player?.shutdown()
        player = nil
        selectedSubtitleSearchable = nil
        cachedSubtitleParts = []
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
        bufferProgressSubject.send(0)
        subtitleContentSubject.send(nil)
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
            let time = player.currentPlaybackTime
            guard time.isFinite, !time.isNaN else { return }
            self.currentTimeSubject.send(CMTime(seconds: time, preferredTimescale: 600))
            self.updateSubtitleText(at: time)
        }
    }

    private func updateSubtitleText(at time: TimeInterval) {
        guard let searchable = selectedSubtitleSearchable else {
            if subtitleContentSubject.value != nil {
                cachedSubtitleParts = []
                subtitleContentSubject.send(nil)
            }
            return
        }

        let newParts = searchable.search(for: time)

        if !newParts.isEmpty {
            cachedSubtitleParts = newParts
        } else {
            cachedSubtitleParts = cachedSubtitleParts.filter { $0 == time }
        }

        let text = cachedSubtitleParts.compactMap { $0.text?.string }.joined(separator: "\n")
        let image = cachedSubtitleParts.compactMap { $0.image }.first
        let content: SubtitleContent? = (text.isEmpty && image == nil) ? nil : SubtitleContent(text: text.isEmpty ? nil : text, image: image)

        if content != subtitleContentSubject.value {
            subtitleContentSubject.send(content)
        }
    }

    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
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
            }
        case .playable:
            lastPlayableTime = CFAbsoluteTimeGetCurrent()
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
