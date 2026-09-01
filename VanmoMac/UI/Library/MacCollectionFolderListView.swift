import SwiftUI
import VanmoCore

struct MacCollectionFolderListView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme

    let folder: CollectionFolder
    let connection: SavedConnection

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var startIndex = 0
    @State private var totalRecordCount = 0
    @State private var errorMessage: String?
    @State private var hasLoadedOnce = false
    @State private var mediaPurgeHandlerId: UUID?

    private let pageSize = 50
    private let columns = [
        GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: MacDesignTokens.Layout.posterSpacing)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MacLibrarySublistHeader(
                title: folder.name,
                subtitle: "\(connection.name) · \(folder.collectionType.displayName)"
            )

            Group {
                if isLoading {
                    ProgressView(L10n.tr("加载中..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    Text(L10n.tr("此媒体库下没有可显示的项目"))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MacLibraryMediaLayout(viewMode: appState.viewMode) {
                            LazyVGrid(columns: columns, spacing: MacDesignTokens.Layout.posterSpacing) {
                                ForEach(sortedItems) { item in
                                    MacPosterCard(
                                        title: item.displayTitle,
                                        subtitle: listItemSubtitle(item),
                                        posterURL: item.posterURL
                                    ) {
                                        openItem(item)
                                    }
                                    .onAppear {
                                        Task { await loadNextPageIfNeeded(currentItem: item) }
                                    }
                                }
                            }
                        } listContent: {
                            MacLibraryPosterList(items: sortedItems, onSelect: openItem) { item in
                                Task { await loadNextPageIfNeeded(currentItem: item) }
                            }
                        }
                        .padding(MacDesignTokens.Layout.contentPadding)

                        if isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
        .background(theme.appBackground)
        .task(id: folder.id) {
            guard !hasLoadedOnce else { return }
            await loadInitialPage()
        }
        .onAppear {
            guard mediaPurgeHandlerId == nil else { return }
            mediaPurgeHandlerId = appState.registerMediaPurgeHandler { connectionId in
                guard connectionId == connection.id else { return }
                items = []
            }
        }
        .onDisappear {
            if let mediaPurgeHandlerId {
                appState.unregisterMediaPurgeHandler(mediaPurgeHandlerId)
                self.mediaPurgeHandlerId = nil
            }
        }
    }

    private var sortedItems: [MediaItem] {
        MacLibrarySorting.sorted(items.filter { !$0.isDeleted }, by: libraryViewModel.sortOption)
    }

    private func openItem(_ item: MediaItem) {
        switch item.mediaType {
        case .folder, .collectionFolder, .season, .boxSet:
            if item.serverId != nil {
                appState.openEmbyFolderBrowse(container: item)
            } else {
                appState.openDetail(item)
            }
        default:
            appState.openDetail(item)
        }
    }

    private func listItemSubtitle(_ item: MediaItem) -> String {
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
        totalRecordCount = 0
        hasMore = true

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                collectionType: folder.collectionType,
                startIndex: 0,
                pageSize: pageSize
            )
            items = page.items.map { serverItem in
                let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                item.sourceConnectionId = connection.id
                return item
            }
            startIndex = page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = startIndex < page.totalRecordCount
            hasLoadedOnce = true
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
                collectionType: folder.collectionType,
                startIndex: startIndex,
                pageSize: pageSize
            )
            let newItems = page.items.map { serverItem in
                let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                item.sourceConnectionId = connection.id
                return item
            }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: newItems.filter { !existingIDs.contains($0.id) })
            startIndex += page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = !page.items.isEmpty && startIndex < page.totalRecordCount
        } catch {
            hasMore = false
        }
    }
}
