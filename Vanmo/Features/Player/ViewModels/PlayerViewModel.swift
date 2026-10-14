import SwiftUI
import AVFoundation
import Combine
import SwiftData
import VanmoCore

@MainActor
final class PlayerViewModel: ObservableObject {
    @AppStorage("subtitle.autoLoad") private var subtitleAutoLoad = true
    @AppStorage("subtitle.preferredLanguage") private var subtitlePreferredLanguage = "zh"

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var cacheStart: Double = 0
    @Published private(set) var cacheEnd: Double = 0
    @Published private(set) var audioTracks: [AudioTrackInfo] = []
    @Published private(set) var subtitleTracks: [SubtitleTrackInfo] = []
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var currentSubtitleContent: SubtitleContent?
    @Published private(set) var episodeGroups: [PlayerEpisodeSeason] = []
    @Published private(set) var currentEpisodeID: String?
    @Published private(set) var isPictureInPictureActive = false

    @Published var config = PlayerConfig()
    @Published var subtitleStyle = SubtitleStyle() {
        didSet { SubtitleStylePreferences.save(subtitleStyle) }
    }
    @Published var controlsVisible = true
    /// 拖进度条时控制栏不能自动隐藏：进度条一旦移出视图，拖动手势就收不到结束事件，松手不会跳转。
    @Published var isSeeking = false {
        didSet {
            guard oldValue != isSeeking else { return }
            if isSeeking {
                hideControlsTask?.cancel()
            } else if controlsVisible {
                scheduleHideControls()
            }
        }
    }
    @Published var seekTime: TimeInterval = 0
    @Published var showAudioSelector = false
    @Published var showSubtitleSelector = false
    @Published var showChapterList = false
    @Published var showEpisodeSelector = false
    @Published var selectedEpisodeSeason: Int?
    @Published var brightnessOverlay: Float?
    @Published var volumeOverlay: Float?
    @Published var seekOverlay: TimeInterval?
    @Published var isRateBoosting = false
    @Published var seekPreviewActive = false
    @Published var seekPreviewForward = true
    @Published var seekPreviewImage: UIImage?
    @Published var scrubTargetTime: TimeInterval?
    @Published var videoQuality = PlaybackPreferences.videoQuality
    @Published var introWindow: IntroSkipWindow?
    @Published var notice: PlayerNotice?
    @Published private(set) var onlineSubtitleResults: [OnlineSubtitleResult] = []
    @Published private(set) var isSearchingOnlineSubtitles = false
    @Published private(set) var isDownloadingOnlineSubtitle = false
    @Published private(set) var downloadingOnlineSubtitleID: String?
    @Published private(set) var onlineSubtitleStatusMessage: String?

    private(set) var engine: PlayerEngine
    private var item: MediaItem
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var engineCancellables = Set<AnyCancellable>()
    private var hideControlsTask: Task<Void, Never>?
    private var prefetchToken: String?
    private var prefetchProxyURL: URL?
    private var showsFullLocalCache = false
    private var lastPrefetchNoteTime: TimeInterval = -.infinity
    /// 引擎 seek 到续播点之前会先报 0。此期间向前填充用这个时间。
    private var pendingPrefetchStart: TimeInterval?
    private var didStopPlaybackResources = false
    private var liveRetryCount = 0
    private let externalSubtitleManager = SubtitleManager()
    private var subtitleDiscoveryTask: Task<Void, Never>?
    private var externalSubtitleCueTask: Task<Void, Never>?
    private var mediaGeneration: UInt64 = 0
    private var seekRequestGeneration: UInt64 = 0
    private var activeExternalSubtitleID: Int?
    private var activeRichSubtitleID: Int?
    private var externalSubtitleTracks: [SubtitleTrackInfo] = []
    private var discChapters: [Chapter] = []
    private var seekBaseTime: TimeInterval?
    private var seekPreviewTask: Task<Void, Never>?
    private var seekPreviewRequestedTime: TimeInterval?
    private var previewWarmTask: Task<Void, Never>?
    private var previewWarmDuration: TimeInterval = 0
    private let scrubPreviewLane = ScrubPreviewLane()
    private var directPlaybackURL: URL?
    private var activePlaybackURL: URL?
    private var playbackTimeOrigin: TimeInterval = 0
    private var qualityClockMode: QualityClockMode = .direct
    private var qualityClockCorrectUntil: CFAbsoluteTime = 0
    private var qualityClockFrozenAt: TimeInterval?
    private var qualityReloadID: UInt64 = 0
    private var programDuration: TimeInterval = 0
    @Published var qualityHoldImage: UIImage?
    private var clearQualityHoldOnFrame = false
    private var qualityHoldOpenedAt: CFAbsoluteTime?
    /// 被取代的 reload 不会自己收尾；记下它已对引擎做了什么，由最新请求失败时恢复。
    private var qualityReloadEngineEffect: QualityReloadEngineEffect = .none
    /// Audio-only media, an undecodable video track, or a flushed KSPlayer view never reports a frame.
    private static let qualityHoldTimeout: CFAbsoluteTime = 3
    private var qualitySwitchTask: Task<Void, Never>?
    private var previewLaneURL: URL?
    private var previewLaneHeaders: [String: String] = [:]
    private var previewLaneHeaderProvider: (() async -> [String: String])?
    private var introMarkerTask: Task<Void, Never>?
    private var playbackSession: EmbyPlaybackSession?
    private var didReportWatchedToServer = false
    #if os(iOS)
    private let rateBoostHaptic = UIImpactFeedbackGenerator(style: .medium)
    #endif

    private static let externalSubtitleIDOffset = 10_000

    private enum QualityClockMode {
        case direct
        case pending
        case relative
        case absolute
    }

    private enum QualityReloadEngineEffect {
        case none
        case paused
        case replaced
    }

    var canSelectEpisode: Bool {
        !episodeGroups.isEmpty
    }

    var hasEmbeddedSubtitleTracks: Bool {
        subtitleTracks.contains { $0.isEmbedded }
    }

    var selectedSeasonEpisodes: [PlayerEpisode] {
        let season = selectedEpisodeSeason ?? episodeGroups.first?.seasonNumber
        return episodeGroups.first { $0.seasonNumber == season }?.episodes ?? []
    }

    init(item: MediaItem) {
        self.item = item
        self.subtitleStyle = SubtitleStylePreferences.load()
        VanmoLogger.player.info("[PlayerVM] init, file: \(item.fileURL.lastPathComponent), URL: \(item.fileURL.safePlaybackLogDescription)")
        self.engine = PlayerEngineFactory.engine(for: item.fileURL)
        VanmoLogger.player.info("[PlayerVM] engine type: \(self.engine.engineType == .avFoundation ? "AVFoundation" : "KSPlayer")")
        setupBindings()
    }

    // MARK: - Engine Access

    var avPlayer: AVPlayer? {
        (engine as? AVPlayerEngine)?.avPlayer
    }

    #if os(iOS)
    var ksPlayerVideoView: UIView? {
        (engine as? KSPlayerEngine)?.videoView
    }
    #endif

    var canShowPictureInPictureButton: Bool {
        avPlayer != nil || engine is KSPlayerEngine
    }

    var isPictureInPicturePossible: Bool {
        if avPlayer != nil { return true }
        return (engine as? KSPlayerEngine)?.isPictureInPicturePossible == true
    }

    private var engineHasRenderedVideoFrame: Bool {
        if let ksEngine = engine as? KSPlayerEngine { return ksEngine.hasRenderedVideoFrame }
        return (engine as? AVPlayerEngine)?.hasRenderedVideoFrame ?? true
    }

    var supportsVideoAirPlay: Bool {
        (engine as? AirPlayRouting)?.supportsVideoAirPlay == true
    }

    var canSkipIntro: Bool {
        guard let introWindow, !isLiveStream else { return false }
        return introWindow.contains(displayTime)
    }

    var displayTime: TimeInterval {
        if seekPreviewActive { return seekTime }
        if let scrubTargetTime { return scrubTargetTime }
        return currentTime
    }

    var availableVideoQualities: [PlaybackVideoQuality] {
        PlaybackVideoQuality.allCases.filter { quality in
            quality == .original || quality.isAvailable(sourceHeight: item.videoHeight)
        }
    }

    // MARK: - Setup

    private func setupBindings() {
        bindEngine()

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAirPlayRouteChange()
            }
            .store(in: &cancellables)

#if DEBUG
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let type = rawType.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
                let typeName = String(describing: type)
                VanmoLogger.player.info("[Debug][PiP] audioInterruption type=\(typeName, privacy: .public)")
            }
            .store(in: &cancellables)
#endif
    }

    private func bindEngine() {
        engine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                VanmoLogger.player.info("[PlayerVM] state changed: \(String(describing: state))")
                self?.playbackState = state
                self?.handleLiveStreamStateIfNeeded(state)
            }
            .store(in: &engineCancellables)

        engine.currentTimePublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .sink { [weak self] time in
                guard let self else { return }
                if let frozen = self.qualityClockFrozenAt {
                    self.currentTime = frozen
                    return
                }
                self.reconcileQualityClock(engineTime: time)
                let absolute = time + self.playbackTimeOrigin
                self.currentTime = absolute
                if self.clearQualityHoldOnFrame, time > 0.2, let openedAt = self.qualityHoldOpenedAt {
                    let rendered = self.engineHasRenderedVideoFrame
                    let timedOut = CFAbsoluteTimeGetCurrent() - openedAt > Self.qualityHoldTimeout
                    if rendered || timedOut {
                        self.qualityHoldImage = nil
                        self.clearQualityHoldOnFrame = false
                        self.qualityHoldOpenedAt = nil
#if DEBUG
                        VanmoLogger.player.info("[Debug][Player] event=videoQualityHoldCleared engineTime=\(time, privacy: .public) rendered=\(rendered, privacy: .public)")
#endif
                    }
                }
                self.updateExternalSubtitle(at: absolute)
                self.reportPlaybackTimeUpdate(at: absolute)
                self.notePrefetchPlayheadIfNeeded(time: absolute)
            }
            .store(in: &engineCancellables)

        engine.durationPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .sink { [weak self] dur in
                guard let self else { return }
                if self.playbackTimeOrigin > 0, self.programDuration > dur + 5 {
                    return
                }
                VanmoLogger.player.info("[PlayerVM] duration updated: \(dur)s")
                self.duration = dur
                if dur > self.programDuration {
                    self.programDuration = dur
                }
                self.startSeekPreviewWarmupIfNeeded()
                self.notePrefetchPlayheadIfNeeded(time: self.currentTime, force: true)
            }
            .store(in: &engineCancellables)

        engine.cacheSpanPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] span in
                self?.applyEngineCacheSpan(span)
            }
            .store(in: &engineCancellables)

        engine.subtitleContentPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard self?.activeExternalSubtitleID == nil else { return }
                self?.currentSubtitleContent = content
            }
            .store(in: &engineCancellables)

        if let ksEngine = engine as? KSPlayerEngine {
            ksEngine.pictureInPictureActivePublisher
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .assign(to: &$isPictureInPictureActive)
        }
    }

    private func useEngine(for url: URL) {
        var needsAV = url.path.lowercased().contains(".m3u8")
#if DEBUG
        if PlaybackPreferences.debugNativeVideoEngine == .avFoundation,
           SupportedFormat.detect(from: url) == .native,
           MediaFormatProbe.nativeVideoExtensions.contains(url.pathExtension.lowercased()) {
            needsAV = true
        }
#endif
        if needsAV == (engine is AVPlayerEngine) { return }
        engine.stop()
        engineCancellables.removeAll()
        engine = needsAV ? AVPlayerEngine() : KSPlayerEngine()
        bindEngine()
#if DEBUG
        let name = needsAV ? "AVPlayer" : "KSPlayer"
        VanmoLogger.player.info("[Debug][Player] event=videoQualityEngine engine=\(name, privacy: .public) path=\(url.safePlaybackLogDescription, privacy: .public)")
#endif
    }

    // MARK: - Lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
