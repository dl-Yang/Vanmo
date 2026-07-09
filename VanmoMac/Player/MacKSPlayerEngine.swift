import AppKit
import AVFoundation
import Combine
import Foundation
import KSPlayer
import VanmoCore

@MainActor
final class MacKSPlayerEngine: NSObject, ObservableObject {
    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let durationSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let bufferProgressSubject = CurrentValueSubject<Double, Never>(0)
    private let subtitleTextSubject = CurrentValueSubject<String?, Never>(nil)

    var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { currentTimeSubject.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<CMTime, Never> { durationSubject.eraseToAnyPublisher() }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { bufferProgressSubject.eraseToAnyPublisher() }
    var subtitleTextPublisher: AnyPublisher<String?, Never> { subtitleTextSubject.eraseToAnyPublisher() }

    var state: PlaybackState { stateSubject.value }
    var duration: CMTime { durationSubject.value }
    var videoView: NSView? { player?.view }

    var playbackRate: Float = 1.0 {
        didSet { player?.playbackRate = playbackRate }
    }

    private var player: KSMEPlayer?
    private var timeUpdateTimer: Timer?
    private var shouldResumeAfterBuffering = false
    private var lastPlayableTime: CFAbsoluteTime = 0
    private var selectedSubtitleSearchable: (any KSSubtitleProtocol)?
    private var cachedSubtitleParts: [SubtitlePart] = []
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var volumeValue: Float = 0.7

    override init() {
        super.init()
        KSOptions.audioPlayerType = AudioRendererPlayer.self
    }

    deinit {
        timeUpdateTimer?.invalidate()
        player?.shutdown()
    }

    func load(
        url: URL,
        headers: [String: String] = [:],
        startPosition: CMTime? = nil
    ) async throws {
        VanmoLogger.player.info("[MacKSEngine] load() called, url: \(url.safePlaybackLogDescription)")
        stop()
        stateSubject.send(.loading)

        let hardwareDecode = PlaybackPreferences.hardwareDecodingEnabled
        do {
            try await loadPlayer(
                url: url,
                headers: headers,
                startPosition: startPosition,
                hardwareDecode: hardwareDecode
            )
        } catch {
            guard hardwareDecode else { throw error }
            VanmoLogger.player.error(
                "[MacKSEngine] hardware decode load failed, retrying with software decode: \(error.localizedDescription)"
            )
            player?.shutdown()
            player = nil
            readyContinuation = nil
            stateSubject.send(.loading)
            try await loadPlayer(
                url: url,
                headers: headers,
                startPosition: startPosition,
                hardwareDecode: false
            )
        }
    }

    func play() {
        player?.play()
        stateSubject.send(.playing)
    }

    func pause() {
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
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        player?.shutdown()
        player = nil
        selectedSubtitleSearchable = nil
        cachedSubtitleParts = []
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
        bufferProgressSubject.send(0)
        subtitleTextSubject.send(nil)
    }

    func setVolume(_ value: Float) {
        volumeValue = min(max(value, 0), 1)
        player?.playbackVolume = volumeValue
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        guard let player else { return }
        switch mode {
        case .fit:
            player.contentMode = .scaleAspectFit
        case .fill:
            player.contentMode = .scaleAspectFill
        case .stretch:
            player.contentMode = .scaleToFill
        }
    }

    func selectAudioTrack(index: Int) async {
        guard let player else { return }
        let audioTracks = player.tracks(mediaType: .audio)
        guard index < audioTracks.count else { return }
        for (trackIndex, track) in audioTracks.enumerated() {
            track.isEnabled = trackIndex == index
        }
    }

    func selectSubtitleTrack(index: Int?) async {
        guard let player else { return }
        let subtitleTracks = player.tracks(mediaType: .subtitle)

        if let index, index < subtitleTracks.count {
            let track = subtitleTracks[index]
            for subtitleTrack in subtitleTracks { subtitleTrack.isEnabled = false }
            player.select(track: track)
            if !track.isEnabled {
                track.isEnabled = true
            }
            selectedSubtitleSearchable = track as? (any KSSubtitleProtocol)
            cachedSubtitleParts = []
            VanmoLogger.player.info("[MacKSEngine] subtitle track selected: \(track.name)")
        } else {
            for subtitleTrack in subtitleTracks { subtitleTrack.isEnabled = false }
            selectedSubtitleSearchable = nil
            cachedSubtitleParts = []
            subtitleTextSubject.send(nil)
        }
    }

    func availableAudioTracks() async -> [AudioTrackInfo] {
        guard let player else { return [] }
        return player.tracks(mediaType: .audio).enumerated().map { index, track in
            AudioTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                codec: nil,
                channels: nil
            )
        }
    }

