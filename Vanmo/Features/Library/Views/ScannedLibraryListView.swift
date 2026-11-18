import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct ScannedLibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            CatAmberHalo(width: 180, height: 70, opacity: 0.22)
                .padding(.top, 12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                stateContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
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

    private var header: some View {
        HStack(spacing: 11) {
            CatBackButton { dismiss() }

            VStack(alignment: .leading, spacing: 1) {
                Text(collectionType.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text("\(connection.name) · \(L10n.tr("%d 项", loadedCount))")
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            CatStretchingDivider()
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            ScannedLibraryLoadingView(gridColumns: gridColumns)
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
                message: L10n.tr("此连接下没有可显示的 %@", collectionType.displayName)
            )
        } else {
            ScrollView {
                contentGrid
                    .padding(.bottom, 28)
            }
        }
    }

    private var taskID: String {
        "\(connection.id.uuidString)-\(collectionType.rawValue)"
    }

    private var isEmpty: Bool {
        switch collectionType {
        case .movies: return movies.isEmpty
        case .tvshows: return shows.isEmpty
        case .playlists: return true
        }
    }

    private var loadedCount: Int {
        switch collectionType {
        case .movies: return movies.count
        case .tvshows: return shows.count
        case .playlists: return 0
        }
    }

    private var contentGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            switch collectionType {
            case .movies:
                ForEach(movies, id: \.id) { item in
                    Button {
                        selectedMovieID = item.id
                    } label: {
                        CatMediaPosterCard(item: item, subtitle: movieSubtitle(item), width: nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            appState.play(item)
                        } label: {
                            Label(L10n.tr("播放"), systemImage: "play.fill")
                        }
                    }
                    .id(item.id)
                }
            case .tvshows:
                ForEach(shows, id: \.id) { show in
                    Button {
                        selectedShowKey = show.groupKey
                    } label: {
                        ScannedShowPosterCard(show: show)
                    }
                    .buttonStyle(.plain)
                    .id(show.id)
                }
            case .playlists:
                EmptyView()
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    private func movieSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
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

private struct ScannedShowPosterCard: View {
    let show: ScannedShowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .overlay {
                        KFImage(show.posterURL)
                            .placeholder {
                                ZStack {
                                    CatDesign.mediaPlaceholder
                                    Image(systemName: "tv")
                                        .font(.title3)
                                        .foregroundStyle(CatDesign.textMuted.opacity(0.45))
                                }
                            }
                            .fade(duration: 0.25)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()

                LinearGradient(
                    colors: [.clear, CatDesign.catSilhouette.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
            }
            .aspectRatio(106.0 / 150.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(L10n.tr("%d 集", show.episodeCount))
                    .font(.system(size: 10))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }
        }
    }
}

private struct ScannedLibraryLoadingView: View {
    let gridColumns: [GridItem]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                            .fill(CatDesign.surfacePill)
                            .aspectRatio(106.0 / 150.0, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CatDesign.surfacePill)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CatDesign.surfacePill.opacity(0.6))
                            .frame(width: 58, height: 10)
                    }
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
        }
        .redacted(reason: .placeholder)
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
