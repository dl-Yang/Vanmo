import Foundation
import AVFoundation
import Combine
import UIKit
import VanmoCore

struct SubtitleContent: Equatable {
    var text: String?
    var attributedText: NSAttributedString?
    var image: UIImage?
    var placement: SubtitlePlacement?

    var isEmpty: Bool { text == nil && attributedText == nil && image == nil }

    static func == (lhs: SubtitleContent, rhs: SubtitleContent) -> Bool {
        lhs.text == rhs.text
            && attributedTextEquals(lhs.attributedText, rhs.attributedText)
            && lhs.image === rhs.image
            && lhs.placement == rhs.placement
    }

    private static func attributedTextEquals(_ lhs: NSAttributedString?, _ rhs: NSAttributedString?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let lhs), .some(let rhs)):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}

struct SubtitlePlacement: Equatable {
    enum Vertical: Equatable {
        case top
        case center
        case bottom
    }

    enum Horizontal: Equatable {
        case leading
        case center
        case trailing
    }

    let vertical: Vertical
    let horizontal: Horizontal
    let verticalMargin: CGFloat
    let leadingMargin: CGFloat
    let trailingMargin: CGFloat
}

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

    func selectAudioTrack(index: Int) async
    func selectSubtitleTrack(index: Int?) async
    func availableAudioTracks() async -> [AudioTrackInfo]
    func availableSubtitleTracks() async -> [SubtitleTrackInfo]

    var subtitleContentPublisher: AnyPublisher<SubtitleContent?, Never> { get }
}

protocol SeekPreviewProviding: AnyObject {
    func previewFrame(at time: TimeInterval, maxPixelSize: Int) async -> UIImage?
    func cachedPreview(at time: TimeInterval) -> UIImage?
    func hasExactCachedPreview(at time: TimeInterval) -> Bool
    func cancelPreviewGeneration()
}

extension SeekPreviewProviding {
    func cachedPreview(at time: TimeInterval) -> UIImage? { nil }
    func hasExactCachedPreview(at time: TimeInterval) -> Bool { false }
    func cancelPreviewGeneration() {}
}

/// 串行抽帧，避免预热和拖动同时打同一个 `AVAssetImageGenerator`。
final class SeekPreviewSerializer: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        lock.lock()
        let previous = tail
        let box = Task<T, Never> {
            await previous?.value
            return await work()
        }
        tail = Task {
            _ = await box.value
        }
        lock.unlock()
        return await box.value
    }
}

private final class EmbyHlsResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let queue = DispatchQueue(label: "vanmo.hls.rewrite")

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let source = Self.sourceURL(from: loadingRequest.request.url) else {
            loadingRequest.finishLoading(with: URLError(.badURL))
            return true
        }
        let requestedStart = Self.startTime(from: loadingRequest.request.url)
        let startTime = requestedStart > 1 ? requestedStart : Self.startTime(in: source)
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: source)
                let text = String(data: data, encoding: .utf8) ?? ""
                let rewritten = EmbyHlsPlaylist.muxedMaster(playlist: text, baseURL: source)
                let started = EmbyHlsPlaylist.applyingStart(playlist: rewritten.playlist, startTime: startTime)
                let nested = Self.wrapNestedPlaylists(started, startTime: startTime)
                let playlist = await HlsSegmentFixServer.shared.rewrite(playlist: nested)
#if DEBUG
                let injected = playlist.contains("#EXT-X-START")
                VanmoLogger.player.info("[Debug][Player] event=videoQualityPlaylist removedAudioGroups=\(rewritten.removedAudioGroups, privacy: .public) startOffset=\(startTime, privacy: .public) injectedStart=\(injected, privacy: .public)")
