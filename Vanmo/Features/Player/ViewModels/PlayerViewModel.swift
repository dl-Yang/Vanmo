import SwiftUI
import AVFoundation
import Combine
import SwiftData

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
    @Published private(set) var currentSubtitleContent: SubtitleContent?
    @Published private(set) var episodeGroups: [PlayerEpisodeSeason] = []
    @Published private(set) var currentEpisodeID: String?

    @Published var config = PlayerConfig()
    @Published var subtitleStyle = SubtitleStyle() {
        didSet { SubtitleStylePreferences.save(subtitleStyle) }
    }
    @Published var showSubtitleSettings = false
    @Published var controlsVisible = true
    @Published var isSeeking = false
    @Published var seekTime: TimeInterval = 0
    @Published var showTrackSelector = false
    @Published var showChapterList = false
    @Published var showEpisodeSelector = false
    @Published var selectedEpisodeSeason: Int?
    @Published var brightnessOverlay: Float?
    @Published var volumeOverlay: Float?
    @Published var seekOverlay: TimeInterval?
    @Published var isRateBoosting = false
    @Published var seekPreviewActive = false
    @Published var seekPreviewForward = true
    @Published var notice: PlayerNotice?
    @Published private(set) var onlineSubtitleResults: [OnlineSubtitleResult] = []
    @Published private(set) var isSearchingOnlineSubtitles = false
    @Published private(set) var isDownloadingOnlineSubtitle = false
    @Published private(set) var downloadingOnlineSubtitleID: String?
    @Published private(set) var onlineSubtitleStatusMessage: String?

    let engine: PlayerEngine
    private var item: MediaItem
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var hideControlsTask: Task<Void, Never>?
    private var prefetchToken: String?
    private var liveRetryCount = 0
    private let externalSubtitleManager = SubtitleManager()
    private var activeExternalSubtitleID: Int?
    private var activeRichSubtitleID: Int?
    private var externalSubtitleTracks: [SubtitleTrackInfo] = []
    private var discChapters: [Chapter] = []
    private var seekBaseTime: TimeInterval?
    #if os(iOS)
    private let rateBoostHaptic = UIImpactFeedbackGenerator(style: .medium)
    #endif

    private static let externalSubtitleIDOffset = 10_000

    var canSelectEpisode: Bool {
        !episodeGroups.isEmpty
    }

    var selectedSeasonEpisodes: [PlayerEpisode] {
        let season = selectedEpisodeSeason ?? episodeGroups.first?.seasonNumber
        return episodeGroups.first { $0.seasonNumber == season }?.episodes ?? []
    }

    init(item: MediaItem) {
        self.item = item
        self.subtitleStyle = SubtitleStylePreferences.load()
        VanmoLogger.player.info("[PlayerVM] init, file: \(item.fileURL.lastPathComponent), URL: \(item.fileURL.absoluteString)")
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

    var isPictureInPictureActive: Bool {
        if let ksEngine = engine as? KSPlayerEngine {
            return ksEngine.isPictureInPictureActive
        }
        return false
    }

    var isPictureInPicturePossible: Bool {
        if avPlayer != nil { return true }
        return (engine as? KSPlayerEngine)?.isPictureInPicturePossible == true
    }

    // MARK: - Setup

    private func setupBindings() {
        engine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                VanmoLogger.player.info("[PlayerVM] state changed: \(String(describing: state))")
                self?.playbackState = state
                self?.handleLiveStreamStateIfNeeded(state)
            }
            .store(in: &cancellables)

        engine.currentTimePublisher
            .receive(on: DispatchQueue.main)
            .map { $0.seconds }
            .filter { $0.isFinite && !$0.isNaN }
            .sink { [weak self] time in
                self?.currentTime = time
                self?.updateExternalSubtitle(at: time)
            }
            .store(in: &cancellables)

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

        engine.subtitleContentPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard self?.activeExternalSubtitleID == nil else { return }
                self?.currentSubtitleContent = content
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func onAppear(modelContext: ModelContext? = nil) async {
        self.modelContext = modelContext
        VanmoLogger.player.info("[PlayerVM] onAppear, loading file: \(self.item.fileURL.lastPathComponent)")
        do {
            try await loadAndPlayCurrentItem()
            await loadEpisodesIfNeeded(modelContext: modelContext)
            scheduleHideControls()
        } catch {
            VanmoLogger.player.error("[PlayerVM] load failed: \(error.localizedDescription)")
            playbackState = .error(error.localizedDescription)
        }
    }

    func onDisappear(keepingPlaybackActive: Bool = false) {
        VanmoLogger.player.info("[PlayerVM] onDisappear, saving progress at \(self.currentTime)s")
        saveProgress()
        guard !keepingPlaybackActive else {
            VanmoLogger.player.info("[PlayerVM] keeping playback alive for Picture in Picture")
            return
        }
        engine.stop()
        if let token = prefetchToken {
            prefetchToken = nil
            Task {
                await PrefetchProxy.shared.unregister(token: token)
            }
        }
    }

    private func loadAndPlayCurrentItem() async throws {
        try await unregisterPrefetchIfNeeded()
        resetPlaybackMetadata()

        let originalURL = await resolveCloudDriveStreamURLIfNeeded(item.fileURL)
        let playbackURL = await resolveDiscPlaybackURLIfNeeded(originalURL)
        let loadURL: URL
        if playbackURL.isFileURL || Self.shouldBypassPrefetch(for: playbackURL) {
            loadURL = playbackURL
        } else if let registration = await PrefetchProxy.shared.register(
            originalURL: playbackURL,
            headerProvider: cloudDriveStreamingHeaderProvider()
        ) {
            loadURL = registration.url
            prefetchToken = registration.token
            VanmoLogger.player.info("[PlayerVM] using prefetch proxy for remote URL")
        } else {
            loadURL = playbackURL
            VanmoLogger.player.info("[PlayerVM] prefetch unavailable, loading remote URL directly")
        }

        let startPosition: CMTime? = item.lastPlaybackPosition > 0
            ? CMTime(seconds: item.lastPlaybackPosition, preferredTimescale: 600)
            : nil
        VanmoLogger.player.info("[PlayerVM] calling engine.load(), startPosition: \(startPosition?.seconds ?? 0)s")
        try await engine.load(url: loadURL, startPosition: startPosition)
        VanmoLogger.player.info("[PlayerVM] engine.load() succeeded, state: \(String(describing: self.playbackState))")
        audioTracks = await engine.availableAudioTracks()
        let embeddedSubtitleTracks = await engine.availableSubtitleTracks()
        externalSubtitleTracks = await discoverExternalSubtitleTracks(for: originalURL)
        subtitleTracks = embeddedSubtitleTracks + externalSubtitleTracks
        await applyPreferredSubtitleIfNeeded()
        VanmoLogger.player.info("[PlayerVM] audio tracks: \(self.audioTracks.count), subtitle tracks: \(self.subtitleTracks.count)")
        await updateDynamicRangeIfNeeded(for: originalURL)
        loadChapters()
        VanmoLogger.player.info("[PlayerVM] calling engine.play()")
        engine.play()
        VanmoLogger.player.info("[PlayerVM] engine.play() called, state: \(String(describing: self.playbackState))")
    }

    private func resetPlaybackMetadata() {
        currentTime = 0
        duration = 0
        bufferProgress = 0
        audioTracks = []
        subtitleTracks = []
        chapters = []
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

    private func unregisterPrefetchIfNeeded() async throws {
        guard let token = prefetchToken else { return }
        prefetchToken = nil
        await PrefetchProxy.shared.unregister(token: token)
    }

    /// OneDrive/Box/pCloud/Yandex.Disk 换到的直链都是有时效性的签名 URL，扫描时持久化进
    /// `MediaItem.fileURL` 的版本很可能在播放时已经过期；这里按 `sourceConnectionId + serverId`
    /// 重新连接对应服务、换一个新鲜直链再播放。Google Drive 的 API URL 本身不过期（靠下面的
    /// headerProvider 动态带 Bearer），不需要这一步；非 OAuth 网盘也直接跳过。
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
            VanmoLogger.player.error("[PlayerVM] 重新解析 \(connection.type.displayName) 直链失败，回退到缓存 URL: \(error.localizedDescription)")
            return url
        }
    }

    /// 若当前条目来自需要自定义请求头的 OAuth 网盘，返回 header provider 交给 PrefetchProxy：
    /// - Google Drive：动态 Bearer token
    /// - 百度网盘：固定 User-Agent（dlink 下载/播放要求）
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

    func toggleKSPictureInPicture() {
        guard let ksEngine = engine as? KSPlayerEngine else { return }
        if !ksEngine.isPictureInPictureSupported {
            showNotice(
                title: "画中画不可用",
                message: "当前 KSPlayer 路径暂无法启动画中画。可尝试 MP4/MOV/HLS 等 AVFoundation 原生格式。"
            )
            return
        }
        if !ksEngine.togglePictureInPicture() {
            showNotice(
                title: "画中画暂不可用",
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
                    self.onlineSubtitleStatusMessage = results.isEmpty ? "未找到匹配的在线字幕" : nil
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
                    self.showNotice(title: "在线字幕不可用", message: error.localizedDescription)
                }
            }
        }
    }

    /// 设置外挂字幕的时间偏移（正值表示字幕提前显示）。内嵌字幕由引擎渲染，暂不支持偏移。
    func setSubtitleDelay(_ delay: TimeInterval) {
        config.subtitleDelay = delay
        Task {
            await externalSubtitleManager.setDelay(delay)
            if activeRichSubtitleID != nil, let ksEngine = engine as? KSPlayerEngine {
                ksEngine.setExternalRichSubtitleDelay(delay)
            }
            updateExternalSubtitle(at: currentTime)
        }
    }

    private func applySubtitleSelection(_ index: Int?) async {
        guard let index else {
            activeExternalSubtitleID = nil
            activeRichSubtitleID = nil
            currentSubtitleContent = nil
            await externalSubtitleManager.clear()
            (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
            await engine.selectSubtitleTrack(index: nil)
            return
        }

        guard let track = subtitleTracks.first(where: { $0.id == index }) else { return }
        if let fileURL = track.fileURL, !track.isEmbedded {
            do {
                await engine.selectSubtitleTrack(index: nil)
                if SubtitleFormat.detect(from: fileURL).isRichTextFormat {
                    guard let ksEngine = engine as? KSPlayerEngine else {
                        throw SubtitleError.assRenderingUnavailable
                    }
                    await externalSubtitleManager.clear()
                    try await ksEngine.selectExternalRichSubtitle(url: fileURL, delay: config.subtitleDelay)
                    activeExternalSubtitleID = nil
                    activeRichSubtitleID = track.id
                    currentSubtitleContent = nil
                } else {
                    (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
                    try await externalSubtitleManager.load(from: fileURL)
                    await externalSubtitleManager.setDelay(config.subtitleDelay)
                    activeExternalSubtitleID = track.id
                    activeRichSubtitleID = nil
                    updateExternalSubtitle(at: currentTime)
                }
            } catch {
                VanmoLogger.subtitle.error("[PlayerVM] Failed to load external subtitle: \(error.localizedDescription)")
                activeExternalSubtitleID = nil
                activeRichSubtitleID = nil
                currentSubtitleContent = nil
                showNotice(title: "字幕不可用", message: error.localizedDescription)
            }
        } else {
            activeExternalSubtitleID = nil
            activeRichSubtitleID = nil
            currentSubtitleContent = nil
            await externalSubtitleManager.clear()
            (engine as? KSPlayerEngine)?.clearExternalRichSubtitle()
            await engine.selectSubtitleTrack(index: index)
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
        guard !subtitleTracks.isEmpty else {
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: no subtitle tracks available")
            return
        }

        switch resolveSavedSubtitleSelection() {
        case .off:
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: restoring saved selection (off)")
            config.selectedSubtitleTrack = nil
            await applySubtitleSelection(nil)
            return
        case .track(let savedIndex):
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: restoring saved track index=\(savedIndex)")
            config.selectedSubtitleTrack = savedIndex
            await applySubtitleSelection(savedIndex)
            return
        case .none:
            break
        }

        if !subtitleAutoLoad {
            VanmoLogger.player.info("[PlayerVM] applyPreferredSubtitle: auto-load disabled")
            config.selectedSubtitleTrack = nil
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
        await applySubtitleSelection(preferredIndex)
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
        engine.stop()
        item = episode.mediaItem ?? makeMediaItem(from: episode)
        currentEpisodeID = episode.id
        showEpisodeSelector = false

        do {
            try await loadAndPlayCurrentItem()
            showControlsBriefly()
        } catch {
            VanmoLogger.player.error("[PlayerVM] episode switch failed: \(error.localizedDescription)")
            playbackState = .error(error.localizedDescription)
        }
    }

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
    }

    private func resolveDiscPlaybackURLIfNeeded(_ url: URL) async -> URL {
        guard MediaFormatProbe.isDiscImage(url) else { return url }
        guard url.isFileURL else {
            showNotice(
                title: "远程原盘将直接尝试播放",
                message: "远程 BDMV/ISO 的 playlist 随机读取尚受限，当前会先交给 KSPlayer 直接尝试。"
            )
            return url
        }
        guard url.pathExtension.lowercased() != "iso" else {
            showNotice(
                title: "ISO playlist 解析暂不可用",
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
                title: "原盘 playlist 已解析",
                message: "已识别 \(playlist.id)，但播放片段路径无法定位，将回退为直接播放原始路径。"
            )
        } catch {
            VanmoLogger.player.error("[PlayerVM] BDMV playlist parse failed: \(error.localizedDescription)")
            showNotice(
                title: "原盘解析失败",
                message: "\(error.localizedDescription)。将回退为 KSPlayer 直接尝试播放。"
            )
        }
        return url
    }

    private static func shouldBypassPrefetch(for url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "concat":
            return true
        default:
            return false
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
    }

    func commitSeekGesture() {
        guard seekPreviewActive else { return }
        seek(to: seekTime)
        seekBaseTime = nil
        seekPreviewActive = false
        showControlsBriefly()
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
        guard activeExternalSubtitleID != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let cue = await externalSubtitleManager.cue(at: time)
            await MainActor.run {
                guard self.activeExternalSubtitleID != nil else { return }
                let content = cue.map { SubtitleContent(text: $0.text) }
                if content != self.currentSubtitleContent {
                    self.currentSubtitleContent = content
                }
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
        }
        if item.isProgressCloudSynced, let context = item.modelContext {
            CloudSyncCoordinator.shared.markMediaProgressChanged(item, in: context)
            try? context.save()
            CloudSyncCoordinator.shared.requestSync(reason: "playback-progress", context: context)
        } else {
            try? item.modelContext?.save()
        }
    }

    private func dismissOverlay<T>(_ keyPath: ReferenceWritableKeyPath<PlayerViewModel, T?>, after: TimeInterval = 1.0) {
        Task {
            try? await Task.sleep(for: .seconds(after))
            withAnimation { self[keyPath: keyPath] = nil }
        }
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
        title.isEmpty ? "第 \(episodeNumber) 集" : title
    }

    var episodeCode: String {
        "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
    }
}
