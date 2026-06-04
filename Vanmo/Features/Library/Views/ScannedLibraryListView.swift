import SwiftUI
import SwiftData

struct ScannedLibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let connection: SavedConnection
    let collectionType: EmbyCollectionType

    @State private var movies: [MediaItem] = []
    @State private var shows: [ScannedShowSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                    title: "无法加载内容",
                    message: errorMessage
                )
            } else if isEmpty {
                EmptyStateView(
                    icon: collectionType.icon,
                    title: "媒体库为空",
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
        .task(id: taskID) {
            loadItems()
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
                ForEach(movies) { item in
                    NavigationLink {
                        LibraryItemDestination(item: item)
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
                    .contextMenu {
                        Button {
                            appState.play(item)
                        } label: {
                            Label("播放", systemImage: "play.fill")
                        }
                    }
                }
            case .tvshows:
                ForEach(shows) { show in
                    NavigationLink {
                        ScannedShowDetailView(connection: connection, showTitle: show.title)
                    } label: {
                        PosterCard(
                            title: show.title,
                            posterURL: show.posterURL,
                            subtitle: "\(show.episodeCount) 集",
                            rating: show.rating
                        )
                    }
                    .buttonStyle(.plain)
                }
            case .playlists:
                EmptyView()
            }
        }
        .padding(.horizontal)
    }

    private func movieSubtitle(_ item: MediaItem) -> String? {
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

            movies = items.filter { $0.mediaType == .movie }
            shows = makeShowSummaries(from: items)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func makeShowSummaries(from items: [MediaItem]) -> [ScannedShowSummary] {
        let episodeItems = items.filter { $0.mediaType == .tvEpisode || $0.mediaType == .tvShow }
        let grouped = Dictionary(grouping: episodeItems) { item in
            normalizedShowTitle(for: item)
        }

        return grouped.compactMap { title, episodes in
            guard let representative = episodes.sorted(by: episodeSortPredicate).first else { return nil }
            return ScannedShowSummary(
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
        if lhsSeason != rhsSeason {
            return lhsSeason < rhsSeason
        }

        let lhsEpisode = lhs.episodeNumber ?? Int.max
        let rhsEpisode = rhs.episodeNumber ?? Int.max
        if lhsEpisode != rhsEpisode {
            return lhsEpisode < rhsEpisode
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private struct ScannedShowSummary: Identifiable {
    let title: String
    let episodeCount: Int
    let posterURL: URL?
    let rating: Double?

    var id: String { title }
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
