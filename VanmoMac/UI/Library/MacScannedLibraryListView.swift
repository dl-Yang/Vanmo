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
    @State private var shows: [ScannedShowSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mediaPurgeHandlerId: UUID?

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
                    ProgressView(L10n.tr("加载中..."))
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
            await refreshPostersWhileMissing()
        }
        .onAppear {
            guard mediaPurgeHandlerId == nil else { return }
            mediaPurgeHandlerId = appState.registerMediaPurgeHandler { connectionId in
                guard connectionId == connection.id else { return }
                movies = []
                shows = []
            }
        }
        .onDisappear {
            if let mediaPurgeHandlerId {
                appState.unregisterMediaPurgeHandler(mediaPurgeHandlerId)
                self.mediaPurgeHandlerId = nil
            }
        }
        .onChange(of: libraryViewModel.sortOption) { _, _ in
            movies = MacLibrarySorting.sorted(movies.filter { !$0.isDeleted }, by: libraryViewModel.sortOption)
            shows = sortedShows(shows)
        }
    }

    private func sortedShows(_ input: [ScannedShowSummary]) -> [ScannedShowSummary] {
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
        case .movies: aliveMovies.isEmpty
        case .tvshows: shows.isEmpty
        case .playlists: true
        }
    }

    private var loadedCount: Int {
        switch collectionType {
        case .movies: aliveMovies.count
        case .tvshows: shows.count
        case .playlists: 0
        }
    }

    @ViewBuilder
    private var contentGrid: some View {
        LazyVGrid(columns: columns, spacing: MacDesignTokens.Layout.posterSpacing) {
            switch collectionType {
            case .movies:
                ForEach(aliveMovies, id: \.id) { item in
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
                ForEach(shows, id: \.id) { show in
                    MacPosterCard(
                        title: show.title,
                        subtitle: "\(show.episodeCount) 集",
                        posterURL: show.posterURL
                    ) {
                        appState.openScannedShowDetail(
                            connection: connection,
                            showTitle: show.title,
                            parentDirectory: show.parentDirectory
                        )
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
            MacLibraryPosterList(items: aliveMovies, onSelect: { appState.openDetail($0) })
        case .tvshows:
            LazyVStack(spacing: 0) {
                ForEach(shows, id: \.id) { show in
                    Button {
                        appState.openScannedShowDetail(
                            connection: connection,
                            showTitle: show.title,
                            parentDirectory: show.parentDirectory
                        )
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

    private var aliveMovies: [MediaItem] {
        movies.filter { !$0.isDeleted }
    }

    private func movieSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func refreshPostersWhileMissing() async {
        while !Task.isCancelled {
            let missingMoviePosters = movies.contains { $0.posterURL == nil }
            let missingShowPosters = shows.contains { $0.posterURL == nil }
            guard missingMoviePosters || missingShowPosters else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            reloadItemsQuietly()
        }
    }

    private func reloadItemsQuietly() {
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
            shows = sortedShows(ScannedShowGrouping.summaries(from: items))
        } catch {
            errorMessage = error.localizedDescription
        }
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
            shows = sortedShows(ScannedShowGrouping.summaries(from: items))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
