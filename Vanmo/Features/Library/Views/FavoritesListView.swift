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

    private var displayItems: [MediaItem] {
        guard isSearching, !searchText.isEmpty else { return viewModel.items }
        return viewModel.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            FavoritesDesign.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isSearching {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                stateContent
            }
        }
        .animation(.smooth(duration: 0.3), value: viewModel.scope)
        .animation(.smooth(duration: 0.3), value: viewModel.items.isEmpty)
        .animation(.smooth(duration: 0.3), value: viewModel.isLoading)
        .animation(.smooth(duration: 0.25), value: isSearching)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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

    // MARK: - State Switch

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            FavoritesLoadingView()
                .transition(.opacity)
        } else if viewModel.items.isEmpty {
            FavoritesEmptyView { dismiss() }
                .transition(.opacity)
        } else {
            content
                .transition(.opacity)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FavoritesDesign.textPrimary)
                        .frame(width: 24, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Text("收藏")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.53)
                    .foregroundStyle(FavoritesDesign.textPrimary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                filterButton
                searchButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 17)
        .background(
            FavoritesDesign.screenBackground.opacity(0.92)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FavoritesDesign.separator)
                .frame(height: 0.5)
        }
    }

    private var filterButton: some View {
        Menu {
            Picker("收藏类型", selection: $viewModel.scope) {
                ForEach(FavoriteLibraryScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FavoritesDesign.accent)
                .frame(width: 32, height: 32)
                .background(FavoritesDesign.accentSoft, in: Circle())
        }
        .accessibilityLabel("筛选")
    }

    private var searchButton: some View {
        Button {
            isSearching.toggle()
            if !isSearching { searchText = "" }
        } label: {
            Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(FavoritesDesign.textPrimary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSearching ? "关闭搜索" : "搜索")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(FavoritesDesign.textSecondary)
            TextField("搜索收藏", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(FavoritesDesign.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FavoritesDesign.fieldBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(FavoritesDesign.separator, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Content Grid

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                itemsCountRow
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                LazyVGrid(columns: FavoritesDesign.gridColumns, spacing: 16) {
                    ForEach(displayItems) { item in
                        posterCell(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                paginationFooter
            }
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func posterCell(for item: MediaItem) -> some View {
        let card = FavoritePosterCard(
            item: item,
            isEditing: isEditing,
            isUpdating: viewModel.isUpdatingFavorite(item)
        ) {
            await viewModel.unfavorite(item)
        }

        if isEditing {
            card
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .onAppear {
                    Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                }
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
                    Label("取消收藏", systemImage: "heart.slash")
                }
                .disabled(viewModel.isUpdatingFavorite(item))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .onAppear {
                Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
            }
        }
    }

    private var itemsCountRow: some View {
        HStack {
            Text("共 \(displayItems.count) 项")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(FavoritesDesign.textSecondary)

            Spacer()

            Button {
                isEditing.toggle()
            } label: {
                Text(isEditing ? "完成" : "编辑")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FavoritesDesign.editBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .tint(FavoritesDesign.accent)
                    .padding(.vertical, 16)
                Spacer()
            }
        } else if !viewModel.hasMore && !viewModel.items.isEmpty {
            Text("已加载全部收藏")
                .font(.system(size: 12))
                .foregroundStyle(FavoritesDesign.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Poster Card

private struct FavoritePosterCard: View {
    let item: MediaItem
    let isEditing: Bool
    let isUpdating: Bool
    let unfavorite: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
            info
        }
    }

    private var poster: some View {
        ZStack {
            Rectangle()
                .fill(FavoritesDesign.cardPlaceholder)
            KFImage(item.posterURL)
                .placeholder {
                    Image(systemName: item.mediaType.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(FavoritesDesign.textSecondary.opacity(0.5))
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
            Rectangle()
                .fill(Color.black.opacity(0.1))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(159.0 / 238.5, contentMode: .fit)
        .clipped()
        .overlay(alignment: .topTrailing) { yearBadge }
        .overlay(alignment: .bottomLeading) { qualityBadge }
        .overlay(alignment: .topLeading) { deleteBadge }
        .overlay { updatingOverlay }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private var yearBadge: some View {
        if let year = item.year {
            Text(String(year))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
    }

    @ViewBuilder
    private var qualityBadge: some View {
        if let text = item.qualityBadgeText {
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 1)
                .padding(8)
        }
    }

    @ViewBuilder
    private var deleteBadge: some View {
        if isEditing {
            Button {
                Task { await unfavorite() }
            } label: {
                ZStack {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                .background(Color.red, in: Circle())
                .overlay { Circle().stroke(.white, lineWidth: 1.5) }
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
            .padding(6)
            .accessibilityLabel("取消收藏")
        }
    }

    @ViewBuilder
    private var updatingOverlay: some View {
        if isUpdating {
            Color.black.opacity(0.24)
                .allowsHitTesting(false)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(FavoritesDesign.textPrimary)
                .lineLimit(1)

            Text(item.mediaType.displayName)
                .font(.system(size: 12))
                .foregroundStyle(FavoritesDesign.textSecondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - Empty State

private struct FavoritesEmptyView: View {
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(FavoritesDesign.accentCircleSoft)
                    .frame(width: 80, height: 80)
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(FavoritesDesign.accent)
            }
            .padding(.bottom, 24)

            Text("还没有收藏")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.45)
                .foregroundStyle(FavoritesDesign.textPrimary)
                .padding(.bottom, 8)

            Text("你标记收藏的电影和电视剧会出现在这里，方便快速访问。")
                .font(.system(size: 14))
                .tracking(-0.15)
                .foregroundStyle(FavoritesDesign.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(width: 250)
                .padding(.bottom, 32)

            Button(action: onBrowse) {
                Text("浏览文件")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.31)
                    .foregroundStyle(FavoritesDesign.browseButtonForeground)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(FavoritesDesign.browseButtonBackground, in: Capsule())
                    .shadow(color: FavoritesDesign.browseButtonShadow, radius: 5, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading State

private struct FavoritesLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            FavoritesSpinner()
            Text("正在加载收藏…")
                .font(.system(size: 14, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(FavoritesDesign.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FavoritesSpinner: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(FavoritesDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 32, height: 32)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
            .accessibilityLabel("加载中")
    }
}

// MARK: - Design Tokens (Light / Dark)

private enum FavoritesDesign {
    static let screenBackground = dynamic(light: Color(hex: "#F4F4F5")!, dark: .black)
    static let separator = dynamic(light: Color(hex: "#E4E4E7")!.opacity(0.6),
                                   dark: Color(hex: "#27272A")!.opacity(0.5))
    static let textPrimary = dynamic(light: Color(hex: "#18181B")!, dark: .white)
    static let textSecondary = dynamic(light: Color(hex: "#71717B")!, dark: Color(hex: "#9F9FA9")!)
    static let accent = Color.vanmoAccent
    /// 筛选按钮圆形底色
    static let accentSoft = Color.vanmoAccent.opacity(0.12)
    /// 空状态 80pt 圆形底色（深色下更淡）
    static let accentCircleSoft = Color.vanmoAccent.opacity(0.10)
    static let editBlue = Color.vanmoAccent
    static let cardPlaceholder = dynamic(light: Color(hex: "#E4E4E7")!, dark: Color(hex: "#27272A")!)
    static let fieldBackground = dynamic(light: .white, dark: Color(hex: "#27272A")!)
    /// 「浏览文件」按钮在深色下反相为白底黑字
    static let browseButtonBackground = dynamic(light: Color(hex: "#18181B")!, dark: .white)
    static let browseButtonForeground = dynamic(light: .white, dark: .black)
    static let browseButtonShadow = dynamic(light: .black.opacity(0.1), dark: .white.opacity(0.12))

    static let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Quality Badge Helper

private extension MediaItem {
    var qualityBadgeText: String? {
        let source = (originalFileName ?? originalTitle ?? title).uppercased()

        var resolution: String?
        if source.contains("2160") || source.contains("4K") || source.contains("UHD") {
            resolution = "4K"
        } else if source.contains("1080") {
            resolution = "HD"
        } else if source.contains("720") {
            resolution = "HD"
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
