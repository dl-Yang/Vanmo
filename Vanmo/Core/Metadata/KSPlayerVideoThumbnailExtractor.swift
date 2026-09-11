import Foundation
import KSPlayer
import VanmoCore

struct KSPlayerVideoThumbnailExtractor: VideoThumbnailExtracting, Sendable {
    func extractJPEG(from url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data {
        if PlaybackURLResolver.isPlaceholder(url) {
            throw VideoThumbnailError.unsupportedURL
        }

        let started = Date()
        do {
            let data: Data
            if LibavformatOpenGate.needsExclusiveOpen(url) {
                data = try await LibavformatOpenGate.shared.exclusive {
                    try await self.extractOnce(url: url, maxPixelSize: maxPixelSize, timeout: timeout)
                }
            } else {
                data = try await extractOnce(url: url, maxPixelSize: maxPixelSize, timeout: timeout)
            }
            logResult(url: url, started: started, error: nil)
            return data
        } catch {
            logResult(url: url, started: started, error: error)
            throw mappedError(error)
        }
    }

    private func extractOnce(url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let data = try await Self.extractOnMainActor(
                        url: url,
                        maxPixelSize: maxPixelSize,
                        timeout: timeout
                    )
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    private static func extractOnMainActor(
        url: URL,
        maxPixelSize: Int,
        timeout: TimeInterval
    ) async throws -> Data {
        let playbackURL = url.isFileURL ? URL(fileURLWithPath: url.path, isDirectory: false) : url
        let options = KSOptions()
        options.isSecondOpen = true
        options.isAccurateSeek = false
        options.hardwareDecode = false
        options.formatContextOptions["probesize"] = 512 * 1024
        options.formatContextOptions["analyzeduration"] = 2_000_000
        options.formatContextOptions["buffer_size"] = 512 * 1024

        let player = KSMEPlayer(url: playbackURL, options: options)
        let delegate = ThumbnailReadyDelegate(timeout: timeout)
        player.delegate = delegate
        player.isMuted = true
        player.prepareToPlay()
        defer { player.shutdown() }

        let started = Date()
        try await delegate.waitForReady()
        player.play()

        while Date().timeIntervalSince(started) < max(timeout, 0.5) {
            try Task.checkCancellation()
            if let error = delegate.consumedFailure() {
                throw error
            }
            if let image = await player.thumbnailImageAtCurrentTime() {
                player.pause()
                return try VideoThumbnailJPEG.encode(image, maxPixelSize: maxPixelSize)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw VideoThumbnailError.timedOut
    }

    private func mappedError(_ error: Error) -> Error {
        if error is CancellationError {
            return VideoThumbnailError.cancelled
        }
        if let error = error as? VideoThumbnailError {
            return error
        }
        if let error = error as? ThumbnailReadyError {
            switch error {
            case .timeout:
                return VideoThumbnailError.timedOut
            case .failed:
                return VideoThumbnailError.generationFailed
            }
        }
        return VideoThumbnailError.generationFailed
    }

    private func logResult(url: URL, started: Date, error: Error?) {
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        let leaf = LibraryScanDebugLog.leaf(url.lastPathComponent)
        if let error {
            LibraryScanDebugLog.thumbnail(
                "extractEngine file=\(leaf) engine=ksplayer-me elapsedMs=\(elapsedMs) error=\(debugName(error))"
            )
        } else {
            LibraryScanDebugLog.thumbnail(
                "extractEngine file=\(leaf) engine=ksplayer-me elapsedMs=\(elapsedMs)"
            )
        }
    }

    private func debugName(_ error: Error) -> String {
        if let error = error as? VideoThumbnailError {
            return error.debugName
        }
        if let error = error as? ThumbnailReadyError {
            switch error {
            case .timeout:
                return VideoThumbnailError.timedOut.debugName
            case .failed:
                return VideoThumbnailError.generationFailed.debugName
            }
        }
        return VideoThumbnailError.generationFailed.debugName
    }
}

@MainActor
private final class ThumbnailReadyDelegate: NSObject, MediaPlayerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var failure: Error?

    init(timeout: TimeInterval) {
        super.init()
        timeoutTask = Task {
            let nanos = UInt64(max(timeout, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            self.resumeOnce(with: .failure(ThumbnailReadyError.timeout))
        }
    }

    func waitForReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func consumedFailure() -> Error? {
        let error = failure
        failure = nil
        return error
    }

    nonisolated func readyToPlay(player: some MediaPlayerProtocol) {
        Task { @MainActor in
            resumeOnce(with: .success(()))
        }
    }

    nonisolated func changeLoadState(player: some MediaPlayerProtocol) {}

    nonisolated func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {}

    nonisolated func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}

    nonisolated func finish(player: some MediaPlayerProtocol, error: Error?) {
        Task { @MainActor in
            guard error != nil else { return }
            self.failure = ThumbnailReadyError.failed
            resumeOnce(with: .failure(ThumbnailReadyError.failed))
        }
    }

    private func resumeOnce(with result: Result<Void, Error>) {
        timeoutTask?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum ThumbnailReadyError: Error {
    case timeout
    case failed
}
