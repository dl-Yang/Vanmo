import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = LibraryViewModel()

    @State private var showSecondFloor = false
    @State private var syncToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            if let syncToastMessage {
                LibrarySyncToast(message: syncToastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
            ScrollView {
                if let message = connectionsViewModel.librarySyncMessage {
                    librarySyncStatusOverlay(message: message)
                        .zIndex(3)
                }
                if viewModel.isLibraryEmpty {
                    emptyState
                } else {
                    libraryContent
                }
            }
            .background(Color.vanmoBackground)

        }
        .navigationTitle("首页")
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
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await viewModel.refreshAfterLibrarySync()
                showSyncToast("数据同步完成")
            }
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

            libraryHeader
            filtersBar

            pagedSection
        }
        .padding(.vertical)
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

    // MARK: - Library Header

    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("全部")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 34, height: 34)
                .background(Color.vanmoPrimary.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(.horizontal)
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
                    LibraryItemDestination(item: item)
                } label: {
                    PosterCard(
                        title: item.displayTitle,
                        posterURL: item.posterURL,
                        subtitle: libraryItemSubtitle(item),
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
                    LibraryItemDestination(item: item)
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
                            LibraryItemDestination(item: item)
                        } label: {
                            PosterCard(
                                title: item.displayTitle,
                                posterURL: item.posterURL,
                                subtitle: libraryItemSubtitle(item),
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

    private func libraryItemSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    @ViewBuilder
    private func itemContextMenu(_ item: MediaItem) -> some View {
        if item.mediaType == .movie || item.mediaType == .tvEpisode {
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

    private func librarySyncStatusOverlay(message: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SyncActivityIndicator()
                    .frame(width: 22, height: 22)

                Text(message)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
//        .padding(.top, 8)
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在同步数据")
        .accessibilityValue(message)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
            icon: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "film.stack",
            title: viewModel.hasActiveFilters ? "没有匹配的媒体" : "暂无媒体",
            message: viewModel.hasActiveFilters ? "尝试更改类型或地区筛选" : "添加媒体后会显示在这里"
        )
        .frame(minHeight: 240)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private func showSyncToast(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            syncToastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard syncToastMessage == message else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                syncToastMessage = nil
            }
        }
    }
}

private struct SyncActivityIndicator: View {
    private let cycleDuration = 1.05

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let rotation = (elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration) * 360

            ZStack {
                Circle()
                    .stroke(
                        Color.vanmoPrimary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(
                        Color.vanmoPrimary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.vanmoPrimary)
                    .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.85))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct LibrarySyncToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.vanmoPrimary)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.vanmoPrimary.opacity(0.28),
                            .white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.vanmoPrimary.opacity(0.1), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
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
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
