import SwiftUI
import SwiftData
import VanmoCore

struct ScannedLibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let connection: SavedConnection
    let collectionType: EmbyCollectionType

    @State private var movies: [MediaItem] = []
    @State private var shows: [ScannedShowSummary] = []
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?
    @State private var selectedMovieID: UUID?
    @State private var selectedShowKey: ScannedShowGroupKey?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 14)
    ]

    var body: some View {
        Group {
            if isLoading {
                ScannedLibraryLoadingView(title: collectionType.displayName)
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: L10n.tr("无法加载内容"),
                    message: errorMessage
                )
            } else if isEmpty {
                EmptyStateView(
                    icon: collectionType.icon,
                    title: L10n.tr("媒体库为空"),
                    message: "此连接下没有可显示的\(collectionType.displayName)"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        contentGrid
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle(collectionType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMovieID) { itemID in
            movieDestination(for: itemID)
        }
        .navigationDestination(item: $selectedShowKey) { key in
            ScannedShowDetailView(
                connection: connection,
                showTitle: key.showTitle,
                parentDirectory: key.parentDirectory
            )
        }
        .task(id: taskID) {
            loadItems()
            await refreshPostersWhileMissing()
        }
    }

    private var taskID: String {
        "\(connection.id.uuidString)-\(collectionType.rawValue)"
    }

    private var isEmpty: Bool {
        switch collectionType {
        case .movies:
            return movies.isEmpty
        case .tvshows:
            return shows.isEmpty
        case .playlists:
            return true
        }
    }

    private var loadedCount: Int {
        switch collectionType {
        case .movies:
            return movies.count
        case .tvshows:
            return shows.count
        case .playlists:
            return 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: collectionType.icon)
                    .font(.headline)
                    .foregroundStyle(Color.vanmoPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.vanmoPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(collectionType.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(connection.name) · \(loadedCount) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var contentGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 18) {
            switch collectionType {
            case .movies:
                ForEach(movies, id: \.id) { item in
                    ScannedMovieNavButton(item: item) { itemID in
                        selectedMovieID = itemID
                    } onPlay: { movie in
                        appState.play(movie)
                    }
                }
            case .tvshows:
                ForEach(shows, id: \.id) { show in
                    ScannedShowNavButton(show: show) { key in
                        selectedShowKey = key
                    }
                }
            case .playlists:
                EmptyView()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func movieDestination(for itemID: UUID) -> some View {
        if let item = resolvedMovie(for: itemID) {
            LibraryItemDestination(item: item)
        } else {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: L10n.tr("无法加载内容"),
                message: L10n.tr("找不到该条目")
            )
        }
    }

    private func resolvedMovie(for itemID: UUID) -> MediaItem? {
        movies.first(where: { $0.id == itemID }) ?? fetchMediaItem(id: itemID)
    }

    private func fetchMediaItem(id: UUID) -> MediaItem? {
        let descriptor = FetchDescriptor<MediaItem>()
        return (try? modelContext.fetch(descriptor))?.first(where: { $0.id == id })
    }

    private func loadItems() {
        if !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
            )
            let items = try modelContext.fetch(descriptor)
                .filter { $0.sourceConnectionId == connection.id }

            movies = items.filter { $0.mediaType == .movie }
            shows = ScannedShowGrouping.summaries(from: items)
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func refreshPostersWhileMissing() async {
        while !Task.isCancelled {
            let missingMoviePosters = movies.contains { $0.posterURL == nil }
            let missingShowPosters = shows.contains { $0.posterURL == nil }
            guard missingMoviePosters || missingShowPosters else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            loadItems()
        }
    }

}

private struct ScannedLibraryLoadingView: View {
    let title: String

    private let gridColumns = [
        GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.vanmoSurface)
                        .frame(width: 120, height: 22)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.vanmoSurface.opacity(0.72))
                        .frame(width: 160, height: 12)
                }
                .padding(.horizontal)

                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(0..<8, id: \.self) { _ in
                        ScannedLibraryPosterPlaceholder()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollClipDisabled()
        .redacted(reason: .placeholder)
    }
}

private struct ScannedLibraryPosterPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.vanmoSurface)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.72))
                    .frame(width: 58, height: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ScannedMovieNavButton: View {
    let item: MediaItem
    let onSelect: (UUID) -> Void
    let onPlay: (MediaItem) -> Void

    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            PosterCard(
                title: item.displayTitle,
                posterURL: item.posterURL,
                subtitle: movieSubtitle(item),
                rating: item.rating,
                progress: item.playbackProgress > 0 ? item.playbackProgress : nil
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                onPlay(item)
            } label: {
                Label(L10n.tr("播放"), systemImage: "play.fill")
            }
        }
        .id(item.id)
    }

    private func movieSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }
}

private struct ScannedShowNavButton: View {
    let show: ScannedShowSummary
    let onSelect: (ScannedShowGroupKey) -> Void

    var body: some View {
        Button {
            onSelect(show.groupKey)
        } label: {
            PosterCard(
                title: show.title,
                posterURL: show.posterURL,
                subtitle: "\(show.episodeCount) 集",
                rating: show.rating
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .id(show.id)
    }
}

#Preview {
    NavigationStack {
        ScannedLibraryListView(
            connection: SavedConnection(
                name: "NAS",
                type: .smb,
                host: "192.168.1.2",
                port: 445
            ),
            collectionType: .movies
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
