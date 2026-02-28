import SwiftUI
import AVFoundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferProgress: Double = 0
    @Published private(set) var audioTracks: [AudioTrackInfo] = []
    @Published private(set) var subtitleTracks: [SubtitleTrackInfo] = []

    @Published var config = PlayerConfig()
    @Published var controlsVisible = true
    @Published var isSeeking = false
    @Published var seekTime: TimeInterval = 0
    @Published var showTrackSelector = false
    @Published var brightnessOverlay: Float?
    @Published var volumeOverlay: Float?
    @Published var seekOverlay: TimeInterval?

    let engine: AVPlayerEngine
    private let item: MediaItem
    private var cancellables = Set<AnyCancellable>()
    private var hideControlsTask: Task<Void, Never>?

    init(item: MediaItem, engine: AVPlayerEngine = AVPlayerEngine()) {
        self.item = item
        self.engine = engine
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        engine.statePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$playbackState)

        engine.currentTimePublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .assign(to: &$currentTime)

        engine.durationPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .assign(to: &$duration)

        engine.bufferProgressPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$bufferProgress)
    }

    // MARK: - Lifecycle

    func onAppear() async {
        do {
            let startPosition: CMTime? = item.lastPlaybackPosition > 0
                ? CMTime(seconds: item.lastPlaybackPosition, preferredTimescale: 600)
                : nil
            try await engine.load(url: item.fileURL, startPosition: startPosition)
            audioTracks = engine.availableAudioTracks()
            subtitleTracks = engine.availableSubtitleTracks()
            engine.play()
            scheduleHideControls()
        } catch {
            playbackState = .error(error.localizedDescription)
        }
    }

    func onDisappear() {
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
    }

    func selectAudioTrack(_ index: Int) {
        config.selectedAudioTrack = index
        engine.selectAudioTrack(index: index)
    }

    func selectSubtitleTrack(_ index: Int?) {
        config.selectedSubtitleTrack = index
        engine.selectSubtitleTrack(index: index)
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
