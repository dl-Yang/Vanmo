import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LibraryViewModel()

    @State private var showSecondFloor = false
    @Namespace private var sectionNamespace

    var body: some View {
        ZStack {
            ScrollView {
                if shouldShowInitialLoading {
                    LoadingView("加载媒体库...")
                        .frame(minHeight: 400)
                } else if viewModel.isLibraryEmpty {
                    emptyState
                } else {
                    libraryContent
                }
            }
            .background(Color.vanmoBackground)
        }
        .navigationTitle("Vanmo")
        .toolbar { toolbarContent }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadInitialSections()
        }
//        .refreshable {
//            await viewModel.loadInitialSections()
//        }
        .onChange(of: viewModel.sortOption) { _, _ in
            Task { await viewModel.reloadForSortChange() }
        }
        .onChange(of: viewModel.selectedGenres) { _, _ in
            Task { await viewModel.reloadForFilterChange() }
        }
        .onChange(of: viewModel.selectedRegions) { _, _ in
            Task { await viewModel.reloadForFilterChange() }
        }
        .fullScreenCover(isPresented: $showSecondFloor) {
            SecondFloorView(
                isPresented: $showSecondFloor,
                recentlyPlayed: viewModel.recentlyPlayed
            )
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if !viewModel.recentlyPlayed.isEmpty {
                secondFloorEntryHint
            }

            if viewModel.totalFavoritesCount > 0 {
                favoritesStackedSection
            }

            if !viewModel.recentlyAdded.isEmpty {
                mediaSection("最近添加", items: viewModel.recentlyAdded)
            }

            sectionTabBar
            filtersBar

            pagedSection
        }
        .padding(.vertical)
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading
            && viewModel.loadedItems.isEmpty
            && viewModel.recentlyPlayed.isEmpty
            && viewModel.recentlyAdded.isEmpty
            && viewModel.favorites.isEmpty
    }

    // MARK: - Second Floor Entry

    private var secondFloorEntryHint: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showSecondFloor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.vanmoPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("继续观看")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("\(viewModel.recentlyPlayed.count) 部影片有播放记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.vanmoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    // MARK: - Favorites

    private var favoritesStackedSection: some View {
        NavigationLink {
            FavoritesListView()
        } label: {
            FavoritesStackedCard(
                posterURLs: viewModel.favorites.prefix(5).map(\.posterURL),
                totalCount: viewModel.totalFavoritesCount,
                movieCount: viewModel.favoriteMovieCount,
                tvShowCount: viewModel.favoriteTVShowCount
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Section + Filters

    private var sectionTabBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.section.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .contentTransition(.opacity)

//                    Text("\(viewModel.loadedItems.count) 部已加载")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                        .contentTransition(.numericText())
                }

                Spacer()

                Image(systemName: viewModel.section.mediaType.icon)
                    .font(.title3)
                    .foregroundStyle(Color.vanmoPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.vanmoPrimary.opacity(0.12))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 2)

            HStack(spacing: 6) {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        Task { await viewModel.changeSection(section) }
                    } label: {
                        ZStack {
                            if viewModel.section == section {
                                Capsule()
                                    .fill(Color.vanmoPrimary)
                                    .matchedGeometryEffect(id: "sectionIndicator", in: sectionNamespace)
                            }

                            Text(section.title)
                                .font(viewModel.section == section ? .headline : .subheadline)
                                .fontWeight(viewModel.section == section ? .bold : .semibold)
                                .foregroundStyle(viewModel.section == section ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color.vanmoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.04), lineWidth: 1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .zIndex(1)
        .animation(.easeInOut(duration: 0.2), value: viewModel.section)
        .animation(.easeInOut(duration: 0.2), value: viewModel.loadedItems.count)
    }

    private var filtersBar: some View {
        VStack(spacing: 16) {
            FilterChipsRow(
                title: "类型",
                options: LibraryFilters.genres,
                selection: $viewModel.selectedGenres
            )

            FilterChipsRow(
                title: "地区",
                options: LibraryFilters.regions.map(\.title),
                selection: $viewModel.selectedRegions
            )
        }
    }

    // MARK: - Paged Content

    @ViewBuilder
    private var pagedSection: some View {
        ZStack(alignment: .top) {
            if viewModel.isReloadingSection {
                sectionLoadingPlaceholder
                    .transition(.opacity)
            } else if viewModel.loadedItems.isEmpty {
                filteredEmptyState
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                VStack(spacing: 0) {
                    if viewModel.viewMode == .grid {
                        pagedGrid
                    } else {
                        pagedList
                    }

                    paginationFooter
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
//        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.section)
//        .animation(.easeInOut(duration: 0.18), value: viewModel.isReloadingSection)
    }

    private var pagedGrid: some View {
        let items = viewModel.loadedItems
        let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                NavigationLink {
                    MediaDetailView(item: item)
                } label: {
                    PosterCard(
                        title: item.title,
                        posterURL: item.posterURL,
                        subtitle: item.year.map { "\($0)" },
                        rating: item.rating,
                        progress: item.playbackProgress > 0 ? item.playbackProgress : nil
                    )
                    .contextMenu { itemContextMenu(item) }
                }
                .buttonStyle(.plain)
                .onAppear {
                    Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                }
            }
        }
        .padding(.horizontal)
    }

    private var pagedList: some View {
        let items = viewModel.loadedItems
        return LazyVStack(spacing: 1) {
            ForEach(items) { item in
                NavigationLink {
                    MediaDetailView(item: item)
                } label: {
                    MediaListRow(item: item)
                }
                .buttonStyle(.plain)
                .contextMenu { itemContextMenu(item) }
                .onAppear {
                    Task { await viewModel.loadNextPageIfNeeded(currentItem: item) }
                }
            }
        }
    }

    @ViewBuilder
    private var sectionLoadingPlaceholder: some View {
        if viewModel.viewMode == .grid {
            let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<8, id: \.self) { _ in
                    SectionPlaceholderCard()
                }
            }
            .padding(.horizontal)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    SectionPlaceholderRow()
                }
            }
            .padding(.horizontal)
        }
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
        } else if !viewModel.hasMore && !viewModel.loadedItems.isEmpty {
            Text("已加载全部")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Shared Sections

    private func mediaSection(
        _ title: String,
        items: [MediaItem],
        showProgress: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink {
                            MediaDetailView(item: item)
                        } label: {
                            PosterCard(
                                title: item.title,
                                posterURL: item.posterURL,
                                subtitle: item.year.map { "\($0)" },
                                rating: item.rating,
                                progress: showProgress ? item.playbackProgress : nil
                            )
                            .frame(width: 130)
                            .contextMenu { itemContextMenu(item) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(_ item: MediaItem) -> some View {
        if item.mediaType != .tvShow {
            Button {
                appState.play(item)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
        }

        Button {
            viewModel.toggleFavorite(item)
        } label: {
            Label(
                item.isFavorite ? "取消收藏" : "收藏",
                systemImage: item.isFavorite ? "heart.slash" : "heart"
            )
        }

        Button {
            viewModel.markAsWatched(item)
        } label: {
            Label("标记为已看", systemImage: "checkmark.circle")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.deleteItem(item)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.viewMode = viewModel.viewMode == .grid ? .list : .grid
                }
            } label: {
                Image(systemName: viewModel.viewMode.icon)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "film.stack",
            title: "媒体库为空",
            message: "连接网络共享或添加本地文件以开始浏览你的媒体"
        ) {
            appState.selectedTab = .connections
        }
        .frame(minHeight: 500)
    }

    private var filteredEmptyState: some View {
        EmptyStateView(
            icon: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle" : viewModel.section.mediaType.icon,
            title: viewModel.hasActiveFilters ? "没有匹配的\(viewModel.section.title)" : "暂无\(viewModel.section.title)",
            message: viewModel.hasActiveFilters ? "尝试更改类型或地区筛选" : "添加媒体后会显示在这里"
        )
        .frame(minHeight: 240)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}

private struct SectionPlaceholderCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.vanmoSurface)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.75))
                    .frame(width: 48, height: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(isAnimating ? 0.48 : 1)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

private struct SectionPlaceholderRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.vanmoSurface)
                .frame(width: 60, height: 90)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.8))
                    .frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.65))
                    .frame(width: 88, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .opacity(isAnimating ? 0.48 : 1)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
