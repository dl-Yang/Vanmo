import AVFoundation
import KSPlayer
import UIKit
import VanmoCore

/// 拖动预览用的第二路播放器。不暂停、不 seek 正在播放的那一路。
@MainActor
final class ScrubPreviewLane {
    var onFrame: ((UIImage) -> Void)?

    private var player: KSMEPlayer?
    private var delegate: PreviewLaneDelegate?
    private var proxyToken: String?
    private var latestTime: TimeInterval?
    private var captureTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var isReady = false
    private var isClosed = false
    private var sourceURL: URL?
    private var sourceHeaders: [String: String] = [:]
    private var sourceHeaderProvider: (() async -> [String: String])?
    private var trickplay: EmbyTrickplayInfo?
    private var trickplayResolved = false
    private var trickplaySheets: [Int: CGImage] = [:]

    func request(
        at time: TimeInterval,
        originalURL: URL,
        headers: [String: String],
        headerProvider: (() async -> [String: String])?
    ) {
        isClosed = false
        latestTime = time
        sourceURL = originalURL
        sourceHeaders = headers
        sourceHeaderProvider = headerProvider
        kickCapture()
    }

    func close() {
        isClosed = true
        latestTime = nil
        openTask?.cancel()
        openTask = nil
        captureTask?.cancel()
        captureTask = nil
        isReady = false
        player?.shutdown()
        player = nil
        delegate = nil
        onFrame = nil
        let token = proxyToken
        proxyToken = nil
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=previewLaneClose hadProxy=\(token != nil, privacy: .public)")
#endif
        if let token {
            Task {
                await PrefetchProxy.shared.unregister(token: token)
            }
        }
    }

    private func open(
        originalURL: URL,
        headers: [String: String],
        headerProvider: (() async -> [String: String])?,
        startTime: TimeInterval
    ) async {
        let resolved = await Self.resolve(
            originalURL: originalURL,
            headers: headers,
            headerProvider: headerProvider
        )
        guard !isClosed, !Task.isCancelled else {
            if let token = resolved.token {
                await PrefetchProxy.shared.unregister(token: token)
            }
            return
        }
        proxyToken = resolved.token
        let options = KSOptions()
        options.isAccurateSeek = false
        options.isSecondOpen = !PrefetchConfig.shouldDisableSecondOpen(for: resolved.url)
        options.hardwareDecode = true
        options.startPlayTime = max(0, startTime)
        options.formatContextOptions["probesize"] = 512 * 1024
        options.formatContextOptions["analyzeduration"] = 2_000_000
        options.formatContextOptions["buffer_size"] = 512 * 1024
        if !resolved.headers.isEmpty {
            options.appendHeader(resolved.headers)
        }

        let readyDelegate = PreviewLaneDelegate()
        delegate = readyDelegate
        let previousAudio = KSOptions.audioPlayerType
        KSOptions.audioPlayerType = SilentPreviewAudioOutput.self
        let previewPlayer = KSMEPlayer(url: resolved.url, options: options)
        KSOptions.audioPlayerType = previousAudio
        previewPlayer.delegate = readyDelegate
        previewPlayer.isMuted = true
        player = previewPlayer
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=previewLaneOpen mode=\(resolved.mode, privacy: .public) hardwareDecode=true url=\(resolved.url.safePlaybackLogDescription, privacy: .public)")
#endif
        previewPlayer.prepareToPlay()
        let opened = await readyDelegate.waitForReady()
        guard opened, !isClosed else { return }
        isReady = true
        previewPlayer.play()
    }

