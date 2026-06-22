import SwiftUI
import SwiftData

struct ScannedShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let connection: SavedConnection
    let showTitle: String

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ScannedShowLoadingView()
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法加载分集",
                    message: errorMessage
                )
            } else if episodes.isEmpty {
                EmptyStateView(
                    icon: "tv",
                    title: "暂无分集",
                    message: "此剧集下没有可显示的分集"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        header

                        ForEach(episodes) { episode in
                            Button {
                                appState.play(episode)
                            } label: {
                                MediaListRow(item: episode)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle(showTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskID) {
            loadEpisodes()
        }
    }

    private var taskID: String {
        "\(connection.id.uuidString)-\(showTitle)"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.headline)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 34, height: 34)
                .background(Color.vanmoPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(showTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)

                Text("\(connection.name) · \(episodes.count) 集")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func loadEpisodes() {
        if !hasLoadedOnce {
            isLoading = true
        }
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
            hasLoadedOnce = true
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

private struct ScannedShowLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.vanmoSurface)
                        .frame(width: 60, height: 90)

                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.vanmoSurface)
                            .frame(height: 13)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.vanmoSurface.opacity(0.72))
                            .frame(width: 150, height: 10)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.vanmoSurface.opacity(0.58))
                            .frame(width: 90, height: 10)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    NavigationStack {
        ScannedShowDetailView(
            connection: SavedConnection(
                name: "NAS",
                type: .smb,
                host: "192.168.1.2",
                port: 445
            ),
            showTitle: "示例剧集"
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
