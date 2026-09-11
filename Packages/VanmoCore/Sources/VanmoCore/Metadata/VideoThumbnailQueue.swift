import Foundation
import SwiftData

public typealias ThumbnailHeaderResolver = @Sendable (UUID) async -> (() async -> [String: String])?
public typealias ThumbnailPrefetchRegistrar = @Sendable (URL, (() async -> [String: String])?) async -> URL?

public actor VideoThumbnailQueue {
    public static let shared = VideoThumbnailQueue()

    public static let defaultMaxPixelSize = 0
    public static let defaultTimeout: TimeInterval = 20

    private var extractor: any VideoThumbnailExtracting
    private var urlResolver: ProbeURLResolver?
    private var headerResolver: ThumbnailHeaderResolver?
    private var prefetchRegistrar: ThumbnailPrefetchRegistrar?
    private var officialPosterResolver: ThumbnailOfficialPosterResolver?
    private var store: VideoThumbnailStore
    private var inflight: Set<String> = []
    private var isPaused = false
    private var isCancelled = false
    private let maxConcurrent = 1

    public init(
        extractor: any VideoThumbnailExtracting = AVFoundationVideoThumbnailExtractor(),
        store: VideoThumbnailStore = VideoThumbnailStore()
    ) {
        self.extractor = extractor
        self.store = store
    }

    public func setExtractor(_ extractor: any VideoThumbnailExtracting) {
        self.extractor = extractor
    }

    public func setURLResolver(_ resolver: ProbeURLResolver?) {
        urlResolver = resolver
    }

    public func setHeaderResolver(_ resolver: ThumbnailHeaderResolver?) {
        headerResolver = resolver
    }

    public func setPrefetchRegistrar(_ registrar: ThumbnailPrefetchRegistrar?) {
        prefetchRegistrar = registrar
    }

    public func setOfficialPosterResolver(_ resolver: ThumbnailOfficialPosterResolver?) {
        officialPosterResolver = resolver
    }

    public func setStore(_ store: VideoThumbnailStore) {
        self.store = store
    }

    public func pause() {
        isPaused = true
    }

    public func cancelPending() {
        isPaused = true
        isCancelled = true
    }

    public func resume() {
        isCancelled = false
        isPaused = false
    }

    public func cachedURL(for cacheKey: String) -> URL? {
        store.existingURL(for: cacheKey)
    }

    public func cachedURL(for request: VideoThumbnailRequest) -> URL? {
        store.existingURL(for: request.cacheKey)
    }

    public func thumbnail(for request: VideoThumbnailRequest) async -> URL? {
        if let cached = store.existingURL(for: request.cacheKey) {
            LibraryScanDebugLog.thumbnail("cacheHit file=\(LibraryScanDebugLog.leaf(request.path))")
            return cached
        }
        return await extractAndStore(request: request, playbackURL: request.sourceURL)
    }

    public func enqueue(items: [MediaItem], in context: ModelContext) async {
        let candidates = items.filter { $0.posterURL == nil && $0.sourceConnectionId != nil && $0.serverId != nil }
        LibraryScanDebugLog.thumbnail("enqueue candidates=\(candidates.count) skippedWithPoster=\(items.count - candidates.count)")
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            var active = 0

            func waitIfPaused() async {
                while isPaused, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            func scheduleNext() async {
                await waitIfPaused()
                while active < maxConcurrent, !isPaused, !isCancelled, let item = iterator.next() {
                    active += 1
                    group.addTask {
                        await self.fillPoster(for: item, context: context)
                    }
                }
            }

            await scheduleNext()
            while active > 0 {
                await group.next()
                active -= 1
                await scheduleNext()
            }
        }
    }

    private func fillPoster(for item: MediaItem, context: ModelContext) async {
        let cancelled = isCancelled
        guard !cancelled else { return }
        let request: VideoThumbnailRequest? = await MainActor.run {
            guard !cancelled, !item.isDeleted, item.posterURL == nil else { return nil }
            return VideoThumbnailRequest.from(item: item, sourceURL: item.fileURL)
        }
        guard let request else {
            LibraryScanDebugLog.thumbnail("skip noRequest file=\(LibraryScanDebugLog.leaf("item"))")
            return
        }

        let playbackURL: URL
        do {
            playbackURL = try await resolvedPlaybackURL(for: item, request: request)
        } catch {
            LibraryScanDebugLog.thumbnail("resolveFail file=\(LibraryScanDebugLog.leaf(item.serverId ?? item.title)) error=\(error.localizedDescription)")
            return
        }

        guard let fileURL = await extractAndStore(
            request: request,
            playbackURL: playbackURL,
            allowOfficialPoster: officialPosterResolver == nil
        ) else {
            LibraryScanDebugLog.thumbnail("extractFail file=\(LibraryScanDebugLog.leaf(request.path))")
            return
        }

        let stillCancelled = isCancelled
        await MainActor.run {
            guard !stillCancelled, !item.isDeleted, item.modelContext != nil, item.posterURL == nil else { return }
            item.posterURL = fileURL
            try? context.save()
            LibraryScanDebugLog.thumbnail("posterSaved file=\(LibraryScanDebugLog.leaf(request.path))")
        }
    }

    private func resolvedPlaybackURL(for item: MediaItem, request: VideoThumbnailRequest) async throws -> URL {
        if let officialPosterResolver {
            switch await officialPosterResolver(request.connectionId, request.path) {
            case .jpeg(let data):
                _ = try store.save(data, for: request.cacheKey)
                LibraryScanDebugLog.thumbnail(
                    "officialPoster file=\(LibraryScanDebugLog.leaf(request.path)) bytes=\(data.count)"
                )
                return store.fileURL(for: request.cacheKey)
            case .skipKeyframe:
                LibraryScanDebugLog.thumbnail("skipKeyframe file=\(LibraryScanDebugLog.leaf(request.path))")
                throw VideoThumbnailError.unsupportedURL
            case .useKeyframe:
                break
            }
        }

        if let urlResolver {
            return try await urlResolver(item)
        }
        if PlaybackURLResolver.isPlaceholder(item.fileURL) {
            LibraryScanDebugLog.thumbnail("skip placeholder file=\(LibraryScanDebugLog.leaf(item.serverId ?? item.title))")
            throw VideoThumbnailError.unsupportedURL
        }
        return item.fileURL
    }

    private func extractAndStore(
        request: VideoThumbnailRequest,
        playbackURL: URL,
        allowOfficialPoster: Bool = true
    ) async -> URL? {
        if let cached = store.existingURL(for: request.cacheKey) {
            return cached
        }
        guard inflight.insert(request.cacheKey).inserted else { return nil }
        defer { inflight.remove(request.cacheKey) }

        do {
            try Task.checkCancellation()
            let data = try await extractJPEG(
                request: request,
                playbackURL: playbackURL,
                allowOfficialPoster: allowOfficialPoster
            )
            let saved = try store.save(data, for: request.cacheKey)
            LibraryScanDebugLog.thumbnail("extractOK file=\(LibraryScanDebugLog.leaf(request.path)) bytes=\(data.count)")
            return saved
        } catch {
            LibraryScanDebugLog.thumbnail("extractError file=\(LibraryScanDebugLog.leaf(request.path)) error=\(Self.debugName(error))")
            return nil
        }
    }

    private func extractJPEG(
        request: VideoThumbnailRequest,
        playbackURL: URL,
        allowOfficialPoster: Bool = true
    ) async throws -> Data {
        let leaf = LibraryScanDebugLog.leaf(request.path)
        if allowOfficialPoster, let officialPosterResolver {
            switch await officialPosterResolver(request.connectionId, request.path) {
            case .jpeg(let data):
                LibraryScanDebugLog.thumbnail("officialPoster file=\(leaf) bytes=\(data.count)")
                return data
            case .skipKeyframe:
                LibraryScanDebugLog.thumbnail("skipKeyframe file=\(leaf)")
                throw VideoThumbnailError.unsupportedURL
            case .useKeyframe:
                break
            }
        }
        if PlaybackURLResolver.isPlaceholder(playbackURL) {
            throw VideoThumbnailError.unsupportedURL
        }
        let prepared = try await prepareExtractURL(request: request, playbackURL: playbackURL)
        LibraryScanDebugLog.thumbnail(
            "extractStart file=\(leaf) scheme=\(prepared.url.scheme ?? "none")\(prepared.viaPrefetch ? " via=prefetch" : "")"
        )
        defer {
            if let token = prepared.prefetchToken {
                Task { await PrefetchProxy.shared.unregister(token: token) }
            }
        }
        return try await extractor.extractJPEG(
            from: prepared.url,
            maxPixelSize: Self.defaultMaxPixelSize,
            timeout: Self.defaultTimeout
        )
    }

    private func prepareExtractURL(
        request: VideoThumbnailRequest,
        playbackURL: URL
    ) async throws -> (url: URL, viaPrefetch: Bool, prefetchToken: String?) {
        guard !playbackURL.isFileURL,
              let headerResolver,
              let provider = await headerResolver(request.connectionId) else {
            return (playbackURL, false, nil)
        }

        let headers = await provider()
        if headers.isEmpty {
            LibraryScanDebugLog.thumbnail(
                "prefetchFail file=\(LibraryScanDebugLog.leaf(request.path)) reason=emptyHeaders"
            )
            throw VideoThumbnailError.generationFailed
        }

        if let prefetchRegistrar {
            guard let url = await prefetchRegistrar(playbackURL, provider) else {
                LibraryScanDebugLog.thumbnail("prefetchFail file=\(LibraryScanDebugLog.leaf(request.path))")
                throw VideoThumbnailError.generationFailed
            }
            return (url, true, nil)
        }

        guard let registration = await PrefetchProxy.shared.register(
            originalURL: playbackURL,
            headerProvider: provider
        ) else {
            LibraryScanDebugLog.thumbnail("prefetchFail file=\(LibraryScanDebugLog.leaf(request.path))")
            throw VideoThumbnailError.generationFailed
        }
        return (registration.url, true, registration.token)
    }

    private static func debugName(_ error: Error) -> String {
        if let error = error as? VideoThumbnailError {
            return error.debugName
        }
        return error.localizedDescription
    }
}