    private func kickCapture() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            await self?.captureLoop()
        }
    }

    private func captureLoop() async {
        defer { captureTask = nil }
        while !isClosed, !Task.isCancelled {
            guard let started = latestTime else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !isClosed, let time = latestTime else { return }
            if abs(time - started) > 0.35 {
                continue
            }
            latestTime = nil
            if let image = await trickplayImage(at: time) {
                publish(image, at: time, source: "trickplay")
                continue
            }
            await ensurePlayer(startTime: time)
            guard isReady, let image = await keyframeImage(at: time) else { continue }
            if let newer = latestTime, abs(newer - time) > 2 {
                continue
            }
            publish(image, at: time, source: "player")
        }
    }

    private func publish(_ image: UIImage, at time: TimeInterval, source: String) {
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=previewLaneShow time=\(time, privacy: .public) source=\(source, privacy: .public)")
#endif
        onFrame?(image)
    }

    private func ensurePlayer(startTime: TimeInterval) async {
        guard player == nil, let sourceURL else { return }
        await open(
            originalURL: sourceURL,
            headers: sourceHeaders,
            headerProvider: sourceHeaderProvider,
            startTime: startTime
        )
    }

    private func keyframeImage(at time: TimeInterval) async -> UIImage? {
        guard let player else { return nil }
#if DEBUG
        let startedAt = CFAbsoluteTimeGetCurrent()
        VanmoLogger.player.info("[Debug][Player] event=previewLaneSeekStart time=\(time, privacy: .public)")
#endif
        await seek(player, to: time)
        guard !isClosed else { return nil }
        (player.view as? MetalPlayView)?.flush()
        player.play()
        var image: CGImage?
        var reason = "none"
        for _ in 0..<30 {
            if let newer = latestTime, abs(newer - time) > 2 { break }
            (player.view as? MetalPlayView)?.readNextFrame()
            guard let next = await player.thumbnailImageAtCurrentTime() else {
                try? await Task.sleep(for: .milliseconds(40))
                continue
            }
            if let displayed = displayedTime(of: player), abs(displayed - time) < 2.5 {
                image = next
                reason = "pts"
                break
            }
            if abs(player.currentPlaybackTime - time) < 2.5 {
                image = next
                reason = "clock"
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        player.pause()
#if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        let clock = player.currentPlaybackTime
        VanmoLogger.player.info("[Debug][Player] event=previewLaneSeekEnd time=\(time, privacy: .public) clock=\(clock, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) image=\(image != nil, privacy: .public) reason=\(reason, privacy: .public)")
#endif
        guard let image else { return nil }
        return Self.scaled(image, maxPixelSize: 240)
    }

    private func displayedTime(of player: KSMEPlayer) -> TimeInterval? {
        guard let layer = (player.view as? MetalPlayView)?.displayLayer.timebase else { return nil }
        let seconds = CMTimebaseGetTime(layer).seconds
        guard seconds.isFinite, seconds > 0.2 else { return nil }
        return seconds
    }

    private func seek(_ player: KSMEPlayer, to time: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = PlaybackSeekCompletionGate(continuation)
            player.seek(time: max(0, time)) { _ in
                gate.resume()
            }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(4))
                _ = gate.resume()
            }
            gate.installTimeout(timeout)
        }
    }

    private static func resolve(
        originalURL: URL,
        headers: [String: String],
        headerProvider: (() async -> [String: String])?
    ) async -> (url: URL, headers: [String: String], token: String?, mode: String) {
        if Self.usesDirectConnection(originalURL) {
            return (originalURL, headers, nil, "direct")
        }
        if let registration = await PrefetchProxy.shared.register(
            originalURL: originalURL,
            headerProvider: headerProvider
        ) {
            return (registration.url, [:], registration.token, "proxy")
        }
        return (originalURL, headers, nil, "direct")
    }

    private func trickplayImage(at time: TimeInterval) async -> UIImage? {
        guard let sourceURL else { return nil }
        if !trickplayResolved {
            trickplay = await EmbyTrickplayInfo.load(from: sourceURL)
            trickplayResolved = true
#if DEBUG
            VanmoLogger.player.info("[Debug][Player] event=previewLaneTrickplay available=\(self.trickplay != nil, privacy: .public)")
#endif
        }
        guard let trickplay else { return nil }
        let index = trickplay.index(at: time)
        if trickplaySheets[index.sheet] == nil {
            guard let sheet = await trickplay.downloadSheet(index.sheet) else { return nil }
            trickplaySheets[index.sheet] = sheet
        }
        guard let sheet = trickplaySheets[index.sheet],
              let tile = trickplay.crop(sheet, column: index.column, row: index.row) else {
            return nil
        }
        return UIImage(cgImage: tile)
    }

    private static func usesDirectConnection(_ url: URL) -> Bool {
        if url.isFileURL { return true }
        if PrefetchConfig.isMediaServerStreamURL(url) { return true }
        return url.path.lowercased().contains("/library/parts")
    }

    private static func scaled(_ image: CGImage, maxPixelSize: Int) -> UIImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return UIImage(cgImage: image) }
        let scale = CGFloat(maxPixelSize) / CGFloat(longest)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct EmbyTrickplayInfo: Sendable {
        let interval: TimeInterval
    let tileWidth: Int
    let tileHeight: Int
    let imageBase: URL
    let apiKey: String?

    static func load(from streamURL: URL) async -> EmbyTrickplayInfo? {
        guard let item = itemLocation(from: streamURL) else { return nil }
        var items = item.base
        items.appendPathComponent("Items/\(item.id)")
        guard var components = URLComponents(url: items, resolvingAgainstBaseURL: false) else { return nil }
        var query = [URLQueryItem(name: "Fields", value: "Trickplay")]
        if let apiKey = item.apiKey {
            query.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = query
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trickplay = json["Trickplay"] as? [String: Any],
              let descriptor = bestDescriptor(in: trickplay) else {
            return nil
        }
        var base = item.base
        base.appendPathComponent("Videos/\(item.id)/Trickplay/\(descriptor.widthKey)")
        return EmbyTrickplayInfo(
            interval: descriptor.interval,
            tileWidth: descriptor.tileWidth,
            tileHeight: descriptor.tileHeight,
            imageBase: base,
            apiKey: item.apiKey
        )
    }

    func index(at time: TimeInterval) -> (sheet: Int, column: Int, row: Int) {
        let step = max(interval, 1)
        let perSheet = max(tileWidth * tileHeight, 1)
        let thumb = max(0, Int(time / step))
        let sheet = thumb / perSheet
        let position = thumb % perSheet
        return (sheet, position % tileWidth, position / tileWidth)
    }

    func crop(_ sheetImage: CGImage, column: Int, row: Int) -> CGImage? {
        let tileWidthPx = sheetImage.width / tileWidth
        let tileHeightPx = sheetImage.height / tileHeight
        guard tileWidthPx > 0, tileHeightPx > 0 else { return sheetImage }
        let rect = CGRect(
            x: column * tileWidthPx,
            y: row * tileHeightPx,
            width: tileWidthPx,
            height: tileHeightPx
        )
        return sheetImage.cropping(to: rect) ?? sheetImage
    }

    func downloadSheet(_ index: Int) async -> CGImage? {
        let fileURL = imageBase.appendingPathComponent("\(index).jpg")
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return nil }
        if let apiKey {
            components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        }
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data)?.cgImage else {
            return nil
        }
        return image
    }

    private static func itemLocation(from streamURL: URL) -> (base: URL, id: String, apiKey: String?)? {
        let parts = streamURL.path.split(separator: "/").map(String.init)
        guard let videos = parts.firstIndex(of: "Videos"), videos + 1 < parts.count else { return nil }
        let id = parts[videos + 1]
        let prefix = parts.prefix(videos).joined(separator: "/")
        var components = URLComponents()
        components.scheme = streamURL.scheme
        components.host = streamURL.host
        components.port = streamURL.port
        components.path = prefix.isEmpty ? "/" : "/" + prefix
        guard let base = components.url else { return nil }
        let apiKey = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "api_key" }?
            .value
        return (base, id, apiKey)
    }

    private static func bestDescriptor(
        in trickplay: [String: Any]
    ) -> (widthKey: String, interval: TimeInterval, tileWidth: Int, tileHeight: Int)? {
        let parsed = trickplay.compactMap { key, value -> (String, TimeInterval, Int, Int, Int)? in
            guard let info = value as? [String: Any] else { return nil }
            let intervalMs = info["Interval"] as? Double ?? 10_000
            let tileWidth = info["TileWidth"] as? Int ?? 1
            let tileHeight = info["TileHeight"] as? Int ?? 1
            let width = Int(key) ?? (info["Width"] as? Int ?? 0)
            return (key, max(intervalMs / 1000, 1), max(tileWidth, 1), max(tileHeight, 1), width)
        }
        guard let best = parsed.max(by: { $0.4 < $1.4 }) else { return nil }
        return (best.0, best.1, best.2, best.3)
    }
}

