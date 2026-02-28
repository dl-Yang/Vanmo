import Foundation
import AVFoundation
import Combine

protocol PlayerEngine: AnyObject {
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { get }
    var durationPublisher: AnyPublisher<CMTime, Never> { get }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { get }

    var state: PlaybackState { get }
    var currentTime: CMTime { get }
    var duration: CMTime { get }
    var playbackRate: Float { get set }

    func load(url: URL, startPosition: CMTime?) async throws
    func play()
    func pause()
    func seek(to time: CMTime) async
    func stop()

    func selectAudioTrack(index: Int)
    func selectSubtitleTrack(index: Int?)
    func availableAudioTracks() -> [AudioTrackInfo]
    func availableSubtitleTracks() -> [SubtitleTrackInfo]
}

final class AVPlayerEngine: NSObject, PlayerEngine {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

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
            if state == .playing {
                player?.rate = playbackRate
            }
        }
    }

    var avPlayer: AVPlayer? { player }

    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        stop()
    }

    // MARK: - Playback Control

    func load(url: URL, startPosition: CMTime? = nil) async throws {
        stop()
        stateSubject.send(.loading)

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.playerItem = playerItem

        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        setupObservers(for: playerItem, player: player)

        if let startPosition {
            await player.seek(to: startPosition, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        try await waitForReady(playerItem)
    }

    func play() {
        player?.rate = playbackRate
        stateSubject.send(.playing)
    }

    func pause() {
        player?.pause()
        stateSubject.send(.paused)
    }

    func seek(to time: CMTime) async {
        await player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSubject.send(time)
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        cancellables.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
    }

    // MARK: - Track Selection

    func selectAudioTrack(index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let options = group.options
        if index < options.count {
            item.select(options[index], in: group)
        }
    }

    func selectSubtitleTrack(index: Int?) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if let index {
            let options = group.options
            if index < options.count {
                item.select(options[index], in: group)
            }
        } else {
            item.select(nil, in: group)
        }
    }

    func availableAudioTracks() -> [AudioTrackInfo] {
        guard let group = playerItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return []
        }
        return group.options.enumerated().map { index, option in
            AudioTrackInfo(
                id: index,
                language: option.locale?.languageCode,
                title: option.displayName,
                codec: nil,
                channels: nil
            )
        }
    }

    func availableSubtitleTracks() -> [SubtitleTrackInfo] {
        guard let group = playerItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return []
        }
        return group.options.enumerated().map { index, option in
            SubtitleTrackInfo(
                id: index,
                language: option.locale?.languageCode,
                title: option.displayName,
                isEmbedded: true,
                fileURL: nil
            )
        }
    }

    // MARK: - Private

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            VanmoLogger.player.error("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    private func setupObservers(for item: AVPlayerItem, player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTimeSubject.send(time)
        }

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown error"
                    self?.stateSubject.send(.error(message))
                default:
                    break
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                if duration.isNumeric {
                    self?.durationSubject.send(duration)
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                if isEmpty, self?.state == .playing {
                    self?.stateSubject.send(.buffering)
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if isReady, self?.state == .buffering {
                    self?.stateSubject.send(.playing)
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ranges in
                guard let first = ranges.first?.timeRangeValue,
                      let duration = self?.durationSubject.value,
                      duration.seconds > 0 else { return }
                let buffered = first.start.seconds + first.duration.seconds
                self?.bufferProgressSubject.send(buffered / duration.seconds)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stateSubject.send(.ended)
            }
            .store(in: &cancellables)
    }

    private func waitForReady(_ item: AVPlayerItem) async throws {
        for await status in item.publisher(for: \.status).values {
            switch status {
            case .readyToPlay:
                return
            case .failed:
                throw PlayerError.loadFailed(item.error?.localizedDescription ?? "Unknown error")
            default:
                continue
            }
        }
    }
}

enum PlayerError: LocalizedError {
    case loadFailed(String)
    case unsupportedFormat
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "加载失败: \(msg)"
        case .unsupportedFormat: return "不支持的视频格式"
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}
