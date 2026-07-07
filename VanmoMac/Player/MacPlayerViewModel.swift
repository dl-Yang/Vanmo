import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacPlayerViewModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferProgress: Double = 0
    @Published var volume: Double = 0.7
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var audioTracks: [AudioTrackInfo] = []
    @Published private(set) var subtitleTracks: [SubtitleTrackInfo] = []
    @Published private(set) var currentSubtitleText: String?
    @Published private(set) var episodeGroups: [MacPlayerEpisodeSeason] = []
    @Published private(set) var currentEpisodeID: String?
    @Published var config = PlayerConfig()
    @Published var subtitleStyle = MacSubtitleStylePreferences.load()
    @Published var showTrackSelector = false
    @Published var showEpisodeSelector = false
    @Published private(set) var onlineSubtitleResults: [OnlineSubtitleResult] = []
    @Published private(set) var isSearchingOnlineSubtitles = false
    @Published private(set) var isDownloadingOnlineSubtitle = false
    @Published private(set) var downloadingOnlineSubtitleID: String?
    @Published private(set) var onlineSubtitleStatusMessage: String?
    @Published var selectedEpisodeSeason: Int?
    @Published var alertMessage: String?
    @Published private(set) var activeEngineKind: MacPlayerEngineKind = .avFoundation

    let player: AVPlayer

    private var item: MediaItem
    private let initialStartPosition: TimeInterval
    private var modelContext: ModelContext?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var itemCancellables = Set<AnyCancellable>()
    private var ksCancellables = Set<AnyCancellable>()
    private var prefetchRegistration: PrefetchRegistration?
    private var didCleanup = false
    private var didSaveProgress = false
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private let legibleHandler = MacLegibleOutputHandler()
    private let externalSubtitleManager = SubtitleManager()
    private var ksEngine: MacKSPlayerEngine?
    private var activeExternalSubtitleID: Int?
    private var externalSubtitleTracks: [SubtitleTrackInfo] = []
    private var embeddedSubtitleActive = false
    private weak var connectionsViewModel: MacConnectionsViewModel?

    private static let externalSubtitleIDOffset = 10_000

    var usesKSPlayer: Bool { activeEngineKind == .ksPlayer }
    var ksVideoView: NSView? { ksEngine?.videoView }

    var canSelectEpisode: Bool {
        !episodeGroups.isEmpty
    }

    var selectedSeasonEpisodes: [MacPlayerEpisode] {
        let season = selectedEpisodeSeason ?? episodeGroups.first?.seasonNumber
        return episodeGroups.first { $0.seasonNumber == season }?.episodes ?? []
    }

    init(item: MediaItem, startPosition: TimeInterval = 0) {
        self.item = item
        self.initialStartPosition = startPosition
        self.player = AVPlayer()
        let savedRate = UserDefaults.standard.object(forKey: "playback.defaultRate") as? Double ?? 1.0
        config.playbackRate = PlayerConfig.clampedRate(Float(savedRate))
        player.volume = Float(volume)
        legibleHandler.onSubtitle = { [weak self] text in
            Task { @MainActor in
                guard let self, self.embeddedSubtitleActive, self.activeExternalSubtitleID == nil else { return }
                self.currentSubtitleText = text
            }
        }
        setupPlaybackObservers()
    }

    func onAppear(modelContext: ModelContext, connectionsViewModel: MacConnectionsViewModel) async {
        self.modelContext = modelContext
        self.connectionsViewModel = connectionsViewModel
        do {
            try await loadAndPlayCurrentItem()
            await loadEpisodesIfNeeded(modelContext: modelContext)
        } catch is CancellationError {
            return
        } catch let error as MacPlayerPlaybackError {
            guard !didCleanup else { return }
            alertMessage = error.localizedDescription
            playbackState = .error(error.localizedDescription)
        } catch {
            guard !didCleanup else { return }
            VanmoLogger.player.error("[MacPlayerVM] load failed: \(error.localizedDescription)")
            if activeEngineKind == .ksPlayer {
                alertMessage = MacPlayerPlaybackError.ffmpegLoadFailed(error.localizedDescription).localizedDescription
            }
            playbackState = .error(error.localizedDescription)
        }
    }

    func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true

        saveProgress()
        stopActiveEngines()

        if let registration = prefetchRegistration {
            prefetchRegistration = nil
            let token = registration.token
            Task {
                await PrefetchProxy.shared.unregister(token: token)
            }
        }

        Task {
            await externalSubtitleManager.clear()
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
        if usesKSPlayer {
            toggleKSPlayPause()
            return
        }

        switch playbackState {
        case .playing:
            player.pause()
            playbackState = .paused
            isPlaying = false
        case .paused, .ended:
            if isAtEnd {
                replayFromBeginning()
            } else {
                player.rate = config.playbackRate
                playbackState = .playing
                isPlaying = true
            }
        default:
            if isAtEnd {
                replayFromBeginning()
            }
        }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func adjustVolume(by delta: Double) {
        setVolume(volume + delta)
    }

    private var isAtEnd: Bool {
        playbackState == .ended || (duration > 0 && currentTime >= max(duration - 0.5, 0))
    }

    private func replayFromBeginning() {
        if usesKSPlayer {
            Task {
                await ksEngine?.seek(to: .zero)
                ksEngine?.playbackRate = config.playbackRate
                ksEngine?.play()
                currentTime = 0
                playbackState = .playing
                isPlaying = true
            }
            return
        }

        player.pause()
        player.seek(to: .zero) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                self.currentTime = 0
                self.player.rate = self.config.playbackRate
                self.playbackState = .playing
                self.isPlaying = true
            }
        }
    }

    func seek(to progress: Double) {
        let clamped = min(max(progress, 0), 1)
        seek(toSeconds: duration * clamped)
    }

    func skip(by seconds: TimeInterval) {
        seek(toSeconds: currentTime + seconds)
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        if usesKSPlayer {
            ksEngine?.setVolume(Float(volume))
        } else {
            player.volume = Float(volume)
        }
    }

    func setRate(_ rate: Float) {
        let clamped = PlayerConfig.clampedRate(rate)
        config.playbackRate = clamped
        if usesKSPlayer {
            ksEngine?.playbackRate = clamped
            if playbackState == .playing {
                ksEngine?.play()
            }
        } else if playbackState == .playing {
            player.rate = clamped
        }
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        config.scaleMode = mode
        if usesKSPlayer {
            ksEngine?.setScaleMode(mode)
        }
    }

    func selectAudioTrack(_ index: Int) {
        config.selectedAudioTrack = index
        Task { await applyAudioTrackSelection(index) }
    }

    func selectSubtitleTrack(_ index: Int?) {
        Task {
            let applied = await applySubtitleSelection(index)
            guard applied else { return }
            config.selectedSubtitleTrack = index
            persistSubtitlePreference(for: index)
        }
    }

    func searchOnlineSubtitles() {
        guard !isSearchingOnlineSubtitles else { return }
        isSearchingOnlineSubtitles = true
        onlineSubtitleStatusMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await OnlineSubtitleService.shared.search(for: self.item)
                self.onlineSubtitleResults = results
                self.onlineSubtitleStatusMessage = results.isEmpty ? "未找到匹配的在线字幕" : nil
                self.isSearchingOnlineSubtitles = false
            } catch {
                self.onlineSubtitleResults = []
                self.onlineSubtitleStatusMessage = error.localizedDescription
                self.isSearchingOnlineSubtitles = false
            }
        }
    }

    func downloadOnlineSubtitle(_ result: OnlineSubtitleResult) {
        guard !isDownloadingOnlineSubtitle else { return }
        isDownloadingOnlineSubtitle = true
        downloadingOnlineSubtitleID = result.id
        onlineSubtitleStatusMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let localURL = try await OnlineSubtitleService.shared.download(result, for: self.item)
                let trackID = self.nextExternalSubtitleID()
                let track = SubtitleTrackInfo(
                    id: trackID,
                    language: result.language,
                    title: "在线 · \(result.provider) · \(result.title)",
                    isEmbedded: false,
                    fileURL: localURL
                )
                self.externalSubtitleTracks.append(track)
                self.subtitleTracks.append(track)
                self.isDownloadingOnlineSubtitle = false
                self.downloadingOnlineSubtitleID = nil
                self.onlineSubtitleStatusMessage = "已加载在线字幕：\(result.title)"
                self.selectSubtitleTrack(trackID)
            } catch {
                self.isDownloadingOnlineSubtitle = false
                self.downloadingOnlineSubtitleID = nil
                self.onlineSubtitleStatusMessage = error.localizedDescription
                self.alertMessage = error.localizedDescription
            }
        }
    }

    func playEpisode(_ episode: MacPlayerEpisode) async {
        guard episode.id != currentEpisodeID else {
            showEpisodeSelector = false
            return
        }

        saveProgress()
        didSaveProgress = false

        await unregisterPrefetchIfNeeded()
        stopActiveEngines()

        if let mediaItem = episode.mediaItem {
            item = mediaItem
        } else {
            item = makeMediaItem(from: episode)
        }
        currentEpisodeID = episode.id
        showEpisodeSelector = false

        do {
            try await loadAndPlayCurrentItem()
        } catch let error as MacPlayerPlaybackError {
            VanmoLogger.player.error("[MacPlayerVM] episode switch failed: \(error.localizedDescription)")
            alertMessage = error.localizedDescription
            playbackState = .error(error.localizedDescription)
        } catch {
            VanmoLogger.player.error("[MacPlayerVM] episode switch failed: \(error.localizedDescription)")
            if activeEngineKind == .ksPlayer {
                alertMessage = MacPlayerPlaybackError.ffmpegLoadFailed(error.localizedDescription).localizedDescription
            }
            playbackState = .error(error.localizedDescription)
        }
    }

    // MARK: - Load & Play

    private func loadAndPlayCurrentItem() async throws {
        try throwIfInactive()
        resetPlaybackMetadata()
        stopActiveEngines()

        await unregisterPrefetchIfNeeded()
        try throwIfInactive()

        let resolvedURL = try await resolveSourcePlaybackURLIfNeeded(item.fileURL)
        try throwIfInactive()

        let originalURL = await resolveCloudDriveStreamURLIfNeeded(resolvedURL)
        try throwIfInactive()

        let engineKind = MacPlayerEngineFactory.engineKind(for: originalURL)
        switch engineKind {
        case .unsupportedDisc:
            throw MacPlayerPlaybackError.unsupportedDiscFormat
        case .ksPlayer:
            try await loadWithKSPlayer(originalURL: originalURL)
        case .avFoundation:
            try await loadWithAVPlayer(originalURL: originalURL)
        }
    }

    private func loadWithAVPlayer(originalURL: URL) async throws {
        activeEngineKind = .avFoundation

        let loadURL: URL
        let headerProvider = cloudDriveStreamingHeaderProvider()
        var usesPrefetch = false

        if originalURL.isFileURL || Self.shouldBypassPrefetch(for: originalURL) {
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

        attachLegibleOutput(to: playerItem)
        player.replaceCurrentItem(with: playerItem)
        playbackState = .loading

        let assetDuration = try? await playerItem.asset.load(.duration)
        try throwIfInactive()

        if let assetDuration, assetDuration.isNumeric {
            duration = assetDuration.seconds
        } else if item.duration > 0 {
            duration = item.duration
        }

        audioTracks = await availableAudioTracks(for: playerItem)
        let embeddedTracks = await availableSubtitleTracks(for: playerItem)
        externalSubtitleTracks = await discoverExternalSubtitleTracks(for: originalURL)
        subtitleTracks = embeddedTracks + externalSubtitleTracks
        await applyPreferredSubtitleIfNeeded()

        setupItemObservers(for: playerItem)

        let seekPosition = resolvedStartPosition()
        if seekPosition > 0 {
            seek(toSeconds: seekPosition)
        }

        player.rate = config.playbackRate
        isPlaying = config.playbackRate > 0
        playbackState = .playing
    }

    private func loadWithKSPlayer(originalURL: URL) async throws {
        activeEngineKind = .ksPlayer

        let loadURL: URL
        let headerProvider = cloudDriveStreamingHeaderProvider()
        var usesPrefetch = false

        if originalURL.isFileURL || Self.shouldBypassPrefetch(for: originalURL) {
            loadURL = originalURL
        } else if let registration = await PrefetchProxy.shared.register(
            originalURL: originalURL,
            headerProvider: headerProvider
        ) {
            try throwIfInactive()
            loadURL = registration.url
            prefetchRegistration = registration
            usesPrefetch = true
            VanmoLogger.player.info("[MacPlayerVM] KS using prefetch proxy for remote URL")
        } else {
            loadURL = originalURL
            VanmoLogger.player.info("[MacPlayerVM] KS prefetch unavailable, loading remote URL directly")
        }

        let headers: [String: String]
        if usesPrefetch || loadURL.isFileURL {
            headers = [:]
        } else {
            headers = await headerProvider?() ?? [:]
        }

        let engine = MacKSPlayerEngine()
        ksEngine = engine
        setupKSEngineObservers(for: engine)
        engine.setVolume(Float(volume))
        engine.setScaleMode(config.scaleMode)

        playbackState = .loading
        let seekPosition = resolvedStartPosition()
        let startTime = seekPosition > 0 ? CMTime(seconds: seekPosition, preferredTimescale: 600) : nil

        do {
            try await engine.load(url: loadURL, headers: headers, startPosition: startTime)
        } catch {
            throw MacPlayerPlaybackError.ffmpegLoadFailed(error.localizedDescription)
        }

        try throwIfInactive()

        if engine.duration.seconds > 0 {
            duration = engine.duration.seconds
        } else if item.duration > 0 {
            duration = item.duration
        }

        audioTracks = await engine.availableAudioTracks()
        let embeddedTracks = await engine.availableSubtitleTracks()
        externalSubtitleTracks = await discoverExternalSubtitleTracks(for: originalURL)
        subtitleTracks = embeddedTracks + externalSubtitleTracks
        await applyPreferredSubtitleIfNeeded()

        engine.playbackRate = config.playbackRate
        engine.play()
        currentTime = seekPosition
        isPlaying = true
        playbackState = .playing
    }

    private func resolvedStartPosition() -> TimeInterval {
        let resumeEnabled = UserDefaults.standard.object(forKey: "playback.resumePlayback") as? Bool ?? true
        if initialStartPosition > 0, currentEpisodeID == nil {
            return initialStartPosition
        }
        if resumeEnabled, item.lastPlaybackPosition > 0 {
            return item.lastPlaybackPosition
        }
        return 0
    }

    private func stopActiveEngines() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        legibleOutput = nil
        itemCancellables.removeAll()
        ksCancellables.removeAll()
        ksEngine?.stop()
        ksEngine = nil
    }

    private func toggleKSPlayPause() {
        guard let ksEngine else { return }
        switch playbackState {
        case .playing:
            ksEngine.pause()
            playbackState = .paused
            isPlaying = false
        case .paused, .ended:
            if isAtEnd {
                replayFromBeginning()
            } else {
                ksEngine.playbackRate = config.playbackRate
                ksEngine.play()
                playbackState = .playing
                isPlaying = true
            }
        default:
            if isAtEnd {
                replayFromBeginning()
            }
        }
    }

    private func setupKSEngineObservers(for engine: MacKSPlayerEngine) {
        ksCancellables.removeAll()

        engine.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                playbackState = state
                switch state {
                case .playing:
                    isPlaying = true
                case .paused, .ended, .error:
                    isPlaying = false
                case .buffering:
                    break
                default:
                    break
                }
                if case .ended = state {
                    handlePlaybackEnded()
                }
            }
            .store(in: &ksCancellables)

        engine.currentTimePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self else { return }
                currentTime = time.seconds
            }
            .store(in: &ksCancellables)

        engine.durationPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self, time.seconds.isFinite, time.seconds > 0 else { return }
                duration = time.seconds
            }
            .store(in: &ksCancellables)

        engine.bufferProgressPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.bufferProgress = progress
            }
            .store(in: &ksCancellables)

        engine.subtitleTextPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self, embeddedSubtitleActive, activeExternalSubtitleID == nil else { return }
                currentSubtitleText = text
            }
            .store(in: &ksCancellables)
    }

    private func resetPlaybackMetadata() {
        currentTime = 0
        duration = 0
        bufferProgress = 0
        audioTracks = []
        subtitleTracks = []
        currentSubtitleText = nil
        activeExternalSubtitleID = nil
        embeddedSubtitleActive = false
        externalSubtitleTracks = []
        onlineSubtitleResults = []
        onlineSubtitleStatusMessage = nil
        Task {
            await externalSubtitleManager.clear()
        }
    }

    private func attachLegibleOutput(to playerItem: AVPlayerItem) {
        legibleOutput = nil
        let output = AVPlayerItemLegibleOutput()
        output.setDelegate(legibleHandler, queue: .main)
        output.suppressesPlayerRendering = true
        playerItem.add(output)
        legibleOutput = output
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
                    if self?.playbackState != .ended {
                        self?.playbackState = .playing
                    }
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

    private func setupItemObservers(for playerItem: AVPlayerItem) {
        itemCancellables.removeAll()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                self?.handlePlaybackEnded()
            }
            .store(in: &itemCancellables)

        playerItem.publisher(for: \.loadedTimeRanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] ranges in
                guard let self,
                      let first = ranges.first?.timeRangeValue,
                      self.duration > 0 else { return }
                let buffered = first.start.seconds + first.duration.seconds
                self.bufferProgress = min(max(buffered / self.duration, 0), 1)
            }
            .store(in: &itemCancellables)

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if self.duration <= 0,
               let itemDuration = self.player.currentItem?.duration.seconds,
               itemDuration.isFinite {
                self.duration = itemDuration
            }
            self.updateExternalSubtitle(at: time.seconds)
        }
    }

    private func handlePlaybackEnded() {
        playbackState = .ended
        isPlaying = false
        saveProgress()

        let autoPlayNext = UserDefaults.standard.object(forKey: "playback.autoPlay") as? Bool ?? true
        guard autoPlayNext, let next = nextEpisode(after: currentEpisode) else { return }

        Task {
            await playEpisode(next)
        }
    }

    private var currentEpisode: MacPlayerEpisode? {
        episodeGroups
            .flatMap(\.episodes)
            .first { $0.id == currentEpisodeID }
    }

    private func nextEpisode(after current: MacPlayerEpisode?) -> MacPlayerEpisode? {
        guard let current else { return nil }
        let all = episodeGroups.flatMap(\.episodes).sorted(by: episodeSortPredicate)
        guard let index = all.firstIndex(where: { $0.id == current.id }), index + 1 < all.count else {
            return nil
        }
        return all[index + 1]
    }

    private func seek(toSeconds seconds: TimeInterval) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        if usesKSPlayer {
            Task {
                await ksEngine?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
                currentTime = clamped
                updateExternalSubtitle(at: clamped)
            }
            return
        }
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateExternalSubtitle(at: clamped)
    }

    // MARK: - Tracks

    private func availableAudioTracks(for playerItem: AVPlayerItem) async -> [AudioTrackInfo] {
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible) else {
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

    private func availableSubtitleTracks(for playerItem: AVPlayerItem) async -> [SubtitleTrackInfo] {
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else {
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

    private func applyAudioTrackSelection(_ index: Int) async {
        if usesKSPlayer {
            await ksEngine?.selectAudioTrack(index: index)
            return
        }
        guard let playerItem = player.currentItem,
              let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible) else { return }
        let options = group.options
        guard index < options.count else { return }
        playerItem.select(options[index], in: group)
    }

    private func applySubtitleSelection(_ index: Int?) async -> Bool {
        embeddedSubtitleActive = false
        currentSubtitleText = nil

        guard let index else {
            activeExternalSubtitleID = nil
            await externalSubtitleManager.clear()
            if usesKSPlayer {
                await ksEngine?.selectSubtitleTrack(index: nil)
            } else {
                await selectEmbeddedSubtitleTrack(nil)
            }
            return true
        }

        guard let track = subtitleTracks.first(where: { $0.id == index }) else { return false }

        if let fileURL = track.fileURL, !track.isEmbedded {
            if usesKSPlayer {
                alertMessage = "Mac KSPlayer 路径暂不支持外挂字幕，请选择内嵌字幕"
                return false
            }
            await selectEmbeddedSubtitleTrack(nil)
            switch SubtitleFormat.detect(from: fileURL) {
            case .srt, .vtt:
                do {
                    try await externalSubtitleManager.load(from: fileURL)
                    await externalSubtitleManager.setDelay(config.subtitleDelay)
                    activeExternalSubtitleID = track.id
                    updateExternalSubtitle(at: currentTime)
                    return true
                } catch {
                    activeExternalSubtitleID = nil
                    alertMessage = error.localizedDescription
                    return false
                }
            case .ass:
                alertMessage = "Mac 播放器暂不支持 ASS 外挂字幕"
                return false
            case .unknown:
                alertMessage = "不支持的字幕格式"
                return false
            }
        }

        activeExternalSubtitleID = nil
        await externalSubtitleManager.clear()
        if usesKSPlayer {
            embeddedSubtitleActive = true
            await ksEngine?.selectSubtitleTrack(index: index)
            currentSubtitleText = nil
            return true
        }
        await selectEmbeddedSubtitleTrack(index)
        embeddedSubtitleActive = true
        return true
    }

    private func selectEmbeddedSubtitleTrack(_ index: Int?) async {
        guard let playerItem = player.currentItem,
              let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else { return }
        if let index, index < group.options.count {
            playerItem.select(group.options[index], in: group)
        } else {
            playerItem.select(nil, in: group)
        }
    }

    private func updateExternalSubtitle(at time: TimeInterval) {
        guard activeExternalSubtitleID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let cue = await externalSubtitleManager.cue(at: time)
            await MainActor.run {
                guard self.activeExternalSubtitleID != nil else { return }
                self.currentSubtitleText = cue?.text
            }
        }
    }

    private func nextExternalSubtitleID() -> Int {
        let maxExternalID = subtitleTracks
            .map(\.id)
            .filter { $0 >= Self.externalSubtitleIDOffset }
            .max()
        return (maxExternalID ?? (Self.externalSubtitleIDOffset - 1)) + 1
    }

    private func applyPreferredSubtitleIfNeeded() async {
        guard !subtitleTracks.isEmpty else { return }

        switch resolveSavedSubtitleSelection() {
        case .off:
            config.selectedSubtitleTrack = nil
            _ = await applySubtitleSelection(nil)
            return
        case .track(let savedIndex):
            if await applySubtitleSelection(savedIndex) {
                config.selectedSubtitleTrack = savedIndex
            }
            return
        case .none:
            break
        }

        let subtitleAutoLoad = UserDefaults.standard.object(forKey: "subtitle.autoLoad") as? Bool ?? true
        if !subtitleAutoLoad {
            config.selectedSubtitleTrack = nil
            _ = await applySubtitleSelection(nil)
            return
        }

        let preferredLanguage = UserDefaults.standard.string(forKey: "subtitle.preferredLanguage") ?? "zh"
        guard let preferredIndex = preferredSubtitleIndex(for: preferredLanguage, tracks: subtitleTracks) else {
            return
        }

        if await applySubtitleSelection(preferredIndex) {
            config.selectedSubtitleTrack = preferredIndex
        }
    }

    private enum SavedSubtitleSelection {
        case off
        case track(Int)
    }

    private func resolveSavedSubtitleSelection() -> SavedSubtitleSelection? {
        guard let preference = item.subtitlePreference else { return nil }
        if preference == "off" { return .off }

        if preference.hasPrefix("embedded:"),
           let index = Int(preference.dropFirst("embedded:".count)),
           subtitleTracks.contains(where: { $0.id == index && $0.isEmbedded }) {
            return .track(index)
        }

        if preference.hasPrefix("external:") {
            let fileName = String(preference.dropFirst("external:".count))
            if let track = subtitleTracks.first(where: { !$0.isEmbedded && $0.fileURL?.lastPathComponent == fileName }) {
                return .track(track.id)
            }
        }

        return nil
    }

    private func persistSubtitlePreference(for index: Int?) {
        let preference: String
        if let index {
            guard let track = subtitleTracks.first(where: { $0.id == index }) else { return }
            if track.isEmbedded {
                preference = "embedded:\(index)"
            } else if let fileName = track.fileURL?.lastPathComponent {
                preference = "external:\(fileName)"
            } else {
                return
            }
        } else {
            preference = "off"
        }

        item.subtitlePreference = preference
        let context = modelContext ?? item.modelContext
        try? context?.save()
    }

    private func preferredSubtitleIndex(for preferredLanguage: String, tracks: [SubtitleTrackInfo]) -> Int? {
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
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func discoverExternalSubtitleTracks(for videoURL: URL) async -> [SubtitleTrackInfo] {
        let baseTracks: [SubtitleTrackInfo]
        if videoURL.isFileURL {
            baseTracks = Self.localExternalSubtitleTracks(for: videoURL)
        } else {
            baseTracks = await remoteExternalSubtitleTracks()
        }
        let onlineTracks = await cachedOnlineSubtitleTracks(startingID: Self.externalSubtitleIDOffset + baseTracks.count)
        return baseTracks + onlineTracks
    }

    private static func localExternalSubtitleTracks(for videoURL: URL) -> [SubtitleTrackInfo] {
        guard videoURL.isFileURL else { return [] }
        return SubtitleManager.findSubtitleFiles(for: videoURL)
            .filter { url in
                switch SubtitleFormat.detect(from: url) {
                case .srt, .vtt, .ass:
                    return true
                case .unknown:
                    return false
                }
            }
            .enumerated()
            .map { index, url in
                SubtitleTrackInfo(
                    id: externalSubtitleIDOffset + index,
                    language: languageCode(from: url),
                    title: url.deletingPathExtension().lastPathComponent,
                    isEmbedded: false,
                    fileURL: url
                )
            }
    }

    private static func languageCode(from subtitleURL: URL) -> String? {
        let nameParts = subtitleURL.deletingPathExtension().lastPathComponent
            .split(separator: ".")
            .map { String($0).lowercased() }
        return nameParts.last { part in
            ["zh", "chs", "cht", "en", "ja", "ko"].contains(part)
        }
    }

    private func cachedOnlineSubtitleTracks(startingID: Int) async -> [SubtitleTrackInfo] {
        do {
            let urls = try await OnlineSubtitleService.shared.cachedSubtitleURLs(for: item)
            return urls.enumerated().map { index, url in
                SubtitleTrackInfo(
                    id: startingID + index,
                    language: Self.languageCode(from: url),
                    title: Self.onlineSubtitleTitle(from: url),
                    isEmbedded: false,
                    fileURL: url
                )
            }
        } catch {
            return []
        }
    }

    private static func onlineSubtitleTitle(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-", maxSplits: 3).map(String.init)
        guard parts.count == 4 else { return stem }
        return "在线 · \(parts[1]) · \(parts[3].replacingOccurrences(of: "-", with: " "))"
    }

    private func remoteExternalSubtitleTracks() async -> [SubtitleTrackInfo] {
        guard let connectionId = item.sourceConnectionId,
              let serverPath = item.serverId,
              let modelContext else { return [] }

        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first else { return [] }

        let supportedTypes: Set<ConnectionType> = [
            .webdav, .alist, .fnos, .smb,
            .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk,
        ]
        guard supportedTypes.contains(connection.type) else { return [] }

        let videoBaseName = (serverPath as NSString).lastPathComponent
        let videoStem = (videoBaseName as NSString).deletingPathExtension
        guard !videoStem.isEmpty else { return [] }
        let parentPath = (serverPath as NSString).deletingLastPathComponent

        let service = RemoteServiceFactory.create(for: connection.type)
        do {
            let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            let config = ConnectionConfig(from: connection, password: password)
            try await service.connect(config: config)

            let siblings = try await service.listDirectory(path: parentPath)
            let matches = siblings.filter { file in
                guard !file.isDirectory else { return false }
                let stem = (file.name as NSString).deletingPathExtension
                guard stem.hasPrefix(videoStem) else { return false }
                switch SubtitleFormat.detect(from: URL(fileURLWithPath: file.name)) {
                case .srt, .vtt, .ass: return true
                default: return false
                }
            }

            guard !matches.isEmpty else {
                await service.disconnect()
                return []
            }

            let cacheDir = try Self.remoteSubtitleCacheDirectory()
            var tracks: [SubtitleTrackInfo] = []
            for (index, file) in matches.enumerated() {
                let localURL = cacheDir.appendingPathComponent("\(item.id.uuidString)-\(file.name)")
                do {
                    try await service.download(file: file, to: localURL, progress: { _ in })
                } catch {
                    continue
                }
                tracks.append(
                    SubtitleTrackInfo(
                        id: Self.externalSubtitleIDOffset + index,
                        language: Self.languageCode(from: localURL),
                        title: (file.name as NSString).deletingPathExtension,
                        isEmbedded: false,
                        fileURL: localURL
                    )
                )
            }
            await service.disconnect()
            return tracks
        } catch {
            await service.disconnect()
            return []
        }
    }

    private static func remoteSubtitleCacheDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("RemoteSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Episodes

    private func loadEpisodesIfNeeded(modelContext: ModelContext?) async {
        guard isEpisodeSelectableItem else {
            episodeGroups = []
            selectedEpisodeSeason = nil
            currentEpisodeID = nil
            return
        }

        var episodes = loadLocalEpisodes(modelContext: modelContext)
        if episodes.count <= 1 {
            episodes = await loadRemoteEpisodes()
        }

        episodeGroups = groupedEpisodes(from: episodes)
        selectedEpisodeSeason = item.seasonNumber ?? episodeGroups.first?.seasonNumber
        currentEpisodeID = episodes.first { matchesCurrentItem($0) }?.id
    }

    private var isEpisodeSelectableItem: Bool {
        item.mediaType == .tvEpisode || item.mediaType == .tvShow || item.showTitle != nil || item.seriesId != nil
    }

    private func loadLocalEpisodes(modelContext: ModelContext?) -> [MacPlayerEpisode] {
        guard let modelContext,
              let showTitle = normalizedShowTitle(for: item) else { return [] }

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                sortBy: [
                    SortDescriptor(\.seasonNumber),
                    SortDescriptor(\.episodeNumber),
                    SortDescriptor(\.title),
                ]
            )
            return try modelContext.fetch(descriptor)
                .filter { candidate in
                    candidate.mediaType == .tvEpisode
                        && candidate.sourceConnectionId == item.sourceConnectionId
                        && normalizedShowTitle(for: candidate) == showTitle
                        && candidate.seasonNumber != nil
                        && candidate.episodeNumber != nil
                }
                .sorted(by: episodeSortPredicate)
                .map(MacPlayerEpisode.init(mediaItem:))
        } catch {
            return []
        }
    }

    private func loadRemoteEpisodes() async -> [MacPlayerEpisode] {
        guard let seriesId = item.seriesId ?? (item.mediaType == .tvShow ? item.serverId : nil) else {
            return []
        }

        do {
            let episodes: [EpisodeInfo]
            if let snapshot = try? MediaServerConnectionResolver.snapshot(for: item, in: modelContext) {
                if snapshot.type == .plex {
                    episodes = try await PlexEpisodeFetcher.fetchEpisodes(
                        seriesRatingKey: seriesId,
                        connection: snapshot
                    )
                } else {
                    episodes = try await EmbyEpisodeFetcher.fetchEpisodes(seriesId: seriesId, connection: snapshot)
                }
            } else if isPlexEpisodeSource {
                episodes = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: seriesId)
            } else {
                episodes = try await EmbyEpisodeFetcher.fetchEpisodes(seriesId: seriesId)
            }
            return episodes.map { MacPlayerEpisode(episodeInfo: $0, showTitle: item.showTitle ?? item.title) }
        } catch {
            return []
        }
    }

    private var isPlexEpisodeSource: Bool {
        item.fileURL.query?.contains("X-Plex-Token") == true || item.fileURL.host == "plex-series"
    }

    private func groupedEpisodes(from episodes: [MacPlayerEpisode]) -> [MacPlayerEpisodeSeason] {
        Dictionary(grouping: episodes, by: \.seasonNumber)
            .map { season, episodes in
                MacPlayerEpisodeSeason(
                    seasonNumber: season,
                    episodes: episodes.sorted(by: episodeSortPredicate)
                )
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private func makeMediaItem(from episode: MacPlayerEpisode) -> MediaItem {
        let episodeItem = MediaItem(
            title: episode.showTitle ?? episode.title,
            fileURL: episode.fileURL,
            mediaType: .tvEpisode,
            duration: episode.duration
        )
        episodeItem.showTitle = episode.showTitle ?? item.showTitle
        episodeItem.seasonNumber = episode.seasonNumber
        episodeItem.episodeNumber = episode.episodeNumber
        episodeItem.episodeTitle = episode.title
        episodeItem.posterURL = item.posterURL
        episodeItem.backdropURL = item.backdropURL
        episodeItem.serverId = episode.serverId
        episodeItem.seriesId = item.seriesId ?? (item.mediaType == .tvShow ? item.serverId : nil)
        episodeItem.sourceConnectionId = item.sourceConnectionId
        return episodeItem
    }

    private func matchesCurrentItem(_ episode: MacPlayerEpisode) -> Bool {
        if let mediaItem = episode.mediaItem, mediaItem.id == item.id {
            return true
        }
        return episode.fileURL == item.fileURL
            && episode.seasonNumber == item.seasonNumber
            && episode.episodeNumber == item.episodeNumber
    }

    private func normalizedShowTitle(for item: MediaItem) -> String? {
        let rawTitle = item.showTitle ?? (item.mediaType == .tvShow ? item.title : nil)
        guard let rawTitle else { return nil }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func episodeSortPredicate(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let lhsSeason = lhs.seasonNumber ?? Int.max
        let rhsSeason = rhs.seasonNumber ?? Int.max
        if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode { return lhsEpisode < rhsEpisode }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func episodeSortPredicate(_ lhs: MacPlayerEpisode, _ rhs: MacPlayerEpisode) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber { return lhs.seasonNumber < rhs.seasonNumber }
        if lhs.episodeNumber != rhs.episodeNumber { return lhs.episodeNumber < rhs.episodeNumber }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
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

    private func resolveSourcePlaybackURLIfNeeded(_ url: URL) async throws -> URL {
        guard let connectionsViewModel, let modelContext else {
            let prepared = MacLocalFilePlayback.prepareLocalFileURL(url)
            try MacLocalFilePlayback.verifyReadableFile(at: prepared)
            return prepared
        }

        do {
            return try await connectionsViewModel.resolvePlaybackURL(for: item, modelContext: modelContext)
        } catch let error as MacPlayerPlaybackError {
            throw error
        } catch {
            VanmoLogger.player.error(
                "[MacPlayerVM] resolve playback URL failed, fallback to cached URL: \(error.localizedDescription)"
            )
            let prepared = MacLocalFilePlayback.prepareLocalFileURL(url)
            try MacLocalFilePlayback.verifyReadableFile(at: prepared)
            return prepared
        }
    }

    private static func shouldBypassPrefetch(for url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "concat", "smb":
            return true
        default:
            return false
        }
    }

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

// MARK: - Legible Output Handler

private final class MacLegibleOutputHandler: NSObject, AVPlayerItemLegibleOutputPushDelegate {
    var onSubtitle: ((String?) -> Void)?

    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.map(\.string).joined(separator: "\n")
        onSubtitle?(text.isEmpty ? nil : text)
    }
}

// MARK: - Episode Models

struct MacPlayerEpisodeSeason: Identifiable, Equatable {
    let seasonNumber: Int
    let episodes: [MacPlayerEpisode]

    var id: Int { seasonNumber }
}

struct MacPlayerEpisode: Identifiable, Equatable {
    let id: String
    let title: String
    let showTitle: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let duration: TimeInterval
    let fileURL: URL
    let serverId: String?
    let mediaItem: MediaItem?

    init(mediaItem: MediaItem) {
        let seasonNumber = mediaItem.seasonNumber ?? 0
        let episodeNumber = mediaItem.episodeNumber ?? 0
        self.id = "media-\(mediaItem.id.uuidString)"
        self.title = mediaItem.episodeTitle ?? mediaItem.title
        self.showTitle = mediaItem.showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = mediaItem.duration
        self.fileURL = mediaItem.fileURL
        self.serverId = mediaItem.serverId
        self.mediaItem = mediaItem
    }

    init(episodeInfo: EpisodeInfo, showTitle: String?) {
        self.id = "remote-\(episodeInfo.id)"
        self.title = episodeInfo.title
        self.showTitle = showTitle
        self.seasonNumber = episodeInfo.seasonNumber
        self.episodeNumber = episodeInfo.episodeNumber
        self.duration = episodeInfo.duration
        self.fileURL = episodeInfo.streamURL
        self.serverId = episodeInfo.id
        self.mediaItem = nil
    }

    var displayTitle: String {
        title.isEmpty ? "第 \(episodeNumber) 集" : title
    }

    var episodeCode: String {
        "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
    }
}

private extension VideoScaleMode {
    var avPlayerViewVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fit:
            return .resizeAspect
        case .fill:
            return .resizeAspectFill
        case .stretch:
            return .resize
        }
    }
}

extension MacPlayerViewModel {
    var videoGravity: AVLayerVideoGravity {
        config.scaleMode.avPlayerViewVideoGravity
    }
}
