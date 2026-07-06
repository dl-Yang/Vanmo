import AVFoundation
import Combine
import Foundation
import VanmoCore

@MainActor
final class MacPlayerViewModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Double = 0.7
    @Published private(set) var playbackState: PlaybackState = .idle

    let player: AVPlayer

    private let item: MediaItem
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var prefetchRegistration: PrefetchRegistration?

    init(item: MediaItem, startPosition: TimeInterval = 0) {
        self.item = item
        self.player = AVPlayer()
        player.volume = Float(volume)
        configurePlayer(startPosition: startPosition)
    }

    func cleanup() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var remainingTime: TimeInterval {
        max(duration - currentTime, 0)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            playbackState = .paused
        } else {
            player.play()
            playbackState = .playing
        }
        isPlaying.toggle()
    }

    func seek(to progress: Double) {
        let clamped = min(max(progress, 0), 1)
        let target = duration * clamped
        seek(toSeconds: target)
    }

    func skip(by seconds: TimeInterval) {
        seek(toSeconds: currentTime + seconds)
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        player.volume = Float(volume)
    }

    private func configurePlayer(startPosition: TimeInterval) {
        let playbackURL = resolvedPlaybackURL(for: item)
        let playerItem = AVPlayerItem(url: playbackURL)
        player.replaceCurrentItem(with: playerItem)
        playbackState = .loading

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                self?.playbackState = .ended
                self?.isPlaying = false
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                    self?.playbackState = .playing
                case .paused:
                    self?.isPlaying = false
                    self?.playbackState = .paused
                case .waitingToPlayAtSpecifiedRate:
                    self?.playbackState = .buffering
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        Task {
            let assetDuration = try? await playerItem.asset.load(.duration)
            if let assetDuration, assetDuration.isNumeric {
                duration = assetDuration.seconds
            } else if item.duration > 0 {
                duration = item.duration
            }

            if startPosition > 0 {
                seek(toSeconds: startPosition)
            }
            player.play()
            isPlaying = true
            playbackState = .playing
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            currentTime = time.seconds
            if duration <= 0, let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                duration = itemDuration
            }
        }
    }

    private func seek(toSeconds seconds: TimeInterval) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    private func resolvedPlaybackURL(for item: MediaItem) -> URL {
        item.fileURL
    }
}
