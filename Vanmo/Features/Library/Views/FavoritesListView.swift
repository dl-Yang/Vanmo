import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct FavoritesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FavoritesListViewModel()

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var filter4KOnly = false
    @State private var filterUnwatchedOnly = false
    @State private var isRefreshingToast = false

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
        count: 3
    )

    private var displayItems: [MediaItem] {
        viewModel.items.filter { item in
            if isSearching, !searchText.isEmpty,
               !item.title.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            if filter4KOnly && !item.is4KVideo {
                return false
            }
            if filterUnwatchedOnly && item.isWatched {
                return false
            }
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian
                .ignoresSafeArea()

            CatAmberHalo(width: 180, height: 70, opacity: 0.22)
                .padding(.top, 12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if isSearching {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                filterChipsRow
                stateContent
            }

            if isRefreshingToast {
                CatSyncToastPill(kind: .syncing, message: L10n.tr("正在同步媒体库"))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .animation(.smooth(duration: 0.28), value: viewModel.scope)
        .animation(.smooth(duration: 0.25), value: isSearching)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadInitialPage()
        }
        .onChange(of: viewModel.scope) { _, _ in
            Task { await viewModel.reload() }
        }
        .alert(L10n.tr("加载失败"), isPresented: $viewModel.showError) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Header (`16 · Favorites & Collections`)

    private var header: some View {
        HStack(spacing: 11) {
            CatBackButton { dismiss() }

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tr("收藏"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(subtitleSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            CatStretchingDivider()

            headerActionButtons
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var headerActionButtons: some View {
        HStack(spacing: 6) {
            Button {
                isSearching.toggle()
                if !isSearching { searchText = "" }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSearching ? CatDesign.accentAmber : CatDesign.textMuted)
                    .frame(width: 30, height: 30)
                    .catGlassCard(cornerRadius: CatDesign.radiusPill, amberStroke: isSearching)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearching ? L10n.tr("关闭搜索") : L10n.tr("搜索"))

            if !viewModel.items.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing.toggle()
                    }
                } label: {
                    Text(isEditing ? L10n.tr("完成") : L10n.tr("编辑"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEditing ? CatDesign.accentAmber : CatDesign.textMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill, amberStroke: isEditing)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subtitleSummary: String {
        var tags: [String] = [L10n.tr("%d 项", displayItems.count)]
        if filter4KOnly { tags.append("4K") }
        if filterUnwatchedOnly { tags.append(L10n.tr("未观看")) }
        return tags.joined(separator: " · ")
    }

    // MARK: - Search & Filter Chips

    private var searchField: some View {
        HStack(spacing: 8) {
            Image("CatSearchIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(CatDesign.accentAmber)

            TextField(L10n.tr("搜索收藏"), text: $searchText)
                .font(.system(size: 13.5))
                .foregroundStyle(CatDesign.textIvory)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .catGlassCard(cornerRadius: CatDesign.radiusPill, elevated: true, amberStroke: true)
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 10)
    }

    private var filterChipsRow: some View {
        let isAllActive = viewModel.scope == .all && !filter4KOnly && !filterUnwatchedOnly
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CatFilterChipPill(title: L10n.tr("全部"), isActive: isAllActive) {
                    viewModel.scope = .all
                    filter4KOnly = false
                    filterUnwatchedOnly = false
                }

                CatFilterChipPill(title: L10n.tr("电影"), isActive: viewModel.scope == .movie) {
                    viewModel.scope = viewModel.scope == .movie ? .all : .movie
                }

                CatFilterChipPill(title: L10n.tr("电视剧"), isActive: viewModel.scope == .tvShow) {
                    viewModel.scope = viewModel.scope == .tvShow ? .all : .tvShow
                }

                CatFilterChipPill(title: "4K", isActive: filter4KOnly) {
                    filter4KOnly.toggle()
                }

                CatFilterChipPill(title: L10n.tr("未观看"), isActive: filterUnwatchedOnly) {
                    filterUnwatchedOnly.toggle()
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    // MARK: - State Switch

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            FavoritesLoadingView()
        } else if displayItems.isEmpty {
            FavoritesEmptyView(
                hasRawItems: !viewModel.items.isEmpty,
                onResetFilters: {
                    viewModel.scope = .all
                    filter4KOnly = false
                    filterUnwatchedOnly = false
                    searchText = ""
                },
                onBrowse: { dismiss() }
            )
        } else {
            contentGrid
        }
    }

    private var contentGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(displayItems) { item in
                    posterCell(for: item)
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.bottom, 32)

            paginationFooter
        }
        .refreshable {
            isRefreshingToast = true
            await viewModel.reload()
            try? await Task.sleep(for: .milliseconds(450))
            isRefreshingToast = false
        }
    }

    @ViewBuilder
    private func posterCell(for item: MediaItem) -> some View {
        let subtitle = item.posterBadgeSubtitle
        let card = CatMediaPosterCard(item: item, subtitle: subtitle, width: nil)
            .overlay(alignment: .topLeading) {
                if isEditing {
                    deleteBadge(for: item)
                }
            }
            .overlay {
                if viewModel.isUpdatingFavorite(item) {
                    RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay { ProgressView().tint(CatDesign.glowAmber) }
                }
            }

        if isEditing {
            card
                .onAppear { Task { await viewModel.loadNextPageIfNeeded(currentItem: item) } }
        } else {
            NavigationLink {
                MediaDetailView(item: item)
            } label: {
                card
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    Task { await viewModel.unfavorite(item) }
                } label: {
                    Label(L10n.tr("取消收藏"), systemImage: "heart.slash")
                }
                .disabled(viewModel.isUpdatingFavorite(item))
            }
            .onAppear { Task { await viewModel.loadNextPageIfNeeded(currentItem: item) } }
        }
    }

    private func deleteBadge(for item: MediaItem) -> some View {
        Button {
            Task { await viewModel.unfavorite(item) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(CatDesign.dangerRed, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isUpdatingFavorite(item))
        .accessibilityLabel(L10n.tr("取消收藏"))
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .tint(CatDesign.accentAmber)
                    .padding(.vertical, 16)
                Spacer()
            }
        } else if !viewModel.hasMore && !displayItems.isEmpty {
            Text(L10n.tr("已加载全部收藏"))
                .font(.system(size: 11))
                .foregroundStyle(CatDesign.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

// MARK: - Empty / Loading

private struct FavoritesEmptyView: View {
    let hasRawItems: Bool
    let onResetFilters: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(hasRawItems ? "CatLyingYarnBall" : "CatDoorwayLookingBack")
                .resizable()
                .scaledToFit()
                .frame(width: hasRawItems ? 110 : 140, height: hasRawItems ? 56 : 160)

            Text(hasRawItems ? L10n.tr("没有匹配的媒体") : L10n.tr("还没有收藏"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Text(hasRawItems
                 ? L10n.tr("尝试调整筛选条件或搜索关键词。")
                 : L10n.tr("你标记收藏的电影和电视剧会出现在这里，方便快速访问。"))
                .font(.system(size: 13))
                .foregroundStyle(CatDesign.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button(action: hasRawItems ? onResetFilters : onBrowse) {
                Text(hasRawItems ? L10n.tr("重置筛选") : L10n.tr("浏览文件"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.accentAmber)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(CatDesign.amberTintFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FavoritesLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(CatDesign.accentAmber)
            Text(L10n.tr("正在加载收藏…"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CatDesign.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Quality Helpers

private extension MediaItem {
    var is4KVideo: Bool {
        if let videoWidth, videoWidth >= 3600 { return true }
        let source = (originalFileName ?? originalTitle ?? title).uppercased()
        return source.contains("2160") || source.contains("4K") || source.contains("UHD")
    }

    var posterBadgeSubtitle: String {
        let typeText = mediaType.displayName
        if let badge = qualityBadgeText {
            return "\(typeText) · \(badge)"
        }
        if let year {
            return "\(typeText) · \(year)"
        }
        return typeText
    }

    var qualityBadgeText: String? {
        let source = (originalFileName ?? originalTitle ?? title).uppercased()

        var resolution: String?
        if (videoWidth ?? 0) >= 3600 || source.contains("2160") || source.contains("4K") || source.contains("UHD") {
            resolution = "4K"
        } else if (videoWidth ?? 0) >= 1800 || source.contains("1080") {
            resolution = "1080p"
        } else if source.contains("720") {
            resolution = "720p"
        }

        let hdrBadge = resolvedDynamicRange.compactBadge

        switch (resolution, hdrBadge) {
        case let (res?, badge?): return "\(res) \(badge)"
        case let (res?, nil): return res
        case let (nil, badge?): return badge
        case (nil, nil): return nil
        }
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
    @Published private var updatingItemIDs: Set<PersistentIdentifier> = []

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

    func unfavorite(_ item: MediaItem) async {
        guard updatingItemIDs.insert(item.persistentModelID).inserted else { return }
        defer { updatingItemIDs.remove(item.persistentModelID) }

        do {
            try await EmbyFavoriteUpdater.setFavorite(item, isFavorite: false)
            item.isFavorite = false
            if let modelContext {
                try modelContext.save()
            }
            loadedItemIDs.remove(item.persistentModelID)
            withAnimation(.smooth(duration: 0.25)) {
                items.removeAll { $0.id == item.id }
            }
            NotificationCenter.default.post(name: .mediaFavoriteDidChange, object: item)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func isUpdatingFavorite(_ item: MediaItem) -> Bool {
        updatingItemIDs.contains(item.persistentModelID)
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
        case .all: return L10n.tr("全部")
        case .movie: return L10n.tr("电影")
        case .tvShow: return L10n.tr("电视剧")
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

#Preview("Light") {
    NavigationStack {
        FavoritesListView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        FavoritesListView()
    }
    .preferredColorScheme(.dark)
}
