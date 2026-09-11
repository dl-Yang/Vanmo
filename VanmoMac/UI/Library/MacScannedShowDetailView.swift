import SwiftData
import SwiftUI
import VanmoCore

struct MacScannedShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    let connection: SavedConnection
    let showTitle: String
    let parentDirectory: String

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var mediaPurgeHandlerId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            MacLibrarySublistHeader(
                title: showTitle,
                subtitle: "\(connection.name) · \(aliveEpisodes.count) 集"
            )

            Group {
                if isLoading {
                    ProgressView(L10n.tr("加载中..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if aliveEpisodes.isEmpty {
                    Text(L10n.tr("此剧集下没有可显示的分集"))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(aliveEpisodes) { episode in
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
        .task(id: "\(connection.id)-\(parentDirectory)-\(showTitle)") {
            loadEpisodes()
        }
        .onAppear {
            guard mediaPurgeHandlerId == nil else { return }
            mediaPurgeHandlerId = appState.registerMediaPurgeHandler { connectionId in
                guard connectionId == connection.id else { return }
                episodes = []
            }
        }
        .onDisappear {
            if let mediaPurgeHandlerId {
                appState.unregisterMediaPurgeHandler(mediaPurgeHandlerId)
                self.mediaPurgeHandlerId = nil
            }
        }
    }

    private var aliveEpisodes: [MediaItem] {
        episodes.filter { !$0.isDeleted }
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
            episodes = ScannedShowGrouping.episodes(
                from: try modelContext.fetch(descriptor),
                connectionId: connection.id,
                showTitle: showTitle,
                parentDirectory: parentDirectory
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
