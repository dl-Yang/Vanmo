import MediaPlayer
import UIKit
import VanmoCore

/// 把当前播放写到系统「正在播放」，并接收锁屏、控制中心和耳机上的播放命令。
@MainActor
final class NowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSkip: ((TimeInterval) -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private var installed = false
    private var title = ""
    private var isLive = false
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var lastElapsed: TimeInterval = 0
    private var lastDuration: TimeInterval = 0
    private var lastRate: Float = 0

    func start(title: String, isLive: Bool) {
        self.title = title
        self.isLive = isLive
        artwork = nil
        artworkTask?.cancel()
        installCommandsIfNeeded()
        applyCommandAvailability()
        VanmoLogger.player.info("[Player] now playing started live=\(isLive, privacy: .public)")
    }

    func setArtwork(from url: URL?) {
        artworkTask?.cancel()
        artwork = nil
        guard let url, installed else { return }
        artworkTask = Task { [weak self] in
            let image = await Self.loadImage(at: url)
            guard !Task.isCancelled, let self, let image else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.publish()
        }
    }

    func update(elapsed: TimeInterval, duration: TimeInterval, rate: Float) {
        guard installed else { return }
        lastElapsed = elapsed
        lastDuration = duration
        lastRate = rate
        publish()
    }

    func stop() {
        guard installed else { return }
        artworkTask?.cancel()
        artworkTask = nil
        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens.removeAll()
        installed = false
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        VanmoLogger.player.info("[Player] now playing stopped")
    }

    private func installCommandsIfNeeded() {
        guard !installed else { return }
        installed = true
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { [weak self] _ in
            self?.logRemote("play")
            self?.onPlay?()
        }
        add(center.pauseCommand) { [weak self] _ in
            self?.logRemote("pause")
            self?.onPause?()
        }
        add(center.togglePlayPauseCommand) { [weak self] _ in
            guard let self else { return }
            self.logRemote("toggle")
            if self.lastRate > 0 {
                self.onPause?()
            } else {
                self.onPlay?()
            }
        }
        add(center.skipForwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.logRemote("skipForward")
            self?.onSkip?(interval)
        }
        add(center.skipBackwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.logRemote("skipBackward")
            self?.onSkip?(-interval)
        }
        add(center.changePlaybackPositionCommand) { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return }
            self?.logRemote("seek")
            self?.onSeek?(position)
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
    }

    private func applyCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let canSeek = !isLive
        center.skipForwardCommand.isEnabled = canSeek
        center.skipBackwardCommand.isEnabled = canSeek
        center.changePlaybackPositionCommand.isEnabled = canSeek
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping @MainActor (MPRemoteCommandEvent) -> Void
    ) {
        let token = command.addTarget { event in
            let apply = {
                MainActor.assumeIsolated {
                    handler(event)
                }
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.sync(execute: apply)
            }
            return .success
        }
        commandTokens.append((command, token))
    }

    private func logRemote(_ command: String) {
#if DEBUG
        VanmoLogger.player.info("[Debug][Player] event=nowPlaying remote=\(command, privacy: .public)")
#endif
    }

    private func publish() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: lastElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: lastRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if isLive {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        } else if lastDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = lastDuration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private static func loadImage(at url: URL) async -> UIImage? {
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode,
              (200...299).contains(status),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}
