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
        case .all: L10n.tr("全部")
        case .movie: L10n.tr("电影")
        case .tvShow: L10n.tr("电视剧")
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
    @State private var mediaPurgeHandlerId: UUID?

    private var displayItems: [MediaItem] {
        let alive = viewModel.items.filter { !$0.isDeleted }
        let base = MacLibrarySorting.sorted(alive, by: libraryViewModel.sortOption)
        guard isSearching, !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacCatAmbientHalo()
                .offset(x: -70, y: -30)

            VStack(spacing: 0) {
                header

                if isSearching {
                    searchField
                }

                content
            }
        }
        .background(theme.appBackground)
        .task(id: appState.favoriteChangeNonce) {
            viewModel.setModelContext(modelContext)
            await viewModel.reload()
        }
        .onAppear {
            guard mediaPurgeHandlerId == nil else { return }
            mediaPurgeHandlerId = appState.registerMediaPurgeHandler { connectionId in
                viewModel.removeItems(forConnectionId: connectionId)
            }
        }
        .onDisappear {
            if let mediaPurgeHandlerId {
                appState.unregisterMediaPurgeHandler(mediaPurgeHandlerId)
                self.mediaPurgeHandlerId = nil
            }
        }
        .onChange(of: viewModel.scope) { _, _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: appState.mediaPurgeEvent?.nonce) { _, _ in
            guard let connectionId = appState.mediaPurgeEvent?.connectionId else { return }
            viewModel.removeItems(forConnectionId: connectionId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView(L10n.tr("正在加载收藏…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Image("MacNavFavoritesPaw")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(theme.accentAmber.opacity(0.7))
                Text(L10n.tr("还没有收藏"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(L10n.tr("你标记收藏的电影和电视剧会显示在这里。"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                MacLibraryMediaLayout(viewMode: appState.viewMode) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: MacDesignTokens.Layout.posterSpacing)],
                        spacing: MacDesignTokens.Layout.posterSpacing
                    ) {
                        ForEach(displayItems) { item in
                            MacPosterCard(
                                title: item.displayTitle,
                                subtitle: itemSubtitle(item),
                                posterURL: item.posterURL
                            ) {
                                appState.openDetail(item)
                            }
                            .macMediaItemContextMenu(for: item)
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
                .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
                .padding(.top, 14)
                .padding(.bottom, 32)

                if viewModel.isLoadingMore {
                    ProgressView().padding()
                }
            }
        }
    }

    private func itemSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.tr("收藏"))
                .font(MacDesignTokens.Typography.headerTitle)
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 6) {
                ForEach(MacFavoriteLibraryScope.allCases) { scope in
                    let isSelected = viewModel.scope == scope
                    Button {
                        viewModel.scope = scope
                    } label: {
                        Text(scope.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(
                                isSelected ? theme.amberTintFill : theme.surfacePill,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(isSelected ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 8)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isSearching.toggle()
                    if !isSearching { searchText = "" }
                }
            } label: {
                Image("MacSearchCat")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSearching ? theme.accentAmber : theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(isSearching ? theme.amberTintFill : theme.surfaceGlass, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(isSearching ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.9)
                    }
            }
            .buttonStyle(.plain)
            .help(isSearching ? L10n.tr("关闭搜索") : L10n.tr("搜索收藏"))

            MacLibraryViewControls()
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image("MacSearchCat")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(theme.accentAmber)

            TextField(L10n.tr("搜索收藏"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.primaryText)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(theme.searchBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(theme.strokeAmber, lineWidth: 0.9)
        }
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

    func reload() async {
        guard modelContext != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetchNextBatch(startDBOffset: 0)
            let newItems = result.ids.compactMap { id -> MediaItem? in
                guard let item = modelContext?.model(for: id) as? MediaItem, !item.isDeleted else { return nil }
                return item
            }
            replaceItems(newItems, dbScanned: result.dbScanned, reachedEnd: result.reachedEnd)
        } catch {
            items = []
        }
    }

    func removeItems(forConnectionId connectionId: UUID) {
        let remaining = items.filter { item in
            guard !item.isDeleted else { return false }
            return item.sourceConnectionId != connectionId
        }
        guard remaining.count != items.count else { return }
        items = remaining
        loadedItemIDs = Set(remaining.map(\.persistentModelID))
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
            let newItems = result.ids.compactMap { id -> MediaItem? in
                guard let item = modelContext?.model(for: id) as? MediaItem, !item.isDeleted else { return nil }
                return item
            }
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
