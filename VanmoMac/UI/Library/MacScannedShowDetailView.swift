import SwiftData
import SwiftUI
import VanmoCore

struct MacScannedShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    let connection: SavedConnection
    let showTitle: String

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            MacLibrarySublistHeader(
                title: showTitle,
                subtitle: "\(connection.name) · \(episodes.count) 集"
            )

            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if episodes.isEmpty {
                    Text("此剧集下没有可显示的分集")
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(episodes) { episode in
                                Button {
                                    appState.play(episode)
                                } label: {
                                    MacMediaListRow(item: episode)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .macMediaItemContextMenu(for: episode)
                            }
                        }
                        .padding(MacDesignTokens.Layout.contentPadding)
                    }
                }
            }
        }
        .background(theme.appBackground)
        .task(id: "\(connection.id)-\(showTitle)") {
            loadEpisodes()
        }
    }

    private func loadEpisodes() {
        isLoading = true
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                sortBy: [
                    SortDescriptor(\.seasonNumber),
                    SortDescriptor(\.episodeNumber),
                    SortDescriptor(\.title),
                ]
            )
            episodes = try modelContext.fetch(descriptor)
                .filter { item in
                    item.sourceConnectionId == connection.id &&
                    (item.mediaType == .tvEpisode || item.mediaType == .tvShow) &&
                    normalizedShowTitle(for: item) == showTitle
                }
                .sorted(by: episodeSortPredicate)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