#endif
                let output = Data(playlist.utf8)
                loadingRequest.contentInformationRequest?.contentType = "public.m3u-playlist"
                loadingRequest.contentInformationRequest?.contentLength = Int64(output.count)
                loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
                if let dataRequest = loadingRequest.dataRequest {
                    let start = Int(dataRequest.requestedOffset)
                    let end = min(output.count, start + dataRequest.requestedLength)
                    if start < output.count, start <= end {
                        dataRequest.respond(with: output.subdata(in: start..<end))
                    }
                }
                loadingRequest.finishLoading()
            } catch {
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    private static func sourceURL(from url: URL?) -> URL? {
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let src = items.first(where: { $0.name == "src" })?.value else {
            return nil
        }
        return URL(string: src)
    }

    private static func startTime(from url: URL?) -> TimeInterval {
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "start" })?.value,
              let value = Double(raw) else {
            return 0
        }
        return value
    }

    fileprivate static func startTime(in url: URL) -> TimeInterval {
        guard let ticks = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("StartTimeTicks") == .orderedSame })?
            .value,
              let value = Double(ticks) else {
            return 0
        }
        return value / 10_000_000
    }

    /// 子播放列表写上 `#EXT-X-START`。媒体分段不走自定义协议，否则 AVPlayer 会解析失败并退回原画。
    fileprivate static func wrapNestedPlaylists(_ playlist: String, startTime: TimeInterval) -> String {
        guard startTime > 1 else { return playlist }
        return playlist.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  trimmed.lowercased().contains(".m3u8"),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return line
            }
            return proxyPlaylistURL(url, startTime: startTime).absoluteString
        }.joined(separator: "\n")
    }

    private static func respond(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        data: Data,
        contentType: String
    ) {
        loadingRequest.contentInformationRequest?.contentType = contentType
        loadingRequest.contentInformationRequest?.contentLength = Int64(data.count)
        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true
        if let dataRequest = loadingRequest.dataRequest {
            let start = max(0, Int(dataRequest.requestedOffset))
            if start < data.count {
                let remaining = data.count - start
                let length = dataRequest.requestedLength > remaining ? remaining : dataRequest.requestedLength
                if length > 0 {
                    dataRequest.respond(with: data.subdata(in: start..<(start + length)))
                }
            }
        }
        loadingRequest.finishLoading()
    }

    fileprivate static func proxyPlaylistURL(_ url: URL, startTime: TimeInterval) -> URL {
        var components = URLComponents()
        components.scheme = "vanmo-hls"
        components.host = "playlist"
        components.path = EmbyHlsPlaylist.playbackProxyPath(for: url)
        var items = [URLQueryItem(name: "src", value: url.absoluteString)]
        if startTime > 1 {
            items.append(URLQueryItem(name: "start", value: String(format: "%.3f", startTime)))
        }
        components.queryItems = items
        return components.url ?? url
    }
}

