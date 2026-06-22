import Foundation

struct OnlineSubtitleResult: Identifiable, Equatable {
    let id: String
    let title: String
    let language: String?
    let format: SubtitleFormat
    let downloadURL: URL
    let provider: String
}

protocol OnlineSubtitleProvider {
    var name: String { get }
    func search(for item: MediaItem) async throws -> [OnlineSubtitleResult]
}

actor OnlineSubtitleService {
    static let shared = OnlineSubtitleService()

    private var providers: [OnlineSubtitleProvider] = []

    func register(_ provider: OnlineSubtitleProvider) {
        providers.append(provider)
    }

    func search(for item: MediaItem) async throws -> [OnlineSubtitleResult] {
        var results: [OnlineSubtitleResult] = []
        for provider in providers {
            results.append(contentsOf: try await provider.search(for: item))
        }
        return results
    }

    func cacheDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("OnlineSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