    func availableSubtitleTracks() async -> [SubtitleTrackInfo] {
        guard let player else { return [] }
        return player.tracks(mediaType: .subtitle).enumerated().map { index, track in
            SubtitleTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                isEmbedded: true,
                fileURL: nil
            )
        }
    }

    private func loadPlayer(
        url: URL,
        headers: [String: String],
        startPosition: CMTime?,
        hardwareDecode: Bool
    ) async throws {
        let playbackURL = url.isFileURL ? URL(fileURLWithPath: url.path, isDirectory: false) : url

        let options = KSOptions()
        if let startPosition, startPosition.seconds > 0 {
            options.startPlayTime = startPosition.seconds
        }
        options.isAccurateSeek = true
        options.isSecondOpen = true
        options.preferredForwardBufferDuration = 10
        options.maxBufferDuration = 60
        options.formatContextOptions["buffer_size"] = 8 * 1024 * 1024
        options.hardwareDecode = hardwareDecode
        if !headers.isEmpty {
            options.appendHeader(headers)
        }
        Self.configureAudioOptions(options)

        let mePlayer = KSMEPlayer(url: playbackURL, options: options)
        mePlayer.delegate = self
        mePlayer.playbackVolume = volumeValue
        player = mePlayer
        mePlayer.prepareToPlay()

        try await waitForReady()

        let duration = mePlayer.duration
        if duration > 0 {
            durationSubject.send(CMTime(seconds: duration, preferredTimescale: 600))
        }

        startTimeUpdateTimer()
        stateSubject.send(.paused)
        VanmoLogger.player.info("[MacKSEngine] load complete: \(url.lastPathComponent)")
    }

    private static func configureAudioOptions(_ options: KSOptions) {
        switch AudioOutputMode.current {
        case .auto, .stereo:
            options.audioFilters = ["aformat=channel_layouts=stereo"]
        case .surround:
            break
        }
    }

    private func waitForReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
        }
    }

    private func startTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimeUpdateTick()
            }
        }
    }

    private func handleTimeUpdateTick() {
        guard let player else { return }
        let time = player.currentPlaybackTime
        guard time.isFinite, !time.isNaN else { return }
        currentTimeSubject.send(CMTime(seconds: time, preferredTimescale: 600))
        updateSubtitleText(at: time)
    }

    private func updateSubtitleText(at time: TimeInterval) {
        guard let searchable = selectedSubtitleSearchable else {
            if subtitleTextSubject.value != nil {
                cachedSubtitleParts = []
                subtitleTextSubject.send(nil)
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
        let normalized = text.isEmpty ? nil : text
        if normalized != subtitleTextSubject.value {
            subtitleTextSubject.send(normalized)
        }
    }
}

private extension URL {
    var safePlaybackLogDescription: String {
        if isFileURL {
            return "file://\(lastPathComponent)"
        }
        let host = host ?? ""
        let path = path.isEmpty ? "/" : path
        return "\(scheme ?? "")://\(host)\(path)"
    }
}

extension MacKSPlayerEngine: MediaPlayerDelegate {
    nonisolated func readyToPlay(player: some MediaPlayerProtocol) {
        Task { @MainActor in
            let duration = player.duration
            if duration > 0 {
                durationSubject.send(CMTime(seconds: duration, preferredTimescale: 600))
            }
            readyContinuation?.resume()
            readyContinuation = nil
        }
    }

    nonisolated func changeLoadState(player: some MediaPlayerProtocol) {
        Task { @MainActor in
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
    }

    nonisolated func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {
        Task { @MainActor in
            bufferProgressSubject.send(Double(progress) / 100.0)
        }
    }

    nonisolated func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}

    nonisolated func finish(player: some MediaPlayerProtocol, error: Error?) {
        Task { @MainActor in
            if let error {
                VanmoLogger.player.error("[MacKSEngine] finished with error: \(error.localizedDescription)")
                stateSubject.send(.error(error.localizedDescription))
                readyContinuation?.resume(throwing: error)
                readyContinuation = nil
            } else {
                stateSubject.send(.ended)
            }
        }
    }
}
