import AVFoundation
import Combine
import Foundation
import SwiftData
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
    private let startPosition: TimeInterval
    private var modelContext: ModelContext?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var prefetchRegistration: PrefetchRegistration?
    private var didCleanup = false
    private var didSaveProgress = false

    private let defaultPlaybackRate: Float
    private let shouldResumePlayback: Bool

    init(item: MediaItem, startPosition: TimeInterval = 0) {
        self.item = item
        self.shouldResumePlayback = UserDefaults.standard.object(forKey: "playback.resumePlayback") as? Bool ?? true
        let resolvedStartPosition = Self.resolvedStartPosition(
            item: item,
            requested: startPosition,
            resumePlayback: shouldResumePlayback
        )
        self.startPosition = resolvedStartPosition
        self.defaultPlaybackRate = Float(
            UserDefaults.standard.object(forKey: "playback.defaultRate") as? Double ?? 1.0
        )
        self.player = AVPlayer()
        player.volume = Float(volume)
        player.rate = defaultPlaybackRate
        setupPlaybackObservers()
    }

    private static func resolvedStartPosition(
        item: MediaItem,
        requested: TimeInterval,
        resumePlayback: Bool
    ) -> TimeInterval {
        if requested > 0 {
            return requested
        }
        guard resumePlayback else { return 0 }
        return item.lastPlaybackPosition
    }

    func onAppear(modelContext: ModelContext) async {
        self.modelContext = modelContext
        do {
            try await loadAndPlayCurrentItem()
        } catch is CancellationError {
            return
        } catch {
            guard !didCleanup else { return }
            VanmoLogger.player.error("[MacPlayerVM] load failed: \(error.localizedDescription)")
            playbackState = .error(error.localizedDescription)
        }
    }

    func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true

        saveProgress()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        player.pause()
        player.replaceCurrentItem(with: nil)

        if let registration = prefetchRegistration {
            prefetchRegistration = nil
            let token = registration.token
            Task {
                await PrefetchProxy.shared.unregister(token: token)
            }
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
        switch playbackState {
        case .playing:
            player.pause()
            playbackState = .paused
            isPlaying = false
        case .paused, .ended:
            if isAtEnd {
                replayFromBeginning()
            } else {
                player.playImmediately(atRate: defaultPlaybackRate)
                playbackState = .playing
                isPlaying = defaultPlaybackRate > 0
            }
        default:
            if isAtEnd {
                replayFromBeginning()
            }
        }
    }

    private var isAtEnd: Bool {
        playbackState == .ended || (duration > 0 && currentTime >= max(duration - 0.5, 0))
    }

    private func replayFromBeginning() {
        player.pause()
        player.seek(to: .zero) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                self.currentTime = 0
                self.playbackState = .playing
                self.isPlaying = self.defaultPlaybackRate > 0
                self.player.playImmediately(atRate: self.defaultPlaybackRate)
            }
        }
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

    // MARK: - Load & Play

    private func loadAndPlayCurrentItem() async throws {
        try throwIfInactive()

        await unregisterPrefetchIfNeeded()
        try throwIfInactive()

        let originalURL = await resolveCloudDriveStreamURLIfNeeded(item.fileURL)
        try throwIfInactive()

        let loadURL: URL
        let headerProvider = cloudDriveStreamingHeaderProvider()
        var usesPrefetch = false

        if originalURL.isFileURL {
            loadURL = originalURL
        } else if let registration = await PrefetchProxy.shared.register(
            originalURL: originalURL,
            headerProvider: headerProvider
        ) {
            try throwIfInactive()
            loadURL = registration.url
            prefetchRegistration = registration
            usesPrefetch = true
            VanmoLogger.player.info("[MacPlayerVM] using prefetch proxy for remote URL")
        } else {
            loadURL = originalURL
            VanmoLogger.player.info("[MacPlayerVM] prefetch unavailable, loading remote URL directly")
        }

        let playerItem = await makePlayerItem(
            url: loadURL,
            headerProvider: usesPrefetch ? nil : headerProvider
        )
        try throwIfInactive()

        player.replaceCurrentItem(with: playerItem)
        playbackState = .loading

        let assetDuration = try? await playerItem.asset.load(.duration)
        try throwIfInactive()

        if let assetDuration, assetDuration.isNumeric {
            duration = assetDuration.seconds
        } else if item.duration > 0 {
            duration = item.duration
        }

        setupTimeObserverIfNeeded()

        if startPosition > 0 {
            seek(toSeconds: startPosition)
        }
        player.playImmediately(atRate: defaultPlaybackRate)
        isPlaying = defaultPlaybackRate > 0
        playbackState = .playing
    }

    private func throwIfInactive() throws {
        try Task.checkCancellation()
        guard !didCleanup else { throw CancellationError() }
    }

    private func makePlayerItem(
        url: URL,
        headerProvider: (() async -> [String: String])?
    ) async -> AVPlayerItem {
        guard !url.isFileURL, let headerProvider else {
            return AVPlayerItem(url: url)
        }

        // Prefetch 不可用时，为需要自定义请求头的远程 URL 注入 header 兜底。
        let headers = await headerProvider()
        guard !headers.isEmpty else {
            return AVPlayerItem(url: url)
        }

        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return AVPlayerItem(asset: asset)
    }

    private func setupPlaybackObservers() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                    self?.playbackState = .playing
                case .paused:
                    self?.isPlaying = false
                    if self?.playbackState != .ended {
                        self?.playbackState = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self?.playbackState = .buffering
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func setupTimeObserverIfNeeded() {
        guard timeObserver == nil else { return }

        guard let playerItem = player.currentItem else { return }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                self?.playbackState = .ended
                self?.isPlaying = false
            }
            .store(in: &cancellables)

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

    // MARK: - Progress

    private func saveProgress() {
        guard !didSaveProgress, !item.isLiveStream else { return }
        didSaveProgress = true

        item.lastPlaybackPosition = currentTime
        item.lastPlayedAt = Date()
        if currentTime / max(duration, 1) > 0.9 {
            item.isWatched = true
        }

        let context = modelContext ?? item.modelContext
        if item.isProgressCloudSynced, let context {
            CloudSyncCoordinator.shared.markMediaProgressChanged(item, in: context)
            try? context.save()
            CloudSyncCoordinator.shared.requestSync(reason: "playback-progress", context: context)
        } else {
            try? context?.save()
        }
    }

    // MARK: - Remote URL Resolution

    private func unregisterPrefetchIfNeeded() async {
        guard let registration = prefetchRegistration else { return }
        prefetchRegistration = nil
        await PrefetchProxy.shared.unregister(token: registration.token)
    }

    private func resolveCloudDriveStreamURLIfNeeded(_ url: URL) async -> URL {
        guard let connectionId = item.sourceConnectionId,
              let serverPath = item.serverId,
              let modelContext else { return url }

        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first,
              connection.type.supportsOAuthLogin,
              !connection.type.requiresBearerStreaming else {
            return url
        }

        let service = RemoteServiceFactory.create(for: connection.type)
        do {
            try await service.connect(config: ConnectionConfig(from: connection))
            let placeholder = RemoteFile(
                name: item.originalFileName ?? url.lastPathComponent,
                path: serverPath,
                size: item.fileSize,
                isDirectory: false,
                modifiedDate: nil,
                type: .video
            )
            return try await service.streamURL(for: placeholder)
        } catch {
            VanmoLogger.player.error("[MacPlayerVM] 重新解析 \(connection.type.displayName) 直链失败，回退到缓存 URL: \(error.localizedDescription)")
            return url
        }
    }

    private func cloudDriveStreamingHeaderProvider() -> (() async -> [String: String])? {
        guard let modelContext, let connectionId = item.sourceConnectionId else { return nil }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first,
              connection.type.requiresStreamingHeaderProvider else {
            return nil
        }

        switch connection.type {
        case .googleDrive:
            let type = connection.type
            return {
                guard let token = try? await OAuthCoordinator.shared.validAccessToken(for: type, connectionId: connectionId) else {
                    return [:]
                }
                return ["Authorization": "Bearer \(token)"]
            }
        case .baiduNetdisk:
            return {
                ["User-Agent": BaiduNetdiskService.requiredUserAgent]
            }
        default:
            return nil
        }
    }
}
