import SwiftUI

/// CollectionFolder 二级列表页：展示媒体库内的 Movie / Series / Video。
struct CollectionFolderListView: View {
    @EnvironmentObject private var appState: AppState

    let folder: CollectionFolder
    let connection: SavedConnection

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var startIndex = 0
    @State private var errorMessage: String?

    private let pageSize = 50

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法加载内容",
                    message: errorMessage
                )
            } else if items.isEmpty {
                EmptyStateView(
                    icon: folder.collectionType.icon,
                    title: "媒体库为空",
                    message: "此媒体库下没有可显示的项目"
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)],
                        spacing: 16
                    ) {
                        ForEach(items) { item in
                            NavigationLink {
                                LibraryItemDestination(item: item)
                            } label: {
                                PosterCard(
                                    title: item.displayTitle,
                                    posterURL: item.posterURL,
                                    subtitle: listItemSubtitle(item),
                                    rating: item.rating,
                                    progress: item.playbackProgress > 0 ? item.playbackProgress : nil
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                listItemContextMenu(item)
                            }
                            .onAppear {
                                Task { await loadNextPageIfNeeded(currentItem: item) }
                            }
                        }
                    }
                    .padding()

                    if isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 16)
                    } else if !hasMore {
                        Text("已加载全部")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .task(id: folder.id) {
            await loadInitialPage()
        }
    }

    @ViewBuilder
    private func listItemContextMenu(_ item: MediaItem) -> some View {
        if item.mediaType == .movie || item.mediaType == .tvEpisode {
            Button {
                appState.play(item)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
        }
    }

    private func listItemSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func loadInitialPage() async {
        isLoading = true
        errorMessage = nil
        items = []
        startIndex = 0
        hasMore = true

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                startIndex: 0,
                pageSize: pageSize
            )
            items = page.items.map { $0.makeMediaItem() }
            startIndex = page.items.count
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let threshold = 5
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard index >= items.count - threshold else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                startIndex: startIndex,
                pageSize: pageSize
            )
            let newItems = page.items.map { $0.makeMediaItem() }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: newItems.filter { !existingIDs.contains($0.id) })
            startIndex += page.items.count
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CollectionFolderListView(
            folder: CollectionFolder(
                id: "preview",
                name: "电影 - 华语",
                collectionType: .movies,
                posterURL: nil,
                serverConnectionId: UUID(),
                serverConnectionName: "Emby"
            ),
            connection: SavedConnection(
                name: "Emby",
                type: .emby,
                host: "192.168.1.1",
                port: 8096
            )
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