#if DEBUG
        let name: String
        switch phase {
        case .active:
            name = "active"
        case .inactive:
            name = "inactive"
        case .background:
            name = "background"
        @unknown default:
            name = "unknown"
        }
        let playback = String(describing: playbackState)
        let possible = isPictureInPicturePossible
        let active = isPictureInPictureActive
        VanmoLogger.player.info("[Debug][PiP] scenePhase=\(name, privacy: .public) playback=\(playback, privacy: .public) possible=\(possible, privacy: .public) active=\(active, privacy: .public)")
#endif
    }

    func handleMemoryWarning() {
#if DEBUG
        let playback = String(describing: playbackState)
        let possible = isPictureInPicturePossible
        let active = isPictureInPictureActive
        VanmoLogger.player.info("[Debug][PiP] memoryWarning playback=\(playback, privacy: .public) possible=\(possible, privacy: .public) active=\(active, privacy: .public)")
#endif
    }

    func onAppear(modelContext: ModelContext? = nil) async {
        self.modelContext = modelContext
        VanmoLogger.player.info("[PlayerVM] onAppear, loading file: \(self.item.fileURL.lastPathComponent)")
        do {
            try await loadAndPlayCurrentItem()
            await loadEpisodesIfNeeded(modelContext: modelContext)
            scheduleHideControls()
        } catch is CancellationError {
            return
        } catch {
            VanmoLogger.player.error("[PlayerVM] load failed: \(error.localizedDescription)")
#if DEBUG
            let nsError = error as NSError
            let domain = nsError.domain
            let code = nsError.code
            let ext = item.fileURL.pathExtension.lowercased()
            let isFile = item.fileURL.isFileURL
            VanmoLogger.player.info("[Debug][Player] load failed domain=\(domain, privacy: .public) code=\(code, privacy: .public) ext=\(ext, privacy: .public) isFile=\(isFile, privacy: .public)")
#endif
            playbackState = .error(error.localizedDescription)
        }
    }

    func closePlayback() {
#if os(iOS)
        if let ksEngine = engine as? KSPlayerEngine {
            ksEngine.disableAutomaticPictureInPicture()
        }
#endif
        onDisappear(keepingPlaybackActive: false)
    }

    func onDisappear(keepingPlaybackActive: Bool = false) {
        // closePlayback() already saved progress; the engine reports 0 after stop.
        guard !didStopPlaybackResources else { return }
        VanmoLogger.player.info("[PlayerVM] onDisappear, saving progress at \(self.currentTime)s")
        saveProgress()
        guard !keepingPlaybackActive else {
            VanmoLogger.player.info("[PlayerVM] keeping playback alive for Picture in Picture")
            return
        }
        stopPlaybackResources()
    }

    private func stopPlaybackResources(force: Bool = false) {
        guard force || !didStopPlaybackResources else { return }
        didStopPlaybackResources = true
#if DEBUG
        let engineName = engine is KSPlayerEngine ? "ks" : "av"
        let hasPrefetch = prefetchToken != nil
        VanmoLogger.player.info("[Debug][PlaybackPerf] event=cleanup platform=ios engine=\(engineName, privacy: .public) prefetch=\(hasPrefetch, privacy: .public)")
#endif
        subtitleDiscoveryTask?.cancel()
        subtitleDiscoveryTask = nil
        externalSubtitleCueTask?.cancel()
        externalSubtitleCueTask = nil
        introMarkerTask?.cancel()
        introMarkerTask = nil
        seekPreviewTask?.cancel()
        seekPreviewTask = nil
        seekPreviewRequestedTime = nil
        previewWarmTask?.cancel()
        previewWarmTask = nil
        previewWarmDuration = 0
        scrubPreviewLane.close()
        qualitySwitchTask?.cancel()
        qualitySwitchTask = nil
        qualityReloadID &+= 1
        previewLaneURL = nil
        previewLaneHeaders = [:]
        previewLaneHeaderProvider = nil
        mediaGeneration &+= 1
        seekRequestGeneration &+= 1
        let stopPosition = currentTime
        let session = playbackSession
        playbackSession = nil
        Task {
            await session?.stopped(position: stopPosition)
        }
        engine.stop()
        if let token = prefetchToken {
            prefetchToken = nil
            prefetchProxyURL = nil
            Task {
                await PrefetchProxy.shared.unregister(token: token)
            }
        }
    }

    private func loadAndPlayCurrentItem() async throws {
        subtitleDiscoveryTask?.cancel()
        subtitleDiscoveryTask = nil
        externalSubtitleCueTask?.cancel()
        externalSubtitleCueTask = nil
        introMarkerTask?.cancel()
        introMarkerTask = nil
        seekPreviewTask?.cancel()
        seekPreviewTask = nil
        seekPreviewRequestedTime = nil
        previewWarmTask?.cancel()
        previewWarmTask = nil
        previewWarmDuration = 0
        scrubPreviewLane.close()
        qualitySwitchTask?.cancel()
        qualitySwitchTask = nil
        qualityReloadID &+= 1
        let loadReloadID = qualityReloadID
        mediaGeneration &+= 1
        seekRequestGeneration &+= 1
        didStopPlaybackResources = false
        let generation = mediaGeneration
        try await unregisterPrefetchIfNeeded()
        guard generation == mediaGeneration else { return }
        resetPlaybackMetadata()

        let originalURL = await resolveCloudDriveStreamURLIfNeeded(item.fileURL)
        let playbackURL = await resolveDiscPlaybackURLIfNeeded(originalURL)
        guard generation == mediaGeneration else { return }
        directPlaybackURL = playbackURL
        let resolvedQuality = PlaybackVideoQuality.resolved(
            requested: PlaybackPreferences.videoQuality,
            sourceHeight: item.videoHeight
        )
        videoQuality = resolvedQuality
        let qualified = await resolvedPlaybackURL(
            direct: playbackURL,
            quality: videoQuality,
            startTime: item.lastPlaybackPosition
        )
        guard generation == mediaGeneration else { return }
        beginQualityClock(origin: qualified.timeOrigin)
        if item.duration > 1 {
            programDuration = item.duration
            duration = item.duration
        }
        let headerProvider = cloudDriveStreamingHeaderProvider()
        previewLaneURL = playbackURL
        previewLaneHeaderProvider = headerProvider
        let loadURL: URL
        var loadHeaders: [String: String] = [:]
        showsFullLocalCache = false
        prefetchProxyURL = nil
        if qualified.url.isFileURL || Self.shouldBypassPrefetch(for: qualified.url) {
            loadURL = qualified.url
            if qualified.url.isFileURL {
                showsFullLocalCache = true
                cacheStart = 0
                cacheEnd = 1
#if DEBUG
                VanmoLogger.prefetch.info("[Debug][Prefetch] event=skip reason=localFile span=0-1")
#endif
            }
            if PrefetchConfig.isMediaServerPlaylist(qualified.url) {
                VanmoLogger.player.info("[PlayerVM] media-server playlist, skip prefetch")
#if DEBUG
                VanmoLogger.prefetch.info("[Debug][Prefetch] event=skip reason=mediaServerPlaylist")
#endif
            }
        } else if usesOfficialDownloadLink(), let headerProvider {
            let headers = await headerProvider()
            guard generation == mediaGeneration else { return }
            guard !headers.isEmpty else {
                throw PlayerError.networkError("无法为该网盘注入播放鉴权头")
            }
            loadURL = playbackURL
            loadHeaders = headers
            VanmoLogger.player.info("[PlayerVM] official download link, skip prefetch")
        } else if let registration = await PrefetchProxy.shared.register(
            originalURL: playbackURL,
            headerProvider: headerProvider
        ) {
            guard generation == mediaGeneration else {
                await PrefetchProxy.shared.unregister(token: registration.token)
                return
            }
            loadURL = registration.url
            prefetchToken = registration.token
            prefetchProxyURL = registration.url
            VanmoLogger.player.info("[PlayerVM] using prefetch proxy for remote URL")
            Self.logMediaServerPrefetchRegistration(playbackURL)
        } else if let headerProvider {
            let headers = await headerProvider()
            guard generation == mediaGeneration else { return }
            guard !headers.isEmpty else {
                throw PlayerError.networkError("无法为该网盘注入播放鉴权头")
            }
            loadURL = playbackURL
            loadHeaders = headers
            VanmoLogger.player.info("[PlayerVM] prefetch unavailable, loading remote URL with streaming headers")
        } else {
            loadURL = playbackURL
            VanmoLogger.player.info("[PlayerVM] prefetch unavailable, loading remote URL directly")
        }

        let startPosition: CMTime? = playbackTimeOrigin > 0 || item.lastPlaybackPosition <= 0
            ? nil
            : CMTime(seconds: item.lastPlaybackPosition, preferredTimescale: 600)
        let primeTime = playbackTimeOrigin > 1 ? playbackTimeOrigin : (startPosition?.seconds ?? 0)
        await HlsTranscodePrimer.prime(playlistURL: loadURL, startTime: primeTime)
        guard generation == mediaGeneration else { return }
        useEngine(for: loadURL)
        VanmoLogger.player.info("[PlayerVM] calling engine.load(), startPosition: \(startPosition?.seconds ?? 0)s url=\(loadURL.safePlaybackLogDescription, privacy: .public)")
#if DEBUG
        let openSummary = PlaybackQualityStream.debugSummary(of: loadURL)
        VanmoLogger.player.info("[Debug][Player] event=videoQualityOpen quality=\(self.videoQuality.rawValue, privacy: .public) \(openSummary, privacy: .public)")
#endif
        var openedURL = loadURL
        do {
            try await loadEngine(url: loadURL, startPosition: startPosition, headers: loadHeaders)
        } catch {
            guard generation == mediaGeneration else { return }
            if error is CancellationError { throw error }
            guard loadURL != playbackURL else { throw error }
            VanmoLogger.player.error("[PlayerVM] transcode open failed, falling back to direct url=\(playbackURL.safePlaybackLogDescription, privacy: .public)")
#if DEBUG
            let nsError = error as NSError
            VanmoLogger.player.info("[Debug][Player] event=videoQualityResult result=fallbackDirect domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) path=\(playbackURL.safePlaybackLogDescription, privacy: .public)")
            await Self.logQualityResponse(loadURL)
#endif
            playbackTimeOrigin = 0
            qualityClockMode = .direct
            let fallbackStart: CMTime? = item.lastPlaybackPosition > 0
                ? CMTime(seconds: item.lastPlaybackPosition, preferredTimescale: 600)
                : nil
            let fallbackURL: URL
            if PrefetchConfig.isProxyURL(loadURL) {
                try await unregisterPrefetchIfNeeded()
                fallbackURL = playbackURL
            } else {
                fallbackURL = try await registerPrefetchReplacingCurrent(playbackURL)
            }
            guard generation == mediaGeneration else { return }
            useEngine(for: fallbackURL)
            let fallbackHeaders = PrefetchConfig.isProxyURL(fallbackURL) ? [:] : loadHeaders
            try await loadEngine(url: fallbackURL, startPosition: fallbackStart, headers: fallbackHeaders)
            openedURL = fallbackURL
        }
        guard generation == mediaGeneration else {
            // close() 之后仍可能完成 engine.load() 并重建播放器；必须强制拆掉。
            stopPlaybackResources(force: true)
            return
        }
        activePlaybackURL = openedURL
        if qualityReloadID == loadReloadID {
            syncDisplayedVideoQuality(requested: resolvedQuality)
        }
        armQualityClockCorrection()
        VanmoLogger.player.info("[PlayerVM] engine.load() succeeded, state: \(String(describing: self.playbackState))")
        previewLaneHeaders = loadHeaders
        configureSeekPreviewSource(originalURL: originalURL, headers: loadHeaders)
        audioTracks = await engine.availableAudioTracks()
        let embeddedSubtitleTracks = await engine.availableSubtitleTracks()
        guard generation == mediaGeneration else { return }
        subtitleTracks = embeddedSubtitleTracks
        await applyPreferredSubtitleIfNeeded(generation: generation)
        guard generation == mediaGeneration else { return }
        VanmoLogger.player.info("[PlayerVM] calling engine.play()")
        engine.play()
        VanmoLogger.player.info("[PlayerVM] engine.play() called, state: \(String(describing: self.playbackState))")
        VanmoLogger.player.info("[PlayerVM] audio tracks: \(self.audioTracks.count), subtitle tracks: \(self.subtitleTracks.count)")
        await updateDynamicRangeIfNeeded(for: originalURL)
        guard generation == mediaGeneration else { return }
        loadChapters()
        preparePlaybackSession()
        let reportPosition = startPosition?.seconds ?? currentTime
        Task {
            guard generation == mediaGeneration else { return }
            await playbackSession?.started(position: reportPosition)
        }
        scheduleExternalSubtitleDiscovery(for: originalURL, generation: generation)
    }

    /// Keeps the embedded tracks current at completion; a quality reload may have replaced the engine.
    private func scheduleExternalSubtitleDiscovery(for videoURL: URL, generation: UInt64) {
        subtitleDiscoveryTask = Task { [weak self] in
            guard let self else { return }
            let tracks = await discoverExternalSubtitleTracks(for: videoURL)
            guard !Task.isCancelled, generation == mediaGeneration else { return }
            guard !tracks.isEmpty else { return }
            externalSubtitleTracks = tracks
            subtitleTracks = subtitleTracks.filter(\.isEmbedded) + tracks
            await applyPreferredSubtitleIfNeeded(generation: generation)
            guard !Task.isCancelled, generation == mediaGeneration else { return }
            VanmoLogger.subtitle.info(
                "[PlayerVM] asynchronous external subtitle discovery completed count=\(tracks.count)"
            )
        }
    }

    private func resetPlaybackMetadata() {
        currentTime = 0
        duration = 0
        playbackTimeOrigin = 0
        qualityClockMode = .direct
        qualityClockCorrectUntil = 0
        qualityClockFrozenAt = nil
        programDuration = 0
        qualityHoldImage = nil
        clearQualityHoldOnFrame = false
        qualityHoldOpenedAt = nil
        qualityReloadEngineEffect = .none
        cacheStart = 0
        cacheEnd = 0
        showsFullLocalCache = false
        lastPrefetchNoteTime = -.infinity
        pendingPrefetchStart = nil
        audioTracks = []
        subtitleTracks = []
        chapters = []
        introWindow = nil
        currentSubtitleContent = nil
        activeExternalSubtitleID = nil
        activeRichSubtitleID = nil
        externalSubtitleTracks = []
        onlineSubtitleResults = []
        onlineSubtitleStatusMessage = nil
        discChapters = []
        Task {
            await externalSubtitleManager.clear()
        }
    }

    var displayTitle: String {
        item.displayTitle
    }

    private func applyEngineCacheSpan(_ span: MediaCacheSpan) {
        guard prefetchToken == nil, !showsFullLocalCache else { return }
        cacheStart = span.startFraction
        cacheEnd = span.endFraction
    }

    private func notePrefetchPlayheadIfNeeded(time: TimeInterval, force: Bool = false) {
        guard let token = prefetchToken, duration > 1 else { return }
        let resolved = PrefetchResumePlayhead.resolve(reported: time, pendingStart: pendingPrefetchStart)
        pendingPrefetchStart = resolved.pendingStart
        let playhead = resolved.time
        if !force, abs(playhead - lastPrefetchNoteTime) < 1 { return }
        lastPrefetchNoteTime = playhead
#if DEBUG
        if abs(playhead - time) > 0.001 {
            VanmoLogger.prefetch.info(
                "[Debug][Prefetch] event=resumePlayhead time=\(playhead, privacy: .public) reported=\(time, privacy: .public)"
            )
        }
#endif
        let fraction = min(max(playhead / duration, 0), 1)
        let mediaDuration = duration
        Task {
            await PrefetchProxy.shared.notePlayhead(
                token: token,
                fraction: fraction,
                duration: mediaDuration
            )
            let span = await PrefetchProxy.shared.cacheSpan(for: token)
            guard self.prefetchToken == token else { return }
            self.cacheStart = span.startFraction
            self.cacheEnd = span.endFraction
#if DEBUG
            let start = span.startFraction
            let end = span.endFraction
            VanmoLogger.prefetch.info(
                "[Debug][Prefetch] event=cacheSpan fraction=\(fraction, privacy: .public) start=\(start, privacy: .public) end=\(end, privacy: .public)"
            )
#endif
        }
    }

    private func unregisterPrefetchIfNeeded() async throws {
        guard let token = prefetchToken else { return }
        prefetchToken = nil
        prefetchProxyURL = nil
        await PrefetchProxy.shared.unregister(token: token)
    }

    /// OneDrive/Box/pCloud/Yandex.Disk 换到的直链都是有时效性的签名 URL，扫描时持久化进
    /// `MediaItem.fileURL` 的版本很可能在播放时已经过期；这里按 `sourceConnectionId + serverId`
    /// 重新连接对应服务、换一个新鲜直链再播放。Google Drive 的 API URL 本身不过期（靠下面的
    /// headerProvider 动态带 Bearer），不需要这一步；非 OAuth 网盘也直接跳过。
    private func resolveCloudDriveStreamURLIfNeeded(_ url: URL) async -> URL {
        guard PlaybackURLResolver.isPlaceholder(url),
              let connectionId = item.sourceConnectionId,
              let modelContext else { return url }

        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first else {
            return url
        }

        let service = RemoteServiceFactory.create(for: connection.type)
        do {
            let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            try await service.connect(config: ConnectionConfig(from: connection, password: password))
            defer { Task { await service.disconnect() } }
            return try await PlaybackURLResolver.resolvePlaybackURL(item: item, service: service)
        } catch {
            VanmoLogger.player.error("[PlayerVM] 重新解析 \(connection.type.displayName) 播放地址失败，回退到缓存 URL: \(error.localizedDescription)")
            return url
        }
    }

    private func loadEngine(url: URL, startPosition: CMTime?, headers: [String: String]) async throws {
        if let seconds = startPosition?.seconds, seconds > 1 {
            pendingPrefetchStart = seconds
        } else {
            pendingPrefetchStart = nil
        }
        if headers.isEmpty {
            try await engine.load(url: url, startPosition: startPosition)
            return
        }
        guard let ksEngine = engine as? KSPlayerEngine else {
            throw PlayerError.networkError("无法建立带鉴权的播放代理")
        }
        try await ksEngine.load(url: url, startPosition: startPosition, headers: headers)
    }

    private func usesOfficialDownloadLink() -> Bool {
        guard let modelContext, let connectionId = item.sourceConnectionId else { return false }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first else {
            return false
        }
        return connection.type.usesOfficialDownloadLink
    }

    /// 若当前条目来自需要自定义请求头的 OAuth 网盘，返回 header provider 交给 PrefetchProxy：
    /// - Google Drive：动态 Bearer token
    /// - 百度网盘：固定 User-Agent（dlink 下载/播放要求）
    private func cloudDriveStreamingHeaderProvider() -> (() async -> [String: String])? {
        guard let modelContext, let connectionId = item.sourceConnectionId else { return nil }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        guard let connection = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return StreamingRequestHeaders.provider(for: connection.type, connectionId: connectionId)
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        switch playbackState {
        case .playing:
            engine.pause()
            Task {
                await playbackSession?.progress(
                    position: currentTime,
                    isPaused: true,
                    event: .pause
                )
            }
        case .paused:
            engine.play()
            Task {
                await playbackSession?.progress(
                    position: currentTime,
                    isPaused: false,
                    event: .unpause
                )
            }
        case .ended:
            Task {
                await engine.seek(to: .zero)
                engine.play()
                await playbackSession?.progress(
                    position: 0,
                    isPaused: false,
                    event: .unpause,
                    force: true
                )
            }
        default:
            break
        }
        showControlsBriefly()
    }

    func seek(to time: TimeInterval) {
        let limit = programDuration > 0 ? programDuration : duration
        let clampedTime = max(0, min(time, limit > 0 ? limit : time))
        seekRequestGeneration &+= 1
        let seekGeneration = seekRequestGeneration
        let itemGeneration = mediaGeneration
        if shouldReopenTranscode(at: clampedTime) {
            let from = currentTime
            qualityClockFrozenAt = clampedTime
            currentTime = clampedTime
            qualityReloadID &+= 1
            let reloadID = qualityReloadID
            qualitySwitchTask?.cancel()
            qualitySwitchTask = Task { [weak self] in
                guard let self else { return }
#if DEBUG
                VanmoLogger.player.info("[Debug][Player] event=videoQualitySeek mode=reopen time=\(clampedTime, privacy: .public) from=\(from, privacy: .public) hold=\(clampedTime, privacy: .public)")
#endif
                guard !Task.isCancelled, reloadID == self.qualityReloadID else { return }
                let opened = await self.reopenTranscodedPlayback(
                    at: clampedTime,
                    generation: itemGeneration,
                    reloadID: reloadID
                )
                if !opened {
                    await self.recoverAbandonedQualityReload(generation: itemGeneration, reloadID: reloadID)
                }
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let engineTime = max(0, clampedTime - playbackTimeOrigin)
            await engine.seek(to: CMTime(seconds: engineTime, preferredTimescale: 600))
            guard seekRequestGeneration == seekGeneration,
                  mediaGeneration == itemGeneration else { return }
            let isPaused = playbackState == .paused || playbackState == .ended
            await playbackSession?.progress(
                position: clampedTime,
                isPaused: isPaused,
                event: .seek,
                force: true
            )
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
        let clampedRate = PlayerConfig.clampedRate(rate)
        config.playbackRate = clampedRate
        engine.playbackRate = clampedRate
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        config.scaleMode = mode
        if let ksEngine = engine as? KSPlayerEngine {
            ksEngine.setContentMode(mode.uiViewContentMode)
        }
    }

    func cycleScaleMode() {
        let modes = VideoScaleMode.allCases
        let index = modes.firstIndex(of: config.scaleMode) ?? 0
        setScaleMode(modes[(index + 1) % modes.count])
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        config.volume = clamped
        avPlayer?.volume = clamped
        (engine as? KSPlayerEngine)?.setPlaybackVolume(clamped)
    }

    func setVideoQuality(_ quality: PlaybackVideoQuality) {
        let resolved = PlaybackVideoQuality.resolved(requested: quality, sourceHeight: item.videoHeight)
#if DEBUG
        let sourceHeight = item.videoHeight ?? 0
        VanmoLogger.player.info("[Debug][Player] event=videoQualitySelect requested=\(quality.rawValue, privacy: .public) resolved=\(resolved.rawValue, privacy: .public) current=\(self.videoQuality.rawValue, privacy: .public) sourceHeight=\(sourceHeight, privacy: .public)")
#endif
        guard resolved != videoQuality || quality != PlaybackPreferences.videoQuality else {
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=videoQualitySkip reason=unchanged")
#endif
            return
        }
        videoQuality = resolved
        let generation = mediaGeneration
        qualityReloadID &+= 1
        let reloadID = qualityReloadID
        qualitySwitchTask?.cancel()
        qualitySwitchTask = Task { [weak self] in
            guard let self, !Task.isCancelled, reloadID == self.qualityReloadID else { return }
            let opened = await self.applyVideoQualitySelection(resolved, generation: generation, reloadID: reloadID)
            guard !Task.isCancelled, reloadID == self.qualityReloadID else { return }
            if opened {
                PlaybackPreferences.videoQuality = resolved
                self.syncDisplayedVideoQuality(requested: resolved)
            } else {
                await self.recoverAbandonedQualityReload(generation: generation, reloadID: reloadID)
                self.syncDisplayedVideoQuality(requested: PlaybackPreferences.videoQuality)
            }
        }
    }

    private func syncDisplayedVideoQuality(requested: PlaybackVideoQuality) {
        guard let openedURL = activePlaybackURL else {
            videoQuality = requested
            return
        }
        let shown = PlaybackVideoQuality.effective(requested: requested, openedURL: openedURL)
#if DEBUG
        if shown != requested {
            VanmoLogger.player.info("[Debug][Player] event=videoQualityDisplay requested=\(requested.rawValue, privacy: .public) shown=\(shown.rawValue, privacy: .public) reason=originalBitstream")
        }
#endif
        videoQuality = shown
    }

    private func resolvedPlaybackURL(
        direct: URL,
        quality: PlaybackVideoQuality,
        startTime: TimeInterval
    ) async -> (url: URL, timeOrigin: TimeInterval) {
        guard quality != .original,
              let connectionType = currentMediaServerType() else {
            return (direct, 0)
        }
        if engine is AVPlayerEngine, direct.path.lowercased().contains("m3u8") {
            return (direct, 0)
        }
        if connectionType == .emby || connectionType == .jellyfin, let itemID = item.serverId {
            if let transcoded = await EmbyTranscodeClient.transcodeURL(
                directURL: direct,
                itemID: itemID,
                quality: quality,
                startTime: startTime
            ) {
                return (transcoded, max(0, startTime))
            }
            return (direct, 0)
        }
        let transcoded = PlaybackQualityStream.playbackURL(
            directURL: direct,
            serverItemID: item.serverId,
            connectionType: connectionType,
            quality: quality,
            startTime: startTime
        )
        guard transcoded != direct else { return (direct, 0) }
        return (transcoded, max(0, startTime))
    }

    private func currentMediaServerType() -> ConnectionType? {
        try? MediaServerConnectionResolver.snapshot(for: item, in: modelContext)?.type
    }

    private func applyVideoQualitySelection(
        _ quality: PlaybackVideoQuality,
        generation: UInt64,
        reloadID: UInt64
    ) async -> Bool {
        guard generation == mediaGeneration else { return false }
        if let avEngine = engine as? AVPlayerEngine,
           directPlaybackURL?.path.lowercased().contains("m3u8") == true {
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=videoQualityApply mode=variant quality=\(quality.rawValue, privacy: .public)")
#endif
            avEngine.applyVideoQuality(quality)
            return true
        }
        guard let direct = directPlaybackURL, let connectionType = currentMediaServerType() else {
#if DEBUG
            let hasDirect = directPlaybackURL != nil
            VanmoLogger.player.info("[Debug][Player] event=videoQualitySkip reason=notServer hasDirect=\(hasDirect, privacy: .public)")
#endif
            return false
        }
        let position = currentTime
        let resolved = await resolvedPlaybackURL(direct: direct, quality: quality, startTime: position)
        let target = resolved.url
        guard quality == .original || Self.isTranscodePlaylist(target) else {
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=videoQualitySkip reason=noPlaylist quality=\(quality.rawValue, privacy: .public)")
#endif
            await resumeDetachedProxyIfNeeded()
            return false
        }
        let timeOrigin = resolved.timeOrigin
        let startPosition: CMTime? = timeOrigin > 0 || position <= 0
            ? nil
            : CMTime(seconds: position, preferredTimescale: 600)
#if DEBUG
        let summary = PlaybackQualityStream.debugSummary(of: target)
        let sameAsDirect = target == direct
        VanmoLogger.player.info("[Debug][Player] event=videoQualityApply mode=reload quality=\(quality.rawValue, privacy: .public) server=\(String(describing: connectionType), privacy: .public) sameAsDirect=\(sameAsDirect, privacy: .public) origin=\(timeOrigin, privacy: .public) \(summary, privacy: .public)")
#endif
        return await reloadPlaybackSource(
            url: target,
            startPosition: startPosition,
            timeOrigin: timeOrigin,
            generation: generation,
            reloadID: reloadID
        )
    }

    private static func isTranscodePlaylist(_ url: URL) -> Bool {
        url.path.lowercased().contains(".m3u8")
    }

    /// 清晰度切换若已停下正在读预取的播放器、但新地址没有打开，就用仍在的会话把原画接回来。
    private func resumeDetachedProxyIfNeeded() async {
        guard let proxy = prefetchProxyURL, prefetchToken != nil else { return }
        guard engine.state != .playing else { return }
        let resumeTime = currentTime > 1 ? currentTime : pendingPrefetchStart
        let start = (resumeTime ?? 0) > 1
            ? CMTime(seconds: resumeTime ?? 0, preferredTimescale: 600)
            : nil
        do {
            try await loadEngine(url: proxy, startPosition: start, headers: [:])
            engine.play()
            qualityReloadEngineEffect = .none
        } catch {
            VanmoLogger.player.error("[PlayerVM] videoQuality resume proxy failed: \(error.localizedDescription)")
        }
    }

    private func shouldReopenTranscode(at time: TimeInterval) -> Bool {
        guard videoQuality != .original else { return false }
        guard let type = currentMediaServerType(), type == .emby || type == .jellyfin else { return false }
        guard activePlaybackURL?.path.lowercased().contains(".m3u8") == true else { return false }
        if playbackTimeOrigin > 0, time + 0.5 < playbackTimeOrigin { return true }
        return abs(time - currentTime) > 1
    }

    private func reopenTranscodedPlayback(
        at time: TimeInterval,
        generation: UInt64,
        reloadID: UInt64
    ) async -> Bool {
        guard generation == mediaGeneration,
              let direct = directPlaybackURL,
              currentMediaServerType() != nil else { return false }
        let resolved = await resolvedPlaybackURL(direct: direct, quality: videoQuality, startTime: time)
        let target = resolved.url
        let timeOrigin = resolved.timeOrigin
        let startPosition: CMTime? = timeOrigin > 0 || time <= 0
            ? nil
            : CMTime(seconds: time, preferredTimescale: 600)
        let opened = await reloadPlaybackSource(
            url: target,
            startPosition: startPosition,
            timeOrigin: timeOrigin,
            generation: generation,
            reloadID: reloadID,
            holdsFrame: false
        )
        if opened {
            syncDisplayedVideoQuality(requested: videoQuality)
        }
        return opened
    }

    /// `holdsFrame` covers a quality change with the last picture; a seek reopen shows the new position instead.
    private func reloadPlaybackSource(
        url: URL,
        startPosition: CMTime?,
        timeOrigin: TimeInterval,
        generation: UInt64,
        reloadID: UInt64? = nil,
        holdsFrame: Bool = true
    ) async -> Bool {
        guard generation == mediaGeneration else { return false }
        if let reloadID, reloadID != qualityReloadID || Task.isCancelled { return false }
        let previousURL = activePlaybackURL
        let previousOrigin = playbackTimeOrigin
        #if os(iOS)
        if holdsFrame {
            let holdImage: UIImage?
            if let ksEngine = engine as? KSPlayerEngine {
                holdImage = await ksEngine.currentThumbnail()
            } else {
                holdImage = (engine as? AVPlayerEngine)?.currentFrameImage()
            }
            if let holdImage {
                qualityHoldImage = holdImage
                clearQualityHoldOnFrame = true
            }
#if DEBUG
            let holdSource = engine is KSPlayerEngine ? "ks" : "av"
            VanmoLogger.player.info("[Debug][Player] event=videoQualityHoldFrame engine=\(holdSource, privacy: .public) captured=\(holdImage != nil, privacy: .public)")
#endif
        } else {
            qualityHoldImage = nil
            clearQualityHoldOnFrame = false
        }
        #endif
        let frozen = timeOrigin > 0.5 ? timeOrigin : max(startPosition?.seconds ?? currentTime, 0)
        qualityClockFrozenAt = frozen
        currentTime = frozen
        engine.pause()
        qualityReloadEngineEffect = .paused
        qualityHoldOpenedAt = nil
        if clearQualityHoldOnFrame {
            // `openEngine` can stop the current layer synchronously; SwiftUI must draw the cover first.
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard generation == mediaGeneration, !Task.isCancelled else { return false }
        if let reloadID, reloadID != qualityReloadID { return false }
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=videoQualityHold time=\(frozen, privacy: .public)")
#endif
        VanmoLogger.player.info("[PlayerVM] videoQuality reload url=\(url.safePlaybackLogDescription, privacy: .public) origin=\(timeOrigin, privacy: .public)")
        let mediaTime = timeOrigin > 1 ? timeOrigin : max(0, startPosition?.seconds ?? 0)
        do {
            qualityReloadEngineEffect = .replaced
            try await openEngine(url: url, startPosition: startPosition, mediaTime: mediaTime)
            guard generation == mediaGeneration, !Task.isCancelled else { return false }
            if let reloadID, reloadID != qualityReloadID { return false }
            qualityReloadEngineEffect = .none
            beginQualityClock(origin: timeOrigin)
            qualityClockFrozenAt = nil
            qualityHoldOpenedAt = CFAbsoluteTimeGetCurrent()
            activePlaybackURL = url
            armQualityClockCorrection()
            engine.playbackRate = config.playbackRate
            engine.play()
#if DEBUG
            let summary = PlaybackQualityStream.debugSummary(of: url)
            VanmoLogger.player.info("[Debug][Player] event=videoQualityResult result=opened \(summary, privacy: .public)")
#endif
            await reattachTracksAfterReload(
                generation: generation,
                reloadID: reloadID,
                sameStreamLayout: !holdsFrame
            )
            return true
        } catch {
            // 引擎被外部 stop 取消了就绪等待：拆除方负责后续，不能再回滚重开。
            if error is CancellationError, !Task.isCancelled { return false }
            let stale = Task.isCancelled
                || generation != mediaGeneration
                || (reloadID.map { $0 != qualityReloadID } ?? false)
            if stale {
                let superseded = reloadID.map { $0 != qualityReloadID } ?? false
                if !superseded, generation == mediaGeneration {
                    await resumeDetachedProxyIfNeeded()
                }
                return false
            }
            clearQualityHold()
            playbackTimeOrigin = previousOrigin
            qualityClockMode = previousOrigin > 0.5 ? .pending : .direct
            VanmoLogger.player.error("[PlayerVM] videoQuality reload failed: \(error.localizedDescription)")
#if DEBUG
            let nsError = error as NSError
            VanmoLogger.player.info("[Debug][Player] event=videoQualityResult result=reloadFailed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            await Self.logQualityResponse(url)
#endif
            guard let previousURL, previousURL != url else { return false }
            await restorePlayback(
                previousURL,
                origin: previousOrigin,
                generation: generation,
                reloadID: reloadID
            )
            return false
        }
    }

    private func clearQualityHold() {
        qualityHoldImage = nil
        clearQualityHoldOnFrame = false
        qualityHoldOpenedAt = nil
        qualityClockFrozenAt = nil
        qualityReloadEngineEffect = .none
    }

    private func restorePlayback(
        _ previousURL: URL,
        origin previousOrigin: TimeInterval,
        generation: UInt64,
        reloadID: UInt64?
    ) async {
        let restoreURL = PrefetchConfig.isProxyURL(previousURL) && prefetchToken == nil
            ? (directPlaybackURL ?? previousURL)
            : previousURL
        let restoreStart: CMTime? = previousOrigin > 0
            ? nil
            : CMTime(seconds: max(0, currentTime), preferredTimescale: 600)
        let restoreTime = previousOrigin > 1 ? previousOrigin : max(0, currentTime)
        do {
            qualityReloadEngineEffect = .replaced
            try await openEngine(url: restoreURL, startPosition: restoreStart, mediaTime: restoreTime)
            qualityReloadEngineEffect = .none
            activePlaybackURL = restoreURL
            armQualityClockCorrection()
            engine.playbackRate = config.playbackRate
            engine.play()
#if DEBUG
            let summary = PlaybackQualityStream.debugSummary(of: previousURL)
            VanmoLogger.player.info("[Debug][Player] event=videoQualityResult result=restored \(summary, privacy: .public)")
#endif
            await reattachTracksAfterReload(
                generation: generation,
                reloadID: reloadID,
                sameStreamLayout: true
            )
        } catch {
            // 被更新请求取代时保留 `.replaced` 交给它收尾；否则已经没有可恢复的来源，不再重试。
            if !Task.isCancelled, reloadID.map({ $0 == qualityReloadID }) ?? true {
                qualityReloadEngineEffect = .none
            }
            VanmoLogger.player.error("[PlayerVM] videoQuality restore failed: \(error.localizedDescription)")
        }
    }

    /// 最新的清晰度或 seek 重开请求没有打开新地址就结束时，被它取代的旧 reload 留下的冻结时钟、
    /// 遮罩和暂停或换掉的引擎没人收尾；按旧 reload 做到哪一步来恢复当前地址。
    private func recoverAbandonedQualityReload(generation: UInt64, reloadID: UInt64) async {
        guard generation == mediaGeneration, reloadID == qualityReloadID, !Task.isCancelled else { return }
        let effect = qualityReloadEngineEffect
        // 只剩成功 reload 等首帧的遮罩时交给帧回调清除。
        guard effect != .none || qualityClockFrozenAt != nil else { return }
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=videoQualityRecover effect=\(String(describing: effect), privacy: .public)")
#endif
        clearQualityHold()
        switch effect {
        case .none:
            break
        case .paused:
            engine.play()
        case .replaced:
            guard engine.state != .playing, let activePlaybackURL else { return }
            qualityClockMode = playbackTimeOrigin > 0.5 ? .pending : .direct
            await restorePlayback(
                activePlaybackURL,
                origin: playbackTimeOrigin,
                generation: generation,
                reloadID: reloadID
            )
        }
    }

    /// A reopened source has a new engine item, so its embedded and engine-rendered tracks start unselected.
    /// Track indices only carry over when `sameStreamLayout` is true (a seek reopen of the same rendition).
    private func reattachTracksAfterReload(
        generation: UInt64,
        reloadID: UInt64?,
        sameStreamLayout: Bool
    ) async {
        let reloadEngine = engine
        func isCurrent() -> Bool {
            generation == mediaGeneration
                && !Task.isCancelled
                && reloadEngine === engine
                && (reloadID.map { $0 == qualityReloadID } ?? true)
        }
        let audio = await reloadEngine.availableAudioTracks()
        let embedded = await reloadEngine.availableSubtitleTracks()
        guard isCurrent() else { return }
        let previousAudio = config.selectedAudioTrack
        let previousEmbedded = config.selectedSubtitleTrack.flatMap {
            $0 < Self.externalSubtitleIDOffset ? $0 : nil
        }
        audioTracks = audio
        subtitleTracks = embedded + externalSubtitleTracks
        config.selectedAudioTrack = 0
        if previousEmbedded != nil { config.selectedSubtitleTrack = nil }
#if DEBUG
        let engineName = engine is KSPlayerEngine ? "ks" : "av"
        let externalCount = externalSubtitleTracks.count
        VanmoLogger.player.info("[Debug][Player] event=videoQualityTracks engine=\(engineName, privacy: .public) embedded=\(embedded.count, privacy: .public) external=\(externalCount, privacy: .public) sameLayout=\(sameStreamLayout, privacy: .public)")
#endif
        if sameStreamLayout {
            // 0 is the config default, not necessarily the item's default audio, so it is not reapplied.
            if previousAudio != 0, audio.contains(where: { $0.id == previousAudio }) {
                config.selectedAudioTrack = previousAudio
                await reloadEngine.selectAudioTrack(index: previousAudio)
                guard isCurrent() else { return }
            }
            if let previousEmbedded, embedded.contains(where: { $0.id == previousEmbedded }) {
                config.selectedSubtitleTrack = previousEmbedded
                await reloadEngine.selectSubtitleTrack(index: previousEmbedded)
            }
            return
        }
        // The external SRT overlay is drawn by the view model, so it survives the engine change.
        guard activeExternalSubtitleID == nil else { return }
        await applyPreferredSubtitleIfNeeded(generation: generation)
    }

    private func beginQualityClock(origin: TimeInterval) {
        playbackTimeOrigin = origin
        qualityClockMode = origin > 0.5 ? .pending : .direct
        qualityClockCorrectUntil = 0
    }

    private func armQualityClockCorrection() {
        guard qualityClockMode == .pending || qualityClockMode == .relative else { return }
        qualityClockCorrectUntil = CFAbsoluteTimeGetCurrent() + 12
    }

    private func reconcileQualityClock(engineTime: TimeInterval) {
        guard qualityClockMode == .pending || qualityClockMode == .relative else { return }
        guard engineTime >= 0.25 else { return }
        let origin = playbackTimeOrigin
        guard origin > 0.5 else {
            qualityClockMode = .direct
            return
        }
        let looksAbsolute = abs(engineTime - origin) < 15
        if qualityClockMode == .pending {
            if looksAbsolute {
                adoptAbsoluteQualityClock(engineTime: engineTime, origin: origin)
            } else {
                qualityClockMode = .relative
#if DEBUG
                VanmoLogger.player.info("[Debug][Player] event=videoQualityClock mode=relative engineTime=\(engineTime, privacy: .public) origin=\(origin, privacy: .public) displayed=\(engineTime + origin, privacy: .public)")
#endif
            }
            return
        }
        if looksAbsolute, CFAbsoluteTimeGetCurrent() < qualityClockCorrectUntil {
            adoptAbsoluteQualityClock(engineTime: engineTime, origin: origin)
        }
    }

    private func adoptAbsoluteQualityClock(engineTime: TimeInterval, origin: TimeInterval) {
        playbackTimeOrigin = 0
        qualityClockMode = .absolute
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=videoQualityClock mode=absolute engineTime=\(engineTime, privacy: .public) droppedOrigin=\(origin, privacy: .public) displayed=\(engineTime, privacy: .public)")
#endif
    }

    private func openEngine(url: URL, startPosition: CMTime?, mediaTime: TimeInterval) async throws {
        let detachProxy = prefetchToken != nil && url != prefetchProxyURL
        if detachProxy {
            engine.stop()
        }
        if Self.isTranscodePlaylist(url) {
            await HlsTranscodePrimer.prime(playlistURL: url, startTime: mediaTime)
        }
        try Task.checkCancellation()
        if detachProxy {
            try await unregisterPrefetchIfNeeded()
        }
        let loadURL = try await engineLoadURL(for: url)
        if !Self.isTranscodePlaylist(url) {
            await HlsTranscodePrimer.prime(playlistURL: loadURL, startTime: mediaTime)
            try Task.checkCancellation()
        }
        useEngine(for: loadURL)
        let headers = PrefetchConfig.isProxyURL(loadURL) ? [:] : previewLaneHeaders
        if let avEngine = engine as? AVPlayerEngine {
            try await avEngine.replacePlaybackItem(url: loadURL, startPosition: startPosition)
        } else {
            try await loadEngine(url: loadURL, startPosition: startPosition, headers: headers)
        }
        if !PrefetchConfig.isProxyURL(loadURL) {
            try await unregisterPrefetchIfNeeded()
        }
    }

    /// 清晰度切换和转码回退再决定一次预取。播放列表直连，并在打开成功后释放旧的文件会话。
    private func engineLoadURL(for url: URL) async throws -> URL {
        if PrefetchConfig.isProxyURL(url) { return url }
        guard shouldProxyPlayback(url) else { return url }
        return try await registerPrefetchReplacingCurrent(url)
    }

    private func shouldProxyPlayback(_ url: URL) -> Bool {
        if url.isFileURL || Self.shouldBypassPrefetch(for: url) || usesOfficialDownloadLink() {
            return false
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "ftp", "sftp":
            return true
        default:
            return false
        }
    }

    private func registerPrefetchReplacingCurrent(_ url: URL) async throws -> URL {
        let generation = mediaGeneration
        try await unregisterPrefetchIfNeeded()
        guard generation == mediaGeneration else { throw CancellationError() }
        guard let registration = await PrefetchProxy.shared.register(
            originalURL: url,
            headerProvider: previewLaneHeaderProvider
        ) else {
            return url
        }
        guard generation == mediaGeneration else {
            await PrefetchProxy.shared.unregister(token: registration.token)
            throw CancellationError()
        }
        prefetchToken = registration.token
        prefetchProxyURL = registration.url
        VanmoLogger.player.info("[PlayerVM] using prefetch proxy for remote URL")
        Self.logMediaServerPrefetchRegistration(url)
        return registration.url
    }

#if DEBUG
    private static func logMediaServerPrefetchRegistration(_ url: URL) {
        let path = url.path.lowercased()
        guard PrefetchConfig.isMediaServerStreamURL(url) || path.contains("/library/parts") else { return }
        VanmoLogger.prefetch.info(
            "[Debug][Prefetch] event=register source=http path=\(url.safePlaybackLogDescription, privacy: .public)"
        )
    }
#else
    private static func logMediaServerPrefetchRegistration(_: URL) {}
#endif

#if DEBUG
    private static func logQualityResponse(_ url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 120 { break }
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? -1
            let type = http?.value(forHTTPHeaderField: "Content-Type") ?? "none"
            let prefix = String(data: data.prefix(80), encoding: .utf8) ?? ""
            let playlist = prefix.contains("#EXTM3U")
            let lowered = prefix.lowercased()
            let snippet = (lowered.contains("api_key") || lowered.contains("token"))
                ? "redacted"
                : prefix.replacingOccurrences(of: "\n", with: " ")
            VanmoLogger.player.info("[Debug][Player] event=videoQualityProbe status=\(status, privacy: .public) type=\(type, privacy: .public) playlist=\(playlist, privacy: .public) bytes=\(data.count, privacy: .public) body=\(snippet, privacy: .public)")
        } catch {
            let nsError = error as NSError
            VanmoLogger.player.info("[Debug][Player] event=videoQualityProbe status=transport domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }
    }
#endif

    func updateScrubTarget(_ fraction: Double?) {
        guard let fraction, duration > 0 else {
            seekPreviewActive = false
            seekPreviewRequestedTime = nil
            seekPreviewImage = nil
            scrubTargetTime = nil
            return
        }
        let time = max(0, min(duration, fraction * duration))
        scrubTargetTime = time
        seekTime = time
        seekPreviewForward = time >= currentTime
        seekPreviewActive = true
        requestSeekPreview(at: time)
    }

    func skipIntro() {
        guard let introWindow else { return }
        seek(to: introWindow.end)
        showControlsBriefly()
    }

    func markIntroEnd() {
        let end = max(currentTime, 1)
        let key = IntroSkipStore.mediaKey(for: item)
        IntroSkipStore.save(manualEnd: end, for: key)
        refreshIntroWindow(serverWindow: introWindow)
        showNotice(title: L10n.tr("已标记片头结束"), message: end.formattedDuration)
    }

    func toggleKSPictureInPicture() {
        guard let ksEngine = engine as? KSPlayerEngine else { return }
        if !ksEngine.isPictureInPictureSupported {
            showNotice(
                title: L10n.tr("画中画不可用"),
                message: "当前 KSPlayer 路径暂无法启动画中画。可尝试 MP4/MOV/HLS 等 AVFoundation 原生格式。"
            )
            return
        }
        if !ksEngine.togglePictureInPicture() {
            showNotice(
                title: L10n.tr("画中画暂不可用"),
                message: "系统尚未允许当前视频进入画中画，请稍后重试或确认设备支持画中画。"
            )
        }
    }

    func selectAudioTrack(_ index: Int) {
        config.selectedAudioTrack = index
        Task { await engine.selectAudioTrack(index: index) }
    }

    func selectSubtitleTrack(_ index: Int?) {
        VanmoLogger.player.info("[PlayerVM] selectSubtitleTrack: index=\(String(describing: index))")
        config.selectedSubtitleTrack = index
        persistSubtitlePreference(for: index)
        Task { await applySubtitleSelection(index) }
    }

    func searchOnlineSubtitles() {
        guard !isSearchingOnlineSubtitles else { return }
        isSearchingOnlineSubtitles = true
        onlineSubtitleStatusMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await OnlineSubtitleService.shared.search(for: self.item)
                await MainActor.run {
                    self.onlineSubtitleResults = results
                    self.onlineSubtitleStatusMessage = results.isEmpty ? L10n.tr("未找到匹配的在线字幕") : nil
                    self.isSearchingOnlineSubtitles = false
                }
            } catch {
                await MainActor.run {
                    self.onlineSubtitleResults = []
                    self.onlineSubtitleStatusMessage = error.localizedDescription
                    self.isSearchingOnlineSubtitles = false
                }
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
                await MainActor.run {
                    self.externalSubtitleTracks.append(track)
                    self.subtitleTracks.append(track)
                    self.isDownloadingOnlineSubtitle = false
                    self.downloadingOnlineSubtitleID = nil
                    self.onlineSubtitleStatusMessage = "已加载在线字幕：\(result.title)"
                    self.selectSubtitleTrack(trackID)
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingOnlineSubtitle = false
                    self.downloadingOnlineSubtitleID = nil
                    self.onlineSubtitleStatusMessage = error.localizedDescription
                    self.showNotice(title: L10n.tr("在线字幕不可用"), message: error.localizedDescription)
                }
            }
        }
    }

    /// 设置外挂字幕的时间偏移（正值表示字幕提前显示）。内嵌字幕由引擎渲染，暂不支持偏移。
    func setSubtitleDelay(_ delay: TimeInterval) {
        let clamped = min(10, max(-10, delay))
        config.subtitleDelay = clamped
        Task {
            await externalSubtitleManager.setDelay(clamped)
            if activeRichSubtitleID != nil, let ksEngine = engine as? KSPlayerEngine {
                ksEngine.setExternalRichSubtitleDelay(clamped)
            }
            updateExternalSubtitle(at: currentTime)
        }
    }

    private func applySubtitleSelection(
        _ index: Int?,
        generation: UInt64? = nil
    ) async {
        guard isCurrentMediaGeneration(generation) else { return }
        guard let index else {
            activeExternalSubtitleID = nil
            activeRichSubtitleID = nil
            currentSubtitleContent = nil
            await externalSubtitleManager.clear()
            guard isCurrentMediaGeneration(generation) else { return }
            (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
            await engine.selectSubtitleTrack(index: nil)
            return
        }

        guard let track = subtitleTracks.first(where: { $0.id == index }) else { return }
        if let fileURL = track.fileURL, !track.isEmbedded {
            do {
                await engine.selectSubtitleTrack(index: nil)
                guard isCurrentMediaGeneration(generation) else { return }
                if SubtitleFormat.detect(from: fileURL).isRichTextFormat {
                    guard let ksEngine = engine as? KSPlayerEngine else {
                        throw SubtitleError.assRenderingUnavailable
                    }
                    await externalSubtitleManager.clear()
                    guard isCurrentMediaGeneration(generation) else { return }
                    try await ksEngine.selectExternalRichSubtitle(url: fileURL, delay: config.subtitleDelay)
                    guard isCurrentMediaGeneration(generation) else { return }
                    activeExternalSubtitleID = nil
                    activeRichSubtitleID = track.id
                    currentSubtitleContent = nil
                } else {
                    (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
                    try await externalSubtitleManager.load(from: fileURL)
                    guard isCurrentMediaGeneration(generation) else { return }
                    await externalSubtitleManager.setDelay(config.subtitleDelay)
                    guard isCurrentMediaGeneration(generation) else { return }
                    activeExternalSubtitleID = track.id
                    activeRichSubtitleID = nil
                    updateExternalSubtitle(at: currentTime)
                }
            } catch {
                guard isCurrentMediaGeneration(generation) else { return }
                VanmoLogger.subtitle.error("[PlayerVM] Failed to load external subtitle: \(error.localizedDescription)")
                activeExternalSubtitleID = nil
                activeRichSubtitleID = nil
                currentSubtitleContent = nil
                showNotice(title: L10n.tr("字幕不可用"), message: error.localizedDescription)
            }
        } else {
            activeExternalSubtitleID = nil
            activeRichSubtitleID = nil
            currentSubtitleContent = nil
            await externalSubtitleManager.clear()
            guard isCurrentMediaGeneration(generation) else { return }
            (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
            await engine.selectSubtitleTrack(index: index)
        }
    }

    private func isCurrentMediaGeneration(_ generation: UInt64?) -> Bool {
        generation == nil || generation == mediaGeneration
    }

    private func nextExternalSubtitleID() -> Int {
        let maxExternalID = subtitleTracks
            .map(\.id)
            .filter { $0 >= Self.externalSubtitleIDOffset }
            .max()
        return (maxExternalID ?? (Self.externalSubtitleIDOffset - 1)) + 1
    }

    private func applyPreferredSubtitleIfNeeded(generation: UInt64? = nil) async {
        guard isCurrentMediaGeneration(generation) else { return }
        guard !subtitleTracks.isEmpty else {
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: no subtitle tracks available")
            return
        }

        switch resolveSavedSubtitleSelection() {
        case .off:
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: restoring saved selection (off)")
            config.selectedSubtitleTrack = nil
            await applySubtitleSelection(nil, generation: generation)
            return
        case .track(let savedIndex):
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: restoring saved track index=\(savedIndex)")
            config.selectedSubtitleTrack = savedIndex
            await applySubtitleSelection(savedIndex, generation: generation)
            return
        case .none:
            break
        }

        if !subtitleAutoLoad {
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: auto-load disabled")
            config.selectedSubtitleTrack = nil
            guard isCurrentMediaGeneration(generation) else { return }
            await engine.selectSubtitleTrack(index: nil)
            return
        }

        guard let preferredIndex = preferredSubtitleIndex(
            for: subtitlePreferredLanguage,
            tracks: subtitleTracks
        ) else {
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: no matching track for '\(self.subtitlePreferredLanguage)'")
            return
        }

        VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: auto-selecting index=\(preferredIndex) for '\(self.subtitlePreferredLanguage)'")
        config.selectedSubtitleTrack = preferredIndex
        await applySubtitleSelection(preferredIndex, generation: generation)
    }

    private enum SavedSubtitleSelection {
        case off
        case track(Int)
    }

    /// 将本条目持久化的字幕偏好解析为当前轨道列表中的有效选择。
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

    /// 记录用户对本条目的字幕轨选择，以便下次播放恢复。语言自动匹配不写入。
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
        try? item.modelContext?.save()
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
            return ["zh", "zho", "chi", "chs", "cht", "cn", "chinese", L10n.tr("中文"), "简体", "繁体"]
        case "en":
            return ["en", "eng", "english", L10n.tr("英文")]
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
            VanmoLogger.subtitle.error("[PlayerVM] online subtitle cache discovery failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func onlineSubtitleTitle(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-", maxSplits: 3).map(String.init)
        guard parts.count == 4 else {
            return stem
        }
        let provider = parts[1]
        let title = parts[3].replacingOccurrences(of: "-", with: " ")
        return "在线 · \(provider) · \(title)"
    }

    /// 远程视频的同目录外挂字幕发现：列出视频所在目录，筛出同名前缀的 .srt/.vtt/.ass/.ssa，
    /// 下载到本地缓存后以本地外挂轨形式暴露（复用现有选轨/加载路径）。
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
            guard !Task.isCancelled else {
                await service.disconnect()
                return []
            }

            let siblings = try await service.listDirectory(path: parentPath)
            guard !Task.isCancelled else {
                await service.disconnect()
                return []
            }
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
                guard !Task.isCancelled else {
                    await service.disconnect()
                    return []
                }
                let localURL = cacheDir.appendingPathComponent("\(item.id.uuidString)-\(file.name)")
                do {
                    try await service.download(file: file, to: localURL, progress: { _ in })
                } catch {
                    VanmoLogger.subtitle.error("[PlayerVM] remote subtitle download failed: \(file.name) - \(error.localizedDescription)")
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
            VanmoLogger.subtitle.info("[PlayerVM] discovered \(tracks.count) remote external subtitle(s)")
            return tracks
        } catch {
            VanmoLogger.subtitle.error("[PlayerVM] remote subtitle discovery failed: \(error.localizedDescription)")
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

    func playEpisode(_ episode: PlayerEpisode) async {
        guard episode.id != currentEpisodeID else {
            showEpisodeSelector = false
            return
        }

        saveProgress()
        let stopPosition = currentTime
        let previousSession = playbackSession
        playbackSession = nil
        await previousSession?.stopped(position: stopPosition)
        engine.stop()
        item = episode.mediaItem ?? makeMediaItem(from: episode)
        currentEpisodeID = episode.id
        didReportWatchedToServer = false
        showEpisodeSelector = false
        #if DEBUG
        VanmoLogger.player.info("[Debug][PlayerVM] event=episodeSwitch from=\(stopPosition, privacy: .public)s")
        #endif

        do {
            try await loadAndPlayCurrentItem()
            showControlsBriefly()
        } catch is CancellationError {
            return
        } catch {
            VanmoLogger.player.error("[PlayerVM] episode switch failed: \(error.localizedDescription)")
            playbackState = .error(error.localizedDescription)
        }
    }

    private func loadEpisodesIfNeeded(modelContext: ModelContext?) async {
        guard isEpisodeSelectableItem else {
            #if DEBUG
            VanmoLogger.player.info("[Debug][PlayerVM] event=episodesSkipped mediaType=\(self.item.mediaType.rawValue, privacy: .public)")
            #endif
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
        #if DEBUG
        let episodeCount = episodes.count
        let seasonCount = episodeGroups.count
        VanmoLogger.player.info("[Debug][PlayerVM] event=episodesLoaded count=\(episodeCount, privacy: .public) seasons=\(seasonCount, privacy: .public)")
        #endif
    }

    private var isEpisodeSelectableItem: Bool {
        item.mediaType == .tvEpisode || item.mediaType == .tvShow || item.showTitle != nil || item.seriesId != nil
    }

    private func loadLocalEpisodes(modelContext: ModelContext?) -> [PlayerEpisode] {
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
                    guard candidate.mediaType == .tvEpisode,
                          candidate.sourceConnectionId == item.sourceConnectionId,
                          normalizedShowTitle(for: candidate) == showTitle,
                          candidate.seasonNumber != nil,
                          candidate.episodeNumber != nil else {
                        return false
                    }
                    return true
                }
                .sorted(by: episodeSortPredicate)
                .map(PlayerEpisode.init(mediaItem:))
        } catch {
            VanmoLogger.player.error("[PlayerVM] local episode fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func loadRemoteEpisodes() async -> [PlayerEpisode] {
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
            return episodes.map { PlayerEpisode(episodeInfo: $0, showTitle: item.showTitle ?? item.title) }
        } catch {
            VanmoLogger.player.error("[PlayerVM] remote episode fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private var isPlexEpisodeSource: Bool {
        item.fileURL.query?.contains("X-Plex-Token") == true || item.fileURL.host == "plex-series"
    }

    private func groupedEpisodes(from episodes: [PlayerEpisode]) -> [PlayerEpisodeSeason] {
        Dictionary(grouping: episodes, by: \.seasonNumber)
            .map { season, episodes in
                PlayerEpisodeSeason(
                    seasonNumber: season,
                    episodes: episodes.sorted(by: episodeSortPredicate)
                )
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private func makeMediaItem(from episode: PlayerEpisode) -> MediaItem {
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

    private func matchesCurrentItem(_ episode: PlayerEpisode) -> Bool {
        if let mediaItem = episode.mediaItem, mediaItem.id == item.id {
            return true
        }

        return episode.fileURL == item.fileURL &&
            episode.seasonNumber == item.seasonNumber &&
            episode.episodeNumber == item.episodeNumber
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
        if lhsSeason != rhsSeason {
            return lhsSeason < rhsSeason
        }

        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode {
            return lhsEpisode < rhsEpisode
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func episodeSortPredicate(_ lhs: PlayerEpisode, _ rhs: PlayerEpisode) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber {
            return lhs.seasonNumber < rhs.seasonNumber
        }
        if lhs.episodeNumber != rhs.episodeNumber {
            return lhs.episodeNumber < rhs.episodeNumber
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    // MARK: - Chapters

    func seekToChapter(_ chapter: Chapter) {
        seek(to: chapter.startTime.seconds)
        showControlsBriefly()
    }

    private func loadChapters() {
        if !discChapters.isEmpty {
            chapters = discChapters
        } else if let ksEngine = engine as? KSPlayerEngine {
            chapters = ksEngine.availableChapters
        }
        refreshIntroWindow(serverWindow: nil)
        loadIntroMarkersIfNeeded()
    }

    private func refreshIntroWindow(serverWindow: IntroSkipWindow?) {
        let key = IntroSkipStore.mediaKey(for: item)
        introWindow = IntroSkipResolver.window(
            chapters: chapters,
            serverWindow: serverWindow,
            manualEnd: IntroSkipStore.manualEnd(for: key)
        )
    }

    private func loadIntroMarkersIfNeeded() {
        introMarkerTask?.cancel()
        guard let serverId = item.serverId else { return }
        let generation = mediaGeneration
        introMarkerTask = Task { [weak self] in
            guard let self else { return }
            let window = await self.fetchServerIntroWindow(serverId: serverId)
            guard !Task.isCancelled, generation == mediaGeneration else { return }
            refreshIntroWindow(serverWindow: window)
        }
    }

    private func fetchServerIntroWindow(serverId: String) async -> IntroSkipWindow? {
        guard let snapshot = try? MediaServerConnectionResolver.snapshot(for: item, in: modelContext) else {
            return nil
        }
        do {
            switch snapshot.type {
            case .emby, .jellyfin:
                return try await EmbyIntroMarkerFetcher.fetchWindow(itemId: serverId, connection: snapshot)
            case .plex:
                return try await PlexIntroMarkerFetcher.fetchWindow(ratingKey: serverId, connection: snapshot)
            default:
                return nil
            }
        } catch {
            VanmoLogger.player.info("[PlayerVM] intro marker fetch failed")
            return nil
        }
    }

    private func resolveDiscPlaybackURLIfNeeded(_ url: URL) async -> URL {
        guard MediaFormatProbe.isDiscImage(url) else { return url }
        guard url.isFileURL else {
            showNotice(
                title: L10n.tr("远程原盘将直接尝试播放"),
                message: "远程 BDMV/ISO 的 playlist 随机读取尚受限，当前会先交给 KSPlayer 直接尝试。"
            )
            return url
        }
        guard url.pathExtension.lowercased() != "iso" else {
            showNotice(
                title: L10n.tr("ISO playlist 解析暂不可用"),
                message: "当前未引入 UDF/libbluray，ISO 会先交给 KSPlayer 直接尝试播放；未加密 BDMV 目录和 .mpls 已支持 playlist 解析。"
            )
            return url
        }

        do {
            let parser = BDMVPlaylistParser()
            let structure = try await parser.parseStructure(at: url)
            guard let playlist = structure.mainPlaylist else { return url }
            discChapters = Self.chapters(from: playlist)
            if let playbackURL = Self.playbackURL(for: playlist, originalURL: url) {
                VanmoLogger.player.info("[PlayerVM] resolved BDMV playlist \(playlist.id) to \(playbackURL.absoluteString)")
                return playbackURL
            }
            showNotice(
                title: L10n.tr("原盘 playlist 已解析"),
                message: "已识别 \(playlist.id)，但播放片段路径无法定位，将回退为直接播放原始路径。"
            )
        } catch {
            VanmoLogger.player.error("[PlayerVM] BDMV playlist parse failed: \(error.localizedDescription)")
            showNotice(
                title: L10n.tr("原盘解析失败"),
                message: "\(error.localizedDescription)。将回退为 KSPlayer 直接尝试播放。"
            )
        }
        return url
    }

    private static func shouldBypassPrefetch(for url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "concat", "smb":
            return true
        default:
            return PrefetchConfig.isMediaServerPlaylist(url)
        }
    }

    private static func playbackURL(for playlist: DiscPlaylist, originalURL: URL) -> URL? {
        guard let root = bdmvRoot(for: originalURL), !playlist.segments.isEmpty else { return nil }
        if playlist.segments.count == 1 {
            return root
                .deletingLastPathComponent()
                .appendingPathComponent(playlist.segments[0].relativePath)
        }

        return makeLocalDiscPlaylistFile(for: playlist, bdmvParent: root.deletingLastPathComponent())
    }

    private static func makeLocalDiscPlaylistFile(for playlist: DiscPlaylist, bdmvParent: URL) -> URL? {
        guard let directory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DiscPlaylists", isDirectory: true) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let targetDuration = max(1, Int(ceil(playlist.segments.map(\.duration).max() ?? 1)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:0",
        ]

        for segment in playlist.segments {
            let segmentURL = bdmvParent.appendingPathComponent(segment.relativePath)
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append(segmentURL.absoluteString)
        }
        lines.append("#EXT-X-ENDLIST")

        let fileName = "\(playlist.id.replacingOccurrences(of: ".", with: "-"))-\(UUID().uuidString).m3u8"
        let playlistURL = directory.appendingPathComponent(fileName)
        do {
            try lines.joined(separator: "\n").write(to: playlistURL, atomically: true, encoding: .utf8)
            return playlistURL
        } catch {
            VanmoLogger.player.error("[PlayerVM] failed to write BDMV helper playlist: \(error.localizedDescription)")
            return nil
        }
    }

    private static func chapters(from playlist: DiscPlaylist) -> [Chapter] {
        let sorted = playlist.chapters.sorted { $0.startTime < $1.startTime }
        guard !sorted.isEmpty else { return [] }
        return sorted.enumerated().map { offset, chapter in
            let end: TimeInterval
            if offset + 1 < sorted.count {
                end = sorted[offset + 1].startTime
            } else {
                end = playlist.duration
            }
            return Chapter(
                id: chapter.index,
                title: "章节 \(offset + 1)",
                startTime: CMTime(seconds: chapter.startTime, preferredTimescale: 600),
                endTime: CMTime(seconds: max(end, chapter.startTime), preferredTimescale: 600)
            )
        }
    }

    private static func bdmvRoot(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        guard let index = components.lastIndex(where: { $0.uppercased() == "BDMV" }) else {
            return standardized.lastPathComponent.uppercased() == "BDMV" ? standardized : nil
        }
        let rootPath = NSString.path(withComponents: Array(components[0...index]))
        return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    /// 首播时读取本地视频真实 HDR 元数据并持久化，供详情/收藏角标使用。
    /// 仅探测本地文件，避免对远程流发起额外网络解析。
    private func updateDynamicRangeIfNeeded(for url: URL) async {
        guard item.dynamicRange == nil, url.isFileURL else { return }
        guard let range = await PlayerCapabilityProbe.detectDynamicRange(for: url) else { return }
        item.dynamicRange = range.rawValue
        try? item.modelContext?.save()
        VanmoLogger.player.info("[PlayerVM] detected dynamic range: \(range.rawValue)")
    }

    // MARK: - Controls Visibility

    func toggleControls() {
        guard !isSeeking else { return }
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
            guard !Task.isCancelled, playbackState == .playing, !isSeeking else { return }
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
        setVolume(config.volume + delta)
        volumeOverlay = config.volume
        dismissOverlay(\.volumeOverlay)
    }

    /// 横向拖动调整进度。`delta` 为相对拖动起点的累计偏移秒数。
    func handleSeekGesture(_ delta: TimeInterval) {
        guard duration > 0 else { return }
        if seekBaseTime == nil {
            seekBaseTime = currentTime
            seekPreviewActive = true
        }
        let base = seekBaseTime ?? currentTime
        let target = max(0, min(base + delta, duration))
        seekTime = target
        seekPreviewForward = target >= base
        requestSeekPreview(at: target)
    }

    func commitSeekGesture() {
        guard seekPreviewActive else { return }
        seek(to: seekTime)
        seekBaseTime = nil
        seekPreviewActive = false
        seekPreviewRequestedTime = nil
        seekPreviewImage = nil
        showControlsBriefly()
    }

    /// KSPlayer 拖动预览走 `scrubPreviewLane`，从不读引擎的预览缓存。AVPlayer 播 HLS 转码时也走它：
    /// `AVAssetImageGenerator` 取不到 HLS 的帧，预览路读的是原始源，与播放引擎无关。
    private var usesScrubPreviewLane: Bool {
        guard let previewLaneURL else { return false }
        if engine is KSPlayerEngine { return true }
        // 源本身就是播放列表时，第二路 KSPlayer 打开它会在服务端再起一路转码。
        guard !Self.isTranscodePlaylist(previewLaneURL) else { return false }
        return activePlaybackURL.map(Self.isTranscodePlaylist) ?? false
    }

    private func requestSeekPreview(at time: TimeInterval) {
        if usesScrubPreviewLane, let originalURL = previewLaneURL {
            scrubPreviewLane.onFrame = { [weak self] image in
                self?.seekPreviewImage = image
            }
            scrubPreviewLane.request(
                at: time,
                originalURL: originalURL,
                headers: previewLaneHeaders,
                headerProvider: previewLaneHeaderProvider,
                sharedProxyURL: prefetchProxyURL
            )
            return
        }

        seekPreviewRequestedTime = time
        if let cached = (engine as? SeekPreviewProviding)?.cachedPreview(at: time) {
            seekPreviewImage = cached
        }
        if seekPreviewTask != nil {
            (engine as? SeekPreviewProviding)?.cancelPreviewGeneration()
            return
        }
        seekPreviewTask = Task { [weak self] in
            await self?.runSeekPreviewLoop()
        }
    }

    private func startSeekPreviewWarmupIfNeeded() {
        guard duration > 1, abs(duration - previewWarmDuration) > 0.5 else { return }
        guard engine is SeekPreviewProviding else { return }
        if usesScrubPreviewLane {
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=previewWarmSkip reason=previewLane")
#endif
            previewWarmDuration = duration
            return
        }
        previewWarmDuration = duration
        previewWarmTask?.cancel()
        let warmDuration = duration
        previewWarmTask = Task { [weak self] in
            var time: TimeInterval = 0
            var failures = 0
            while time < warmDuration, !Task.isCancelled {
                guard let self else { return }
                if self.seekPreviewRequestedTime != nil {
                    try? await Task.sleep(for: .milliseconds(200))
                    continue
                }
                let provider = self.engine as? SeekPreviewProviding
                if provider?.hasExactCachedPreview(at: time) != true {
                    _ = await provider?.previewFrame(at: time, maxPixelSize: 160)
                    if self.seekPreviewRequestedTime != nil {
                        continue
                    }
                    if provider?.hasExactCachedPreview(at: time) == true {
                        failures = 0
                    } else {
                        failures += 1
                        if failures >= 3 { return }
                    }
                }
                time += 6
            }
        }
    }

    private func runSeekPreviewLoop() async {
        defer { seekPreviewTask = nil }
        while let time = seekPreviewRequestedTime {
            seekPreviewRequestedTime = nil
            let image = await (engine as? SeekPreviewProviding)?
                .previewFrame(at: time, maxPixelSize: 240)
            guard !Task.isCancelled else { return }
            if let image {
                seekPreviewImage = image
            }
        }
    }

    private func configureSeekPreviewSource(originalURL: URL, headers: [String: String]) {
        guard let ksEngine = engine as? KSPlayerEngine else { return }
        let previewURL: URL?
        if LibavformatOpenGate.needsExclusiveOpen(originalURL) {
            previewURL = nil
        } else {
            let scheme = originalURL.scheme?.lowercased() ?? ""
            previewURL = originalURL.isFileURL || scheme == "http" || scheme == "https"
                ? originalURL
                : nil
        }
        ksEngine.configureSeekPreview(sourceURL: previewURL, headers: headers)
    }

    /// 整体长按时将播放速度提升至最高倍速，松手恢复。
    func handleRateBoost(isActive: Bool) {
        if isActive {
            guard !isRateBoosting else { return }
            isRateBoosting = true
            engine.playbackRate = PlayerConfig.clampedRate(PlayerConfig.maximumRate)
            #if os(iOS)
            rateBoostHaptic.prepare()
            rateBoostHaptic.impactOccurred()
            #else
            PlatformHaptics.impactMedium()
            #endif
        } else {
            guard isRateBoosting else { return }
            isRateBoosting = false
            engine.playbackRate = config.playbackRate
        }
    }

    private func updateExternalSubtitle(at time: TimeInterval) {
        guard let subtitleID = activeExternalSubtitleID else { return }
        let generation = mediaGeneration
        externalSubtitleCueTask?.cancel()
        externalSubtitleCueTask = Task { [weak self] in
            guard let self else { return }
            let cue = await externalSubtitleManager.cue(at: time)
            guard !Task.isCancelled,
                  mediaGeneration == generation,
                  activeExternalSubtitleID == subtitleID else { return }
            let content = cue.map { SubtitleContent(text: $0.text) }
            if content != currentSubtitleContent {
                currentSubtitleContent = content
            }
        }
    }

    // MARK: - Live Stream

    /// 当前条目是否为直播流（IPTV）。直播无固定时长/进度，UI 据此隐藏进度条与续播。
    var isLiveStream: Bool { item.isLiveStream }

    private static let maxLiveRetries = 3

    /// 直播流断流后自动重连：错误时延迟重试，成功播放后重置计数。
    private func handleLiveStreamStateIfNeeded(_ state: PlaybackState) {
        guard item.isLiveStream else { return }
        switch state {
        case .playing:
            liveRetryCount = 0
        case .error:
            guard liveRetryCount < Self.maxLiveRetries else {
                VanmoLogger.player.error("[PlayerVM] live stream retry exhausted (\(self.liveRetryCount))")
                return
            }
            liveRetryCount += 1
            let attempt = liveRetryCount
            VanmoLogger.player.info("[PlayerVM] live stream error, retry \(attempt)/\(Self.maxLiveRetries)")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.item.isLiveStream else { return }
                do {
                    try await self.loadAndPlayCurrentItem()
                } catch is CancellationError {
                    return
                } catch {
                    self.playbackState = .error(error.localizedDescription)
                }
            }
        default:
            break
        }
    }

    // MARK: - Progress

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private func saveProgress() {
        guard !item.isLiveStream else { return }
        item.lastPlaybackPosition = currentTime
        item.lastPlayedAt = Date()
        if currentTime / max(duration, 1) > 0.9 {
            item.isWatched = true
            reportWatchedToServerIfNeeded()
        }
        if item.isProgressCloudSynced, let context = item.modelContext {
            CloudSyncCoordinator.shared.markMediaProgressChanged(item, in: context)
            try? context.save()
            CloudSyncCoordinator.shared.requestSync(reason: "playback-progress", context: context)
        } else {
            try? item.modelContext?.save()
        }
    }

    private func preparePlaybackSession() {
        let snapshot = try? MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
        playbackSession = EmbyPlaybackSession(item: item, connection: snapshot)
        didReportWatchedToServer = false
    }

    private func reportPlaybackTimeUpdate(at time: TimeInterval) {
        guard playbackSession?.isEnabled == true else { return }
        let isPaused = playbackState == .paused
        Task {
            await playbackSession?.progress(
                position: time,
                isPaused: isPaused,
                event: .timeUpdate
            )
        }
    }

    private func reportWatchedToServerIfNeeded() {
        guard !didReportWatchedToServer else { return }
        didReportWatchedToServer = true
        let snapshot = try? MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
        let mediaItem = item
        Task {
            do {
                try await EmbyPlayedUpdater.setPlayed(
                    mediaItem,
                    isPlayed: true,
                    connection: snapshot
                )
            } catch {
                VanmoLogger.network.error(
                    "[EmbyPlayback] mark played failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func dismissOverlay<T>(_ keyPath: ReferenceWritableKeyPath<PlayerViewModel, T?>, after: TimeInterval = 1.0) {
        Task {
            try? await Task.sleep(for: .seconds(after))
            withAnimation { self[keyPath: keyPath] = nil }
        }
    }

    private func handleAirPlayRouteChange() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let isAirPlay = outputs.contains { $0.portType == .airPlay }
        guard isAirPlay, !supportsVideoAirPlay, !isLiveStream else { return }
        showNotice(
            title: L10n.tr("当前格式不支持视频投屏"),
            message: L10n.tr("可用系统屏幕镜像")
        )
    }

    private func showNotice(title: String, message: String) {
        notice = PlayerNotice(title: title, message: message)
    }

}

struct PlayerNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct PlayerEpisodeSeason: Identifiable, Equatable {
    let seasonNumber: Int
    let episodes: [PlayerEpisode]

    var id: Int { seasonNumber }
}

struct PlayerEpisode: Identifiable, Equatable {
    let id: String
    let title: String
    let showTitle: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let duration: TimeInterval
    let fileURL: URL
    let serverId: String?
    let mediaItem: MediaItem?

    static func == (lhs: PlayerEpisode, rhs: PlayerEpisode) -> Bool {
        lhs.id == rhs.id
    }

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
        title.isEmpty ? LocalizedFormat.episodeLabel(episodeNumber) : title
    }

    var episodeCode: String {
        LocalizedFormat.episodeCode(season: seasonNumber, episode: episodeNumber)
    }
}
