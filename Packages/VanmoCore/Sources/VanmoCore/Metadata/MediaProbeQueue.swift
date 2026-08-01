import Foundation
import SwiftData

public typealias ProbeURLResolver = @Sendable (MediaItem) async throws -> URL

public actor MediaProbeQueue {
    public static let shared = MediaProbeQueue()

    private var provider: (any MediaProbeProviding)?
    private var urlResolver: ProbeURLResolver?
    private var inflight: Set<UUID> = []
    private var isPaused = false
    private let maxConcurrentProbes = 2

    public func setProvider(_ provider: (any MediaProbeProviding)?) {
        self.provider = provider
    }

    public func setURLResolver(_ resolver: ProbeURLResolver?) {
        self.urlResolver = resolver
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }

    public func enqueue(items: [MediaItem], in context: ModelContext) async {
        guard provider != nil else { return }
        let candidates = items.filter { MediaProbeApplicator.shouldProbe(item: $0) }
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            var active = 0

            func scheduleNext() {
                while active < maxConcurrentProbes, !isPaused, let item = iterator.next() {
                    guard inflight.insert(item.id).inserted else { continue }
                    active += 1
                    group.addTask {
                        await self.probe(item: item, context: context)
                    }
                }
            }

            scheduleNext()
            while active > 0 {
                await group.next()
                active -= 1
                scheduleNext()
            }
        }
    }

    private func probe(item: MediaItem, context: ModelContext) async {
        defer { inflight.remove(item.id) }
        guard !Task.isCancelled, let provider else { return }

        let fingerprint = ProbeFingerprint.from(item: item)
        await MainActor.run {
            MediaProbeApplicator.markPending(item)
        }

        do {
            let playbackURL: URL
            if let urlResolver {
                playbackURL = try await urlResolver(item)
            } else if PlaybackURLResolver.isPlaceholder(item.fileURL) {
                throw NetworkError.invalidURL
            } else {
                playbackURL = item.fileURL
            }

            let result = try await provider.probe(url: playbackURL, timeout: 12)
            await MainActor.run {
                MediaProbeApplicator.apply(result, to: item, fingerprint: fingerprint)
                try? context.save()
            }
        } catch {
            await MainActor.run {
                MediaProbeApplicator.apply(
                    MediaProbeResult(status: .failed, message: error.localizedDescription),
                    to: item,
                    fingerprint: fingerprint
                )
                try? context.save()
            }
        }
    }
}
