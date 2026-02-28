import SwiftUI
import SwiftData
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var tmdbMovies: [TMDbMovie] = []
    @Published private(set) var tmdbShows: [TMDbTVShow] = []
    @Published private(set) var isSearching = false
    @Published var searchScope: SearchScope = .library

    private var modelContext: ModelContext?
    private var searchTask: Task<Void, Never>?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func search() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            tmdbMovies = []
            tmdbShows = []
            return
        }

        searchTask = Task {
            isSearching = true
            defer { isSearching = false }

            switch searchScope {
            case .library:
                await searchLibrary(query)
            case .online:
                await searchOnline(query)
            }
        }
    }

    private func searchLibrary(_ query: String) async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<MediaItem>()
            let allItems = try context.fetch(descriptor)
            let lowered = query.lowercased()
            results = allItems.filter { item in
                item.title.lowercased().contains(lowered) ||
                (item.originalTitle?.lowercased().contains(lowered) ?? false) ||
                (item.director?.lowercased().contains(lowered) ?? false) ||
                item.cast.contains { $0.lowercased().contains(lowered) } ||
                item.genres.contains { $0.lowercased().contains(lowered) }
            }
        } catch {
            results = []
        }
    }

    private func searchOnline(_ query: String) async {
        do {
            async let movieResults = TMDbService.shared.searchMovie(query: query)
            async let tvResults = TMDbService.shared.searchTV(query: query)

            let (movies, shows) = try await (movieResults, tvResults)
            guard !Task.isCancelled else { return }
            tmdbMovies = movies
            tmdbShows = shows
        } catch {
            guard !Task.isCancelled else { return }
            tmdbMovies = []
            tmdbShows = []
        }
    }
}

enum SearchScope: String, CaseIterable {
    case library, online

    var displayName: String {
        switch self {
        case .library: return "媒体库"
        case .online: return "在线搜索"
        }
    }
}
