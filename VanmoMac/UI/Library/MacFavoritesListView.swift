import SwiftData
import SwiftUI
import VanmoCore

enum MacFavoriteLibraryScope: String, CaseIterable, Identifiable {
    case all
    case movie
    case tvShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .movie: "电影"
        case .tvShow: "电视剧"
        }
    }

    func matches(_ mediaType: MediaType) -> Bool {
        switch self {
        case .all: mediaType == .movie || mediaType == .tvShow
        case .movie: mediaType == .movie
        case .tvShow: mediaType == .tvShow
        }
    }
}

struct MacFavoritesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme

    @StateObject private var viewModel = MacFavoritesListViewModel()
    @State private var searchText = ""
    @State private var isSearching = false

    private var displayItems: [MediaItem] {
        let base = MacLibrarySorting.sorted(viewModel.items, by: libraryViewModel.sortOption)
        guard isSearching, !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isSearching {
                searchField
            }

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("正在加载收藏…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty {
                    Text("还没有收藏")
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MacLibraryMediaLayout(viewMode: appState.viewMode) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: 16)],
                                spacing: 16
                            ) {
                                ForEach(displayItems) { item in
                                    MacPosterCard(
                                        title: item.title,
                                        subtitle: item.mediaType.displayName,
                                        posterURL: item.posterURL
                                    ) {
                                        appState.openDetail(item)
                                    }
                                    .onAppear {
                                        Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                                    }
                                }
                            }
                        } listContent: {
                            MacLibraryPosterList(items: displayItems, onSelect: { appState.openDetail($0) }) { item in
                                Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                            }
                        }
                        .padding(MacDesignTokens.Layout.contentPadding)

                        if viewModel.isLoadingMore {
                            ProgressView().padding()
                        }
                    }
                }
            }
        }
        .background(theme.appBackground)
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadInitialPage()
        }
        .onChange(of: viewModel.scope) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        HStack {
            Button {
                appState.backFromLibrarySubRoute()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text("收藏")
                .font(MacDesignTokens.Typography.headerTitle)

            Spacer()

            Menu {
                Picker("收藏类型", selection: $viewModel.scope) {
                    ForEach(MacFavoriteLibraryScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)

            Button {
                isSearching.toggle()
                if !isSearching { searchText = "" }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
            }
            .buttonStyle(.plain)

            MacLibraryViewControls()
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)
            TextField("搜索收藏", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.searchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.bottom, 8)
    }
}

@MainActor
final class MacFavoritesListViewModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var scope: MacFavoriteLibraryScope = .all

    private let pageSize = 24
    private var dbOffset = 0
    private var modelContext: ModelContext?
    private var loadedItemIDs: Set<PersistentIdentifier> = []

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadInitialPage() async {
        guard modelContext != nil, items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        guard modelContext != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetchNextBatch(startDBOffset: 0)
            let newItems = result.ids.compactMap { modelContext?.model(for: $0) as? MediaItem }
            replaceItems(newItems, dbScanned: result.dbScanned, reachedEnd: result.reachedEnd)
        } catch {
            items = []
        }
    }

    func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let threshold = 5
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if index >= items.count - threshold {
            await loadNextPage()
        }
    }

    func loadNextPage() async {
        guard modelContext != nil, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetchNextBatch(startDBOffset: dbOffset)
            let newItems = result.ids.compactMap { modelContext?.model(for: $0) as? MediaItem }
            appendItems(newItems)
            dbOffset += result.dbScanned
            hasMore = !result.reachedEnd
        } catch {
            hasMore = false
        }
    }

    private func fetchNextBatch(startDBOffset: Int) async throws -> MacFavoritesBatchResult {
        guard let context = modelContext else {
            return MacFavoritesBatchResult(ids: [], dbScanned: 0, reachedEnd: true)
        }

        let container = context.container
        let scope = scope
        let target = pageSize
        let batchSize = pageSize * 2

        return try await Task.detached(priority: .userInitiated) {
            let bgCtx = ModelContext(container)
            var collectedIds: [PersistentIdentifier] = []
            var dbScanned = 0
            var reachedEnd = false

            while collectedIds.count < target {
                var descriptor = FetchDescriptor<MediaItem>(
                    predicate: #Predicate<MediaItem> { item in
                        item.isFavorite
                    },
                    sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = startDBOffset + dbScanned

                let batch = try bgCtx.fetch(descriptor)
                if batch.isEmpty {
                    reachedEnd = true
                    break
                }

                dbScanned += batch.count
                let filtered = batch.filter { scope.matches($0.mediaType) }
                collectedIds.append(contentsOf: filtered.map(\.persistentModelID))

                if batch.count < batchSize {
                    reachedEnd = true
                    break
                }
            }

            return MacFavoritesBatchResult(ids: collectedIds, dbScanned: dbScanned, reachedEnd: reachedEnd)
        }.value
    }

    private func replaceItems(_ newItems: [MediaItem], dbScanned: Int, reachedEnd: Bool) {
        dbOffset = dbScanned
        hasMore = !reachedEnd
        loadedItemIDs = Set(newItems.map(\.persistentModelID))
        items = newItems
    }

    private func appendItems(_ newItems: [MediaItem]) {
        for item in newItems where loadedItemIDs.insert(item.persistentModelID).inserted {
            items.append(item)
        }
    }
}

private struct MacFavoritesBatchResult: Sendable {
    let ids: [PersistentIdentifier]
    let dbScanned: Int
    let reachedEnd: Bool
}
