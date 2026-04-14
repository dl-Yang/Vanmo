import SwiftUI
import AVFoundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    @AppStorage("subtitle.autoLoad") private var subtitleAutoLoad = true
    @AppStorage("subtitle.preferredLanguage") private var subtitlePreferredLanguage = "zh"

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferProgress: Double = 0
    @Published private(set) var audioTracks: [AudioTrackInfo] = []
    @Published private(set) var subtitleTracks: [SubtitleTrackInfo] = []
    @Published private(set) var chapters: [Chapter] = []

    @Published var config = PlayerConfig()
    @Published var controlsVisible = true
    @Published var isSeeking = false
    @Published var seekTime: TimeInterval = 0
    @Published var showTrackSelector = false
    @Published var showChapterList = false
    @Published var brightnessOverlay: Float?
    @Published var volumeOverlay: Float?
    @Published var seekOverlay: TimeInterval?

    let engine: PlayerEngine
    private let item: MediaItem
    private var cancellables = Set<AnyCancellable>()
    private var hideControlsTask: Task<Void, Never>?

    init(item: MediaItem) {
        self.item = item
        VanmoLogger.player.info("[PlayerVM] init, file: \(item.fileURL.lastPathComponent), URL: \(item.fileURL.absoluteString)")
        self.engine = PlayerEngineFactory.engine(for: item.fileURL)
        VanmoLogger.player.info("[PlayerVM] engine type: \(self.engine.engineType == .avFoundation ? "AVFoundation" : "FFmpeg")")
        setupBindings()
    }

    // MARK: - Engine Access

    var avPlayer: AVPlayer? {
        (engine as? AVPlayerEngine)?.avPlayer
    }

    var ffmpegRenderView: VideoRenderer? {
        (engine as? FFmpegPlayerEngine)?.renderView
    }

    // MARK: - Setup

    private func setupBindings() {
        engine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                VanmoLogger.player.info("[PlayerVM] state changed: \(String(describing: state))")
                self?.playbackState = state
            }
            .store(in: &cancellables)

        engine.currentTimePublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .assign(to: &$currentTime)

        engine.durationPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .sink { [weak self] dur in
                VanmoLogger.player.info("[PlayerVM] duration updated: \(dur)s")
                self?.duration = dur
            }
            .store(in: &cancellables)

        engine.bufferProgressPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$bufferProgress)
    }

    // MARK: - Lifecycle

    func onAppear() async {
        VanmoLogger.player.info("[PlayerVM] onAppear, loading file: \(self.item.fileURL.lastPathComponent)")
        do {
            let startPosition: CMTime? = item.lastPlaybackPosition > 0
                ? CMTime(seconds: item.lastPlaybackPosition, preferredTimescale: 600)
                : nil
            VanmoLogger.player.info("[PlayerVM] calling engine.load(), startPosition: \(startPosition?.seconds ?? 0)s")
            try await engine.load(url: item.fileURL, startPosition: startPosition)
            VanmoLogger.player.info("[PlayerVM] engine.load() succeeded, state: \(String(describing: self.playbackState))")
            audioTracks = await engine.availableAudioTracks()
            subtitleTracks = await engine.availableSubtitleTracks()
            await applyPreferredSubtitleIfNeeded()
            VanmoLogger.player.info("[PlayerVM] audio tracks: \(self.audioTracks.count), subtitle tracks: \(self.subtitleTracks.count)")
            loadChapters()
            VanmoLogger.player.info("[PlayerVM] calling engine.play()")
            engine.play()
            VanmoLogger.player.info("[PlayerVM] engine.play() called, state: \(String(describing: self.playbackState))")
            scheduleHideControls()
        } catch {
            VanmoLogger.player.error("[PlayerVM] load failed: \(error.localizedDescription)")
            playbackState = .error(error.localizedDescription)
        }
    }

    func onDisappear() {
        VanmoLogger.player.info("[PlayerVM] onDisappear, saving progress at \(self.currentTime)s")
        saveProgress()
        engine.stop()
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        switch playbackState {
        case .playing:
            engine.pause()
        case .paused:
            engine.play()
        case .ended:
            Task {
                await engine.seek(to: .zero)
                engine.play()
            }
        default:
            break
        }
        showControlsBriefly()
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        Task {
            await engine.seek(to: CMTime(seconds: clampedTime, preferredTimescale: 600))
        }
    }

    func skipForward(_ seconds: TimeInterval = 10) {
        let target = currentTime + seconds
        seek(to: target)
        seekOverlay = seconds
        dismissOverlay(\.seekOverlay)
    }

    func skipBackward(_ seconds: TimeInterval = 10) {
        let target = currentTime - seconds
        seek(to: target)
        seekOverlay = -seconds
        dismissOverlay(\.seekOverlay)
    }

    func setRate(_ rate: Float) {
        config.playbackRate = rate
        engine.playbackRate = rate
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        config.scaleMode = mode
        ffmpegRenderView?.setScaleMode(mode)
    }

    func selectAudioTrack(_ index: Int) {
        config.selectedAudioTrack = index
        Task { await engine.selectAudioTrack(index: index) }
    }

    func selectSubtitleTrack(_ index: Int?) {
        config.selectedSubtitleTrack = index
        Task { await engine.selectSubtitleTrack(index: index) }
    }

    private func applyPreferredSubtitleIfNeeded() async {
        guard !subtitleTracks.isEmpty else { return }

        if !subtitleAutoLoad {
            config.selectedSubtitleTrack = nil
            await engine.selectSubtitleTrack(index: nil)
            return
        }

        guard let preferredIndex = preferredSubtitleIndex(
            for: subtitlePreferredLanguage,
            tracks: subtitleTracks
        ) else { return }

        config.selectedSubtitleTrack = preferredIndex
        await engine.selectSubtitleTrack(index: preferredIndex)
    }

    private func preferredSubtitleIndex(
        for preferredLanguage: String,
        tracks: [SubtitleTrackInfo]
    ) -> Int? {
        let aliases = languageAliases(for: preferredLanguage)

        var bestIndex: Int?
        var bestScore = Int.min

        for track in tracks {
            let lang = normalizedLanguageCode(track.language)
            let title = normalizedLanguageCode(track.title)

            let score: Int
            if let lang, aliases.contains(lang) {
                score = 3
            } else if let title, aliases.contains(title) {
                score = 2
            } else if let lang, lang.starts(with: preferredLanguage) {
                score = 1
            } else {
                score = 0
            }

            if score > bestScore {
                bestScore = score
                bestIndex = track.id
            }
        }

        return bestScore > 0 ? bestIndex : nil
    }

    private func languageAliases(for preferredLanguage: String) -> Set<String> {
        switch preferredLanguage {
        case "zh":
            return ["zh", "zho", "chi", "chs", "cht", "cn", "chinese", "中文", "简体", "繁体"]
        case "en":
            return ["en", "eng", "english", "英文"]
        case "ja":
            return ["ja", "jpn", "japanese", "日语", "日本語"]
        case "ko":
            return ["ko", "kor", "korean", "韩语", "한국어"]
        default:
            return [preferredLanguage]
        }
    }

    private func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value else { return nil }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Chapters

    func seekToChapter(_ chapter: Chapter) {
        seek(to: chapter.startTime.seconds)
        showControlsBriefly()
    }

    private func loadChapters() {
        if let ffmpegEngine = engine as? FFmpegPlayerEngine {
            chapters = ffmpegEngine.availableChapters
        }
    }

    // MARK: - Controls Visibility

    func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        }
    }

    func showControlsBriefly() {
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible = true
        }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, playbackState == .playing else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                controlsVisible = false
            }
        }
    }

    // MARK: - Gesture Handlers

    func handleBrightnessChange(_ delta: Float) {
        let current = UIScreen.main.brightness
        let newValue = Float(current) + delta
        let clamped = max(0, min(1, newValue))
        UIScreen.main.brightness = CGFloat(clamped)
        brightnessOverlay = clamped
        dismissOverlay(\.brightnessOverlay)
    }

    func handleVolumeChange(_ delta: Float) {
        config.volume = max(0, min(1, config.volume + delta))
        volumeOverlay = config.volume
        dismissOverlay(\.volumeOverlay)
    }

    func handleSeekGesture(_ delta: TimeInterval) {
        let target = currentTime + delta
        seekTime = max(0, min(target, duration))
        seekOverlay = delta
    }

    func commitSeekGesture() {
        seek(to: seekTime)
        seekOverlay = nil
    }

    func handleLongPress(isActive: Bool) {
        if isActive {
            engine.playbackRate = 2.0
        } else {
            engine.playbackRate = config.playbackRate
        }
    }

    // MARK: - Progress

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private func saveProgress() {
        item.lastPlaybackPosition = currentTime
        item.lastPlayedAt = Date()
        if currentTime / max(duration, 1) > 0.9 {
            item.isWatched = true
        }
    }

    private func dismissOverlay<T>(_ keyPath: ReferenceWritableKeyPath<PlayerViewModel, T?>, after: TimeInterval = 1.0) {
        Task {
            try? await Task.sleep(for: .seconds(after))
            withAnimation { self[keyPath: keyPath] = nil }
        }
    }
}
