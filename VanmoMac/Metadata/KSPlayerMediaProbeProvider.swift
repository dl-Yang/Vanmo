import Foundation
import KSPlayer
import VanmoCore

final class KSPlayerMediaProbeProvider: MediaProbeProviding, @unchecked Sendable {
    func probe(url: URL, timeout: TimeInterval) async throws -> MediaProbeResult {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let result = try await Self.probeOnMainActor(url: url, timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    private static func probeOnMainActor(url: URL, timeout: TimeInterval) async throws -> MediaProbeResult {
        let playbackURL = url.isFileURL ? URL(fileURLWithPath: url.path, isDirectory: false) : url
        let options = KSOptions()
        options.isSecondOpen = true
        options.hardwareDecode = false
        options.formatContextOptions["probesize"] = 512 * 1024
        options.formatContextOptions["analyzeduration"] = 2_000_000
        options.formatContextOptions["buffer_size"] = 512 * 1024

        let player = KSMEPlayer(url: playbackURL, options: options)
        let delegate = ProbeDelegate(timeout: timeout)
        player.delegate = delegate
        player.prepareToPlay()

        do {
            try await delegate.waitForReady()
        } catch {
            player.shutdown()
            throw error
        }

        defer { player.shutdown() }

        let duration = player.duration
        let container = playbackURL.pathExtension.lowercased()
        let videoTracks = player.tracks(mediaType: .video)
        let videoTrack = videoTracks.first
        let parsedVideo = parseTrackDescription(videoTrack?.description ?? "")
        let dynamicRange = await PlayerCapabilityProbe.detectDynamicRange(for: playbackURL)

        let audioTracks = player.tracks(mediaType: .audio).enumerated().map { index, track in
            let parsed = parseTrackDescription(track.description)
            return AudioTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                codec: parsed.codec,
                channels: parsed.channels
            )
        }

        let subtitleTracks = player.tracks(mediaType: .subtitle).enumerated().map { index, track in
            SubtitleTrackInfo(
                id: index,
                language: track.languageCode,
                title: track.name,
                isEmbedded: true,
                fileURL: nil
            )
        }

        return MediaProbeResult(
            status: duration > 0 || videoTrack != nil ? .success : .partial,
            duration: duration.isFinite ? max(duration, 0) : 0,
            container: container.isEmpty ? nil : container,
            videoWidth: parsedVideo.width,
            videoHeight: parsedVideo.height,
            videoCodec: parsedVideo.codec,
            dynamicRange: dynamicRange,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
    }

    private static func parseTrackDescription(_ raw: String) -> (codec: String, channels: Int?, width: Int?, height: Int?) {
        let lower = raw.lowercased()

        let codec: String
        if lower.contains("hevc") || lower.contains("h265") || lower.contains("hev1") {
            codec = "HEVC"
        } else if lower.contains("h264") || lower.contains("avc1") {
            codec = "H.264"
        } else if lower.contains("av1") {
            codec = "AV1"
        } else if lower.contains("vp9") {
            codec = "VP9"
        } else if lower.contains("mpeg4") {
            codec = "MPEG-4"
        } else {
            codec = raw.isEmpty ? "Unknown" : raw
        }

        var channels: Int?
        if let match = lower.range(of: #"(\d+)\s*ch"#, options: .regularExpression) {
            let token = String(lower[match])
            channels = Int(token.filter(\.isNumber))
        }

        var width: Int?
        var height: Int?
        if let match = lower.range(of: #"(\d{3,4})x(\d{3,4})"#, options: .regularExpression) {
            let token = String(lower[match])
            let parts = token.split(separator: "x")
            if parts.count == 2 {
                width = Int(parts[0])
                height = Int(parts[1])
            }
        }

        return (codec, channels, width, height)
    }
}

@MainActor
private final class ProbeDelegate: NSObject, MediaPlayerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(timeout: TimeInterval) {
        super.init()
        timeoutTask = Task {
            let nanos = UInt64(max(timeout, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            self.resumeOnce(with: .failure(ProbeError.timeout))
        }
    }

    func waitForReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
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
            if let error {
                resumeOnce(with: .failure(error))
            }
        }
    }

    nonisolated func playBackDidFinish(player: some MediaPlayerProtocol, error: Error?) {
        Task { @MainActor in
            if let error {
                resumeOnce(with: .failure(error))
            }
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

private enum ProbeError: LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "媒体探测超时"
        }
    }
}

enum MediaProbeBootstrap {
    static func configure() {
        Task {
            await MediaProbeQueue.shared.setProvider(KSPlayerMediaProbeProvider())
        }
    }
}
