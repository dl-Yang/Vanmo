import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LibraryViewModel()

    var body: some View {
        ScrollView {
            if viewModel.isLoading && viewModel.movies.isEmpty {
                LoadingView("加载媒体库...")
                    .frame(minHeight: 400)
            } else if viewModel.filteredItems.isEmpty && viewModel.recentlyPlayed.isEmpty {
                emptyState
            } else {
                libraryContent
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle("Vanmo")
        .toolbar { toolbarContent }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.load()
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if !viewModel.recentlyPlayed.isEmpty {
                mediaSection("继续观看", items: viewModel.recentlyPlayed, showProgress: true)
            }

            if !viewModel.recentlyAdded.isEmpty {
                mediaSection("最近添加", items: viewModel.recentlyAdded)
            }

            categoryPicker

            if viewModel.viewMode == .grid {
                mediaGrid
            } else {
                mediaList
            }
        }
        .padding(.vertical)
    }

    // MARK: - Sections

    private func mediaSection(_ title: String, items: [MediaItem], showProgress: Bool = false) -> some View {
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
                                progress: showProgress ? item.playbackProgress : nil
                            )
                            .frame(width: 130)
                            .contextMenu { itemContextMenu(item) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectedCategory = category
                        }
                    } label: {
                        Text(category.displayName)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedCategory == category ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedCategory == category
                                    ? Color.vanmoPrimary
                                    : Color.vanmoSurface
                            )
                            .foregroundStyle(
                                viewModel.selectedCategory == category ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Grid & List

    private var mediaGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.filteredItems) { item in
                NavigationLink {
                    MediaDetailView(item: item)
                } label: {
                    PosterCard(
                        title: item.title,
                        posterURL: item.posterURL,
                        subtitle: item.year.map { "\($0)" },
                        progress: item.playbackProgress > 0 ? item.playbackProgress : nil
                    )
                    .contextMenu { itemContextMenu(item) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var mediaList: some View {
        LazyVStack(spacing: 1) {
            ForEach(viewModel.filteredItems) { item in
                NavigationLink {
                    MediaDetailView(item: item)
                } label: {
                    MediaListRow(item: item)
                }
                .buttonStyle(.plain)
                .contextMenu { itemContextMenu(item) }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(_ item: MediaItem) -> some View {
        Button {
            appState.play(item)
        } label: {
            Label("播放", systemImage: "play.fill")
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
            appState.selectedTab = .browse
        }
        .frame(minHeight: 500)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
