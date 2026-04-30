import SwiftUI
import SwiftData
import Kingfisher

struct FavoritesListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FavoritesListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView("加载收藏...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if viewModel.items.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: viewModel.scope)
        .animation(.smooth(duration: 0.3), value: viewModel.items.isEmpty)
        .animation(.smooth(duration: 0.3), value: viewModel.isLoading)
        .background(Color.vanmoBackground)
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.large)
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadInitialPage()
        }
        .refreshable {
            await viewModel.reload()
        }
        .onChange(of: viewModel.scope) { _, _ in
            Task { await viewModel.reload() }
        }
        .alert("加载失败", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                scopePicker
                    .padding(.horizontal)
                    .padding(.top, 8)

                ForEach(viewModel.items) { item in
                    NavigationLink {
                        MediaDetailView(item: item)
                    } label: {
                        FavoriteMediaRow(item: item) {
                            withAnimation(.smooth(duration: 0.25)) {
                                viewModel.unfavorite(item)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .onAppear {
                        Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                    }
                }

                paginationFooter
            }
            .padding(.bottom, 24)
        }
    }

    private var scopePicker: some View {
        Picker("收藏类型", selection: $viewModel.scope) {
            ForEach(FavoriteLibraryScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 16)
                Spacer()
            }
        } else if !viewModel.hasMore && !viewModel.items.isEmpty {
            Text("已加载全部收藏")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            scopePicker
                .padding(.horizontal)

            EmptyStateView(
                icon: "heart",
                title: viewModel.scope.emptyTitle,
                message: "在详情页点亮红心后，这里会显示你的收藏"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vanmoBackground)
    }
}

// MARK: - Row

private struct FavoriteMediaRow: View {
    let item: MediaItem
    let unfavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            poster
            info
            Spacer(minLength: 8)
            favoriteButton
        }
        .padding(14)
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private var poster: some View {
        KFImage(item.posterURL)
            .placeholder {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vanmoBackground)
                    .overlay {
                        Image(systemName: item.mediaType.icon)
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(width: 82, height: 122)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if let year = item.year {
                    metadataBadge("\(year)", icon: "calendar")
                }

                metadataBadge(item.mediaType.displayName, icon: item.mediaType.icon)

                if let rating = item.rating, rating > 0 {
                    metadataBadge(String(format: "%.1f", rating), icon: "star.fill")
                }
            }

            if !regionText.isEmpty {
                Text(regionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if item.duration > 0 {
                Text(item.duration.shortDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("入库 \(item.addedAt.libraryShortDate)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var favoriteButton: some View {
        Button(action: unfavorite) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(Color.vanmoBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消收藏")
    }

    private var regionText: String {
        item.originCountry
            .map(CountryMapper.displayName(for:))
            .joined(separator: " / ")
    }

    private func metadataBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.vanmoBackground)
        .clipShape(Capsule())
    }
}

// MARK: - View Model

@MainActor
private final class FavoritesListViewModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var scope: FavoriteLibraryScope = .all
    @Published var showError = false
    @Published var errorMessage = ""

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
            errorMessage = error.localizedDescription
            showError = true
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
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func unfavorite(_ item: MediaItem) {
        item.isFavorite = false
        try? modelContext?.save()
        loadedItemIDs.remove(item.persistentModelID)
        items.removeAll { $0.id == item.id }
    }

    private func fetchNextBatch(startDBOffset: Int) async throws -> FavoritesBatchResult {
        guard let context = modelContext else {
            return FavoritesBatchResult(ids: [], dbScanned: 0, reachedEnd: true)
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

            return FavoritesBatchResult(ids: collectedIds, dbScanned: dbScanned, reachedEnd: reachedEnd)
        }.value
    }

    private func replaceItems(_ newItems: [MediaItem], dbScanned: Int, reachedEnd: Bool) {
        dbOffset = dbScanned
        hasMore = !reachedEnd
        loadedItemIDs = Set(newItems.map(\.persistentModelID))
        withAnimation(.smooth(duration: 0.3)) {
            items = newItems
        }
    }

    private func appendItems(_ newItems: [MediaItem]) {
        for item in newItems where loadedItemIDs.insert(item.persistentModelID).inserted {
            items.append(item)
        }
    }
}

private struct FavoritesBatchResult: Sendable {
    let ids: [PersistentIdentifier]
    let dbScanned: Int
    let reachedEnd: Bool
}

enum FavoriteLibraryScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case movie
    case tvShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .movie: return "电影"
        case .tvShow: return "电视剧"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "还没有收藏"
        case .movie: return "还没有收藏电影"
        case .tvShow: return "还没有收藏电视剧"
        }
    }

    func matches(_ mediaType: MediaType) -> Bool {
        switch self {
        case .all:
            return mediaType == .movie || mediaType == .tvShow
        case .movie:
            return mediaType == .movie
        case .tvShow:
            return mediaType == .tvShow
        }
    }
}

private extension Date {
    var libraryShortDate: String {
        Self.libraryDateFormatter.string(from: self)
    }

    static let libraryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        FavoritesListView()
    }
    .preferredColorScheme(.dark)
}