private final class AVReadyContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancellable: AnyCancellable?
    private var finished = false
    private var pendingError: Error?

    func arm(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if finished {
            let error = pendingError
            lock.unlock()
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func retain(_ cancellable: AnyCancellable) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        self.cancellable = cancellable
        lock.unlock()
    }

    func resume() {
        finish(returning: nil)
    }

    func fail(_ error: Error) {
        finish(returning: error)
    }

    private func finish(returning error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        pendingError = error
        let continuation = continuation
        self.continuation = nil
        cancellable = nil
        lock.unlock()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}

protocol VideoQualityApplying: AnyObject {
    func applyVideoQuality(_ quality: PlaybackVideoQuality)
}

protocol AirPlayRouting: AnyObject {
    var supportsVideoAirPlay: Bool { get }
}

enum EngineType {
    case avFoundation
    case ksPlayer
}

extension PlayerEngine {
    var engineType: EngineType {
        if self is AVPlayerEngine {
            return .avFoundation
        }
        return .ksPlayer
    }
}

final class AVPlayerEngine: NSObject, PlayerEngine, SeekPreviewProviding, VideoQualityApplying, AirPlayRouting {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playbackURL: URL?
    private var timeObserver: Any?
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private var cancellables = Set<AnyCancellable>()
    private var previewGenerator: AVAssetImageGenerator?
    private var previewCache: [Int: UIImage] = [:]
    private var previewCacheOrder: [Int] = []
    private let previewSerializer = SeekPreviewSerializer()
    private var hlsRewriteLoader: EmbyHlsResourceLoader?

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let durationSubject = CurrentValueSubject<CMTime, Never>(.zero)
    private let bufferProgressSubject = CurrentValueSubject<Double, Never>(0)
    private let subtitleContentSubject = CurrentValueSubject<SubtitleContent?, Never>(nil)

#if DEBUG
    private var performanceLoadStartedAt: CFAbsoluteTime?
    private var performanceBufferingStartedAt: CFAbsoluteTime?
    private var performanceBufferingCount = 0
    private var performanceLastSampleAt: CFAbsoluteTime = 0
    private var performanceThermalState = ProcessInfo.processInfo.thermalState
#endif

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
        VanmoLogger.player.info("[AVEngine] load() called, url: \(url.safePlaybackLogDescription)")
        stop()
#if DEBUG
        performanceLoadStartedAt = CFAbsoluteTimeGetCurrent()
        performanceBufferingStartedAt = nil
        performanceBufferingCount = 0
        performanceLastSampleAt = 0
        performanceThermalState = ProcessInfo.processInfo.thermalState
#endif
        stateSubject.send(.loading)

        let (cleanURL, asset) = makePlaybackAsset(from: url)
        VanmoLogger.player.info("[AVEngine] AVURLAsset created, isPlayable check pending")
        let playerItem = AVPlayerItem(asset: asset)
        self.playbackURL = cleanURL
        self.playerItem = playerItem
        if !Self.isTranscodedPlaylist(cleanURL) {
            Self.assignVideoQuality(PlaybackPreferences.videoQuality, to: playerItem)
        }

        // HDR 输出：让系统按帧应用 HDR 动态元数据（HDR10+/Dolby Vision），
        // 在支持 EDR 的屏幕上获得正确的高动态范围呈现。iOS 自动管理 SDR/HDR 切换。
        // 转码 HLS 关掉这项，避免画面比声音多走一截显示延迟。
        playerItem.appliesPerFrameHDRDisplayMetadata = !Self.isTranscodedPlaylist(cleanURL)
        if PlayerCapabilityProbe.isHDRCandidate(url: cleanURL) {
            VanmoLogger.player.info("[AVEngine] HDR candidate detected, per-frame HDR metadata enabled")
        }

        let output = AVPlayerItemLegibleOutput()
        output.setDelegate(self, queue: .main)
        output.suppressesPlayerRendering = true
        playerItem.add(output)
        self.legibleOutput = output

        let player = AVPlayer()
        player.allowsExternalPlayback = Self.supportsVideoAirPlay(for: cleanURL)
        player.usesExternalPlaybackWhileExternalScreenIsActive = player.allowsExternalPlayback
        if Self.isTranscodedPlaylist(cleanURL) {
            player.automaticallyWaitsToMinimizeStalling = true
        }
        player.replaceCurrentItem(with: playerItem)
        self.player = player
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        previewCache.removeAll()
        previewCacheOrder.removeAll()
        previewGenerator = generator

        setupObservers(for: playerItem, player: player)

        if let startPosition {
            VanmoLogger.player.info("[AVEngine] seeking to start position: \(startPosition.seconds)s")
            await player.seek(to: startPosition, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        VanmoLogger.player.info("[AVEngine] waiting for playerItem to become ready...")
        try await waitForReady(playerItem)
        VanmoLogger.player.info("[AVEngine] playerItem is ready, duration: \(playerItem.duration.seconds)s")
        await alignTracksIfNeeded()
#if DEBUG
        if let startedAt = performanceLoadStartedAt {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
            VanmoLogger.player.info("[Debug][PlaybackPerf] event=ready platform=ios engine=av elapsedMs=\(elapsedMs, privacy: .public)")
        }
#endif
    }

    func play() {
        VanmoLogger.player.info("[AVEngine] play(), rate: \(self.playbackRate)")
        player?.rate = playbackRate
        stateSubject.send(.playing)
    }

    func pause() {
        VanmoLogger.player.info("[AVEngine] pause()")
        player?.pause()
        stateSubject.send(.paused)
    }

    func seek(to time: CMTime) async {
#if DEBUG
        let startedAt = CFAbsoluteTimeGetCurrent()
#endif
        await player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSubject.send(time)
#if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        VanmoLogger.player.info("[Debug][PlaybackPerf] event=seekEnd platform=ios engine=av elapsedMs=\(elapsedMs, privacy: .public)")
#endif
    }

    func replacePlaybackItem(url: URL, startPosition: CMTime?) async throws {
        guard let player else {
            try await load(url: url, startPosition: startPosition)
            return
        }
        VanmoLogger.player.info("[AVEngine] replace item url=\(url.safePlaybackLogDescription, privacy: .public)")
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        cancellables.removeAll()
        legibleOutput = nil
        stateSubject.send(.loading)

        let (cleanURL, asset) = makePlaybackAsset(from: url)
        let playerItem = AVPlayerItem(asset: asset)
        playbackURL = cleanURL
        self.playerItem = playerItem
        if !Self.isTranscodedPlaylist(cleanURL) {
            Self.assignVideoQuality(PlaybackPreferences.videoQuality, to: playerItem)
        }
        playerItem.appliesPerFrameHDRDisplayMetadata = !Self.isTranscodedPlaylist(cleanURL)
        let output = AVPlayerItemLegibleOutput()
        output.setDelegate(self, queue: .main)
        output.suppressesPlayerRendering = true
        playerItem.add(output)
        legibleOutput = output
        player.replaceCurrentItem(with: playerItem)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        previewCache.removeAll()
        previewCacheOrder.removeAll()
        previewGenerator = generator
        setupObservers(for: playerItem, player: player)
        if let startPosition, startPosition.seconds > 0 {
            await player.seek(to: startPosition, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        try await waitForReady(playerItem)
        await alignTracksIfNeeded()
    }

    func alignTracksIfNeeded() async {
        guard let player, let playerItem else { return }
        guard Self.isTranscodedPlaylist(playbackURL) else { return }
        player.automaticallyWaitsToMinimizeStalling = true
        let time = playerItem.currentTime()
        let seekable = playerItem.seekableTimeRanges.first?.timeRangeValue
        let likely = playerItem.isPlaybackLikelyToKeepUp
#if DEBUG
        let seekStart = seekable?.start.seconds ?? -1
        let seekEnd = seekable.map { $0.start.seconds + $0.duration.seconds } ?? -1
        VanmoLogger.player.info("[Debug][Player] event=videoQualitySync likely=\(likely, privacy: .public) engineTime=\(time.seconds, privacy: .public) seekable=\(seekStart, privacy: .public)-\(seekEnd, privacy: .public)")
#endif
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=videoQualitySync result=kept engineTime=\(time.seconds, privacy: .public)")
#endif
    }

    private static func isTranscodedPlaylist(_ url: URL?) -> Bool {
        guard let query = url?.query?.lowercased() else { return false }
        return query.contains("segmentcontainer") || query.contains("maxheight")
    }

    func stop() {
        VanmoLogger.player.info("[AVEngine] stop()")
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        legibleOutput = nil
        cancellables.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        playbackURL = nil
        previewGenerator = nil
        hlsRewriteLoader = nil
        previewCache.removeAll()
        previewCacheOrder.removeAll()
        stateSubject.send(.idle)
        currentTimeSubject.send(.zero)
        durationSubject.send(.zero)
        subtitleContentSubject.send(nil)
    }

    // MARK: - Track Selection

    func selectAudioTrack(index: Int) async {
        guard let item = playerItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
        let options = group.options
        if index < options.count {
            item.select(options[index], in: group)
        }
    }

    func selectSubtitleTrack(index: Int?) async {
        guard let item = playerItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        if let index {
            let options = group.options
            guard index < options.count, current != options[index] else { return }
            item.select(options[index], in: group)
        } else if current != nil {
            item.select(nil, in: group)
            subtitleContentSubject.send(nil)
        }
    }

    func availableAudioTracks() async -> [AudioTrackInfo] {
        guard let group = try? await playerItem?.asset.loadMediaSelectionGroup(for: .audible) else {
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

    func availableSubtitleTracks() async -> [SubtitleTrackInfo] {
        guard let group = try? await playerItem?.asset.loadMediaSelectionGroup(for: .legible) else {
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

    // MARK: - URL Credential Handling

    private func makePlaybackAsset(from url: URL) -> (URL, AVURLAsset) {
        let (cleanURL, options) = Self.assetURL(from: url)
        let playbackURL = Self.wrappedPlaylistURL(cleanURL)
        let asset = AVURLAsset(url: playbackURL, options: options)
        if playbackURL.scheme == "vanmo-hls" {
            let loader = EmbyHlsResourceLoader()
            hlsRewriteLoader = loader
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        } else {
            hlsRewriteLoader = nil
        }
        return (cleanURL, asset)
    }

    private static func wrappedPlaylistURL(_ url: URL) -> URL {
        guard isTranscodedPlaylist(url) else { return url }
        var components = URLComponents()
        components.scheme = "vanmo-hls"
        components.host = "playlist"
        components.path = "/master.m3u8"
        var items = [URLQueryItem(name: "src", value: url.absoluteString)]
        let start = EmbyHlsResourceLoader.startTime(in: url)
        if start > 1 {
            items.append(URLQueryItem(name: "start", value: String(format: "%.3f", start)))
        }
        components.queryItems = items
        return components.url ?? url
    }

    private static func assetURL(from url: URL) -> (URL, [String: Any]?) {
        guard let user = url.user, !user.isEmpty else {
            return (url, nil)
        }
        let password = url.password ?? ""
        let credential = "\(user):\(password)"
        let base64 = Data(credential.utf8).base64EncodedString()

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.user = nil
        components.password = nil
        let cleanURL = components.url ?? url

        let headers: [String: String] = ["Authorization": "Basic \(base64)"]
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        VanmoLogger.player.info("[AVEngine] URL contains credentials, stripped and added Authorization header")
        return (cleanURL, options)
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
#if DEBUG
            self?.logPerformanceSampleIfNeeded()
#endif
        }

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                VanmoLogger.player.info("[AVEngine] playerItem.status changed: \(status.rawValue) (0=unknown, 1=readyToPlay, 2=failed)")
                switch status {
                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown error"
                    VanmoLogger.player.error("[AVEngine] playerItem failed: \(message)")
                    self?.stateSubject.send(.error(message))
                case .readyToPlay:
                    VanmoLogger.player.info("[AVEngine] playerItem readyToPlay")
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
#if DEBUG
                    guard let self, self.performanceBufferingStartedAt == nil else { return }
                    self.performanceBufferingStartedAt = CFAbsoluteTimeGetCurrent()
                    self.performanceBufferingCount += 1
                    let bufferingCount = self.performanceBufferingCount
                    VanmoLogger.player.info("[Debug][PlaybackPerf] event=bufferingStart platform=ios engine=av count=\(bufferingCount, privacy: .public)")
#endif
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if isReady, self?.state == .buffering {
                    self?.player?.rate = self?.playbackRate ?? 1.0
                    self?.stateSubject.send(.playing)
#if DEBUG
                    if let self, let startedAt = self.performanceBufferingStartedAt {
                        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
                        self.performanceBufferingStartedAt = nil
                        VanmoLogger.player.info("[Debug][PlaybackPerf] event=bufferingEnd platform=ios engine=av elapsedMs=\(elapsedMs, privacy: .public)")
                    }
#endif
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

#if DEBUG
    private func logPerformanceSampleIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - performanceLastSampleAt >= 5 else { return }
        performanceLastSampleAt = now

        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState != performanceThermalState {
            performanceThermalState = thermalState
            let thermal = thermalState.rawValue
            VanmoLogger.player.info("[Debug][PlaybackPerf] event=thermal platform=ios state=\(thermal, privacy: .public)")
        }

        let bufferingCount = performanceBufferingCount
        VanmoLogger.player.info("[Debug][PlaybackPerf] event=sample platform=ios engine=av bufferingCount=\(bufferingCount, privacy: .public)")
    }
#endif

    private func waitForReady(_ item: AVPlayerItem) async throws {
        let current = item.status
        VanmoLogger.player.info("[AVEngine] waitForReady: status=\(current.rawValue)")
        switch current {
        case .readyToPlay:
            VanmoLogger.player.info("[AVEngine] waitForReady: ready!")
            return
        case .failed:
            let message = item.error?.localizedDescription ?? "Unknown error"
            VanmoLogger.player.error("[AVEngine] waitForReady: failed - \(message)")
            throw PlayerError.loadFailed(message)
        default:
            break
        }

        let gate = AVReadyContinuationGate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                gate.arm(continuation)
                let cancellable = item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { status in
                        VanmoLogger.player.info("[AVEngine] waitForReady: status=\(status.rawValue)")
                        switch status {
                        case .readyToPlay:
                            VanmoLogger.player.info("[AVEngine] waitForReady: ready!")
                            gate.resume()
                        case .failed:
                            let message = item.error?.localizedDescription ?? "Unknown error"
                            VanmoLogger.player.error("[AVEngine] waitForReady: failed - \(message)")
                            gate.fail(PlayerError.loadFailed(message))
                        default:
                            break
                        }
                    }
                gate.retain(cancellable)
            }
        } onCancel: {
            gate.fail(CancellationError())
        }
    }

    // MARK: - Quality and AirPlay

    var supportsVideoAirPlay: Bool {
        player?.allowsExternalPlayback == true
    }

    func applyVideoQuality(_ quality: PlaybackVideoQuality) {
        guard let playerItem, let playbackURL else { return }
        let path = playbackURL.path.lowercased()
        guard path.hasSuffix(".m3u8") || path.contains(".m3u8") else {
            VanmoLogger.player.info("[AVEngine] videoQuality saved for next open")
            return
        }
        Self.assignVideoQuality(quality, to: playerItem)
    }

    func cachedPreview(at time: TimeInterval) -> UIImage? {
        nearestCachedPreview(at: time)
    }

    func hasExactCachedPreview(at time: TimeInterval) -> Bool {
        previewCache[Self.previewBucket(for: time)] != nil
    }

    func cancelPreviewGeneration() {
        previewGenerator?.cancelAllCGImageGeneration()
    }

    func previewFrame(at time: TimeInterval, maxPixelSize: Int) async -> UIImage? {
        let bucket = Self.previewBucket(for: time)
        if let cached = previewCache[bucket] {
            return cached
        }
        let generated = await previewSerializer.run { [weak self] () -> UIImage? in
            guard let self, let previewGenerator = self.previewGenerator else { return nil }
            if self.previewCache[bucket] != nil { return self.previewCache[bucket] }
            previewGenerator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
            do {
                let image = try await previewGenerator.image(at: cmTime).image
                return UIImage(cgImage: image)
            } catch {
                return nil
            }
        }
        if let generated {
            storePreview(generated, bucket: bucket)
            return generated
        }
        return nearestCachedPreview(at: time)
    }

    private static func assignVideoQuality(_ quality: PlaybackVideoQuality, to item: AVPlayerItem) {
        item.preferredMaximumResolution = quality.preferredMaximumResolution ?? .zero
        item.preferredPeakBitRate = quality.preferredPeakBitRate ?? 0
    }

    private func nearestCachedPreview(at time: TimeInterval) -> UIImage? {
        guard !previewCache.isEmpty else { return nil }
        let bucket = Self.previewBucket(for: time)
        if let exact = previewCache[bucket] { return exact }
        return previewCache.min { abs($0.key - bucket) < abs($1.key - bucket) }?.value
    }

    private func storePreview(_ image: UIImage, bucket: Int) {
        if previewCache[bucket] == nil {
            previewCacheOrder.append(bucket)
        }
        previewCache[bucket] = image
        while previewCache.count > 360, let oldest = previewCacheOrder.first {
            previewCacheOrder.removeFirst()
            previewCache.removeValue(forKey: oldest)
        }
    }

    private static func previewBucket(for time: TimeInterval) -> Int {
        Int((max(0, time) / 2).rounded(.down))
    }

    static func supportsVideoAirPlay(for url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return false }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "m3u8", "m3u"].contains(ext) {
            return true
        }
        return url.path.lowercased().contains(".m3u8")
    }
}

// MARK: - AVPlayerItemLegibleOutputPushDelegate

extension AVPlayerEngine: AVPlayerItemLegibleOutputPushDelegate {
    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.map { $0.string }.joined(separator: "\n")
        let content: SubtitleContent? = text.isEmpty ? nil : SubtitleContent(text: text)
        if content != subtitleContentSubject.value {
            subtitleContentSubject.send(content)
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
        case .unsupportedFormat: return L10n.tr("不支持的视频格式")
        case .networkError(let msg): return "网络错误: \(msg)"
        }
    }
}