private final class SilentPreviewAudioOutput: AudioOutput {
    var renderSource: (any OutputRenderSourceDelegate)?
    var playbackRate: Float = 1
    var volume: Float = 0
    var isMuted = true

    func prepare(audioFormat: AVAudioFormat) {}
    func play() {}
    func pause() {}
    func flush() {}
}

@MainActor
private final class PreviewLaneDelegate: NSObject, MediaPlayerDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false

    func waitForReady() async -> Bool {
        await withCheckedContinuation { continuation in
            if finished {
                continuation.resume(returning: true)
            } else {
                self.continuation = continuation
            }
        }
    }

    nonisolated func readyToPlay(player: some MediaPlayerProtocol) {
        Task { @MainActor in
            self.finish(success: true)
        }
    }

    nonisolated func changeLoadState(player: some MediaPlayerProtocol) {}

    nonisolated func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {}

    nonisolated func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}

    nonisolated func finish(player: some MediaPlayerProtocol, error: Error?) {
        Task { @MainActor in
            if let error {
#if DEBUG
                VanmoLogger.player.error("[Debug][Player] event=previewLaneFail error=\(error.localizedDescription, privacy: .public)")
#endif
                self.finish(success: false)
            }
        }
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = success
        continuation?.resume(returning: success)
        continuation = nil
    }
}
