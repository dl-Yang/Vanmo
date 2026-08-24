import SwiftData
import SwiftUI
import VanmoCore

/// 全部观看记录页面：侧边栏 History 入口，按最近播放时间倒序展示全部历史。
struct MacHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    @StateObject private var viewModel = MacHistoryListViewModel()
    @State private var mediaPurgeHandlerId: UUID?

    private var displayItems: [MediaItem] {
        viewModel.items.filter { !$0.isDeleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MacDesignTokens.Layout.trafficLightsTopInset + 5)
            header
            content
        }
        .background(theme.appBackground)
        // 首次挂载与每次播放结束（进度落库）后刷新。
        .task(id: appState.watchHistoryChangeNonce) {
            viewModel.setModelContext(modelContext)
            await viewModel.reload()
        }
        // 兜底：详情页「标记已看」等未广播 nonce 的变更，切回本页时补一次刷新。
        .onChange(of: appState.contentRoute) { _, newRoute in
            guard newRoute == .libraryHistory else { return }
            Task { await viewModel.reload() }
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
        .onChange(of: appState.mediaPurgeEvent?.nonce) { _, _ in
            guard let connectionId = appState.mediaPurgeEvent?.connectionId else { return }
            viewModel.removeItems(forConnectionId: connectionId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("正在加载历史记录…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
            Text("还没有观看记录")
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
                                title: item.displayTitle,
                                subtitle: subtitle(for: item),
                                posterURL: item.posterURL
                            ) {
                                play(item)
                            }
                            .macMediaItemContextMenu(for: item)
                            .onAppear {
                                Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                            }
                        }
                    }
                } listContent: {
                    MacLibraryPosterList(items: displayItems, onSelect: { play($0) }) { item in
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

    private var header: some View {
        HStack {
            Text("历史记录")
                .font(MacDesignTokens.Typography.headerTitle)

            Spacer()

            // 历史记录固定按最近播放倒序，不提供排序菜单。
            MacLibraryViewControls(showsSortMenu: false)
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
    }

    /// 历史记录条目语义为「继续观看」：点击直接从上次位置继续播放。
    private func play(_ item: MediaItem) {
        appState.play(item, from: item.lastPlaybackPosition)
    }

    private func subtitle(for item: MediaItem) -> String {
        if item.lastPlaybackPosition > 0, item.duration > 0 {
            return MacFormatters.remainingDuration(position: item.lastPlaybackPosition, total: item.duration)
        }
        if let year = item.year {
            return String(year)
        }
        return item.mediaType.displayName
    }
}

@MainActor
final class MacHistoryListViewModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true

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
        } catch is CancellationError {
            // task(id:) 因 nonce 变化取消上一次加载时保留旧数据，避免列表闪烁/被清空。
            return
        } catch {
            items = []
        }
    }

    /// 删除连接前同步剔除历史记录中的 MediaItem。
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

    private func fetchNextBatch(startDBOffset: Int) async throws -> MacHistoryBatchResult {
        guard let context = modelContext else {
            return MacHistoryBatchResult(ids: [], dbScanned: 0, reachedEnd: true)
        }

        let container = context.container
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
                        item.lastPlayedAt != nil
                    },
                    sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = startDBOffset + dbScanned

                let batch = try bgCtx.fetch(descriptor)
                if batch.isEmpty {
                    reachedEnd = true
                    break
                }

                dbScanned += batch.count
                collectedIds.append(contentsOf: batch.map(\.persistentModelID))

                if batch.count < batchSize {
                    reachedEnd = true
                    break
                }
            }

            return MacHistoryBatchResult(ids: collectedIds, dbScanned: dbScanned, reachedEnd: reachedEnd)
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

private struct MacHistoryBatchResult: Sendable {
    let ids: [PersistentIdentifier]
    let dbScanned: Int
    let reachedEnd: Bool
}

#Preview {
    MacHistoryListView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .macTheme(.light)
}
