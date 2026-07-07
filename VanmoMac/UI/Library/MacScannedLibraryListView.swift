import SwiftData
import SwiftUI
import VanmoCore

struct MacScannedLibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme

    let connection: SavedConnection
    let collectionType: EmbyCollectionType

    @State private var movies: [MediaItem] = []
    @State private var shows: [MacScannedShowSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: MacDesignTokens.Layout.posterSpacing)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MacLibrarySublistHeader(
                title: collectionType.displayName,
                subtitle: "\(connection.name) · \(loadedCount) 项"
            )

            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isEmpty {
                    Text("此连接下没有可显示的\(collectionType.displayName)")
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MacLibraryMediaLayout(viewMode: appState.viewMode) {
                            contentGrid
                        } listContent: {
                            contentList
                        }
                        .padding(MacDesignTokens.Layout.contentPadding)
                    }
                }
            }
        }
        .background(theme.appBackground)
        .task(id: "\(connection.id)-\(collectionType.rawValue)") {
            loadItems()
        }
        .onChange(of: libraryViewModel.sortOption) { _, _ in
            movies = MacLibrarySorting.sorted(movies, by: libraryViewModel.sortOption)
            shows = sortedShows(shows)
        }
    }

    private func sortedShows(_ input: [MacScannedShowSummary]) -> [MacScannedShowSummary] {
        switch libraryViewModel.sortOption {
        case .title:
            return input.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .rating:
            return input.sorted { lhs, rhs in
                switch (lhs.rating, rhs.rating) {
                case let (left?, right?): return left > right
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        case .addedDate, .year:
            return input.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var isEmpty: Bool {
        switch collectionType {
        case .movies: movies.isEmpty
        case .tvshows: shows.isEmpty
        case .playlists: true
        }
    }

    private var loadedCount: Int {
        switch collectionType {
        case .movies: movies.count
        case .tvshows: shows.count
        case .playlists: 0
        }
    }

    @ViewBuilder
    private var contentGrid: some View {
        LazyVGrid(columns: columns, spacing: MacDesignTokens.Layout.posterSpacing) {
            switch collectionType {
            case .movies:
                ForEach(movies) { item in
                    MacPosterCard(
                        title: item.displayTitle,
                        subtitle: movieSubtitle(item),
                        posterURL: item.posterURL
                    ) {
                        appState.openDetail(item)
                    }
                    .macMediaItemContextMenu(for: item)
                }
            case .tvshows:
                ForEach(shows) { show in
                    MacPosterCard(
                        title: show.title,
                        subtitle: "\(show.episodeCount) 集",
                        posterURL: show.posterURL
                    ) {
                        appState.openScannedShowDetail(connection: connection, showTitle: show.title)
                    }
                }
            case .playlists:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        switch collectionType {
        case .movies:
            MacLibraryPosterList(items: movies, onSelect: { appState.openDetail($0) })
        case .tvshows:
            LazyVStack(spacing: 0) {
                ForEach(shows) { show in
                    Button {
                        appState.openScannedShowDetail(connection: connection, showTitle: show.title)
                    } label: {
                        HStack(spacing: 12) {
                            MacRemoteImage(url: show.posterURL)
                                .frame(width: 60, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(show.episodeCount) 集")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .playlists:
            EmptyView()
        }
    }

    private func movieSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func loadItems() {
        isLoading = true
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
            )
            let items = try modelContext.fetch(descriptor)
                .filter { $0.sourceConnectionId == connection.id }

            movies = MacLibrarySorting.sorted(
                items.filter { $0.mediaType == .movie },
                by: libraryViewModel.sortOption
            )
            shows = sortedShows(makeShowSummaries(from: items))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func makeShowSummaries(from items: [MediaItem]) -> [MacScannedShowSummary] {
        let episodeItems = items.filter { $0.mediaType == .tvEpisode || $0.mediaType == .tvShow }
        let grouped = Dictionary(grouping: episodeItems) { normalizedShowTitle(for: $0) }

        return grouped.compactMap { title, episodes in
            guard let representative = episodes.sorted(by: episodeSortPredicate).first else { return nil }
            return MacScannedShowSummary(
                title: title,
                episodeCount: episodes.count,
                posterURL: representative.posterURL,
                rating: representative.rating
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func normalizedShowTitle(for item: MediaItem) -> String {
        let rawTitle = item.showTitle ?? item.title
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? item.displayTitle : trimmed
    }

    private func episodeSortPredicate(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let lhsSeason = lhs.seasonNumber ?? Int.max
        let rhsSeason = rhs.seasonNumber ?? Int.max
        if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode { return lhsEpisode < rhsEpisode }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

struct MacScannedShowSummary: Identifiable {
    let title: String
    let episodeCount: Int
    let posterURL: URL?
    let rating: Double?

    var id: String { title }
}
