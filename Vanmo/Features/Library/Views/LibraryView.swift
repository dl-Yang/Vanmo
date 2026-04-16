import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LibraryViewModel()

    @State private var showSecondFloor = false
    @State private var pullOffset: CGFloat = 0

    var body: some View {
        ZStack {
            ScrollView {
                if viewModel.isLoading && viewModel.allItems.isEmpty {
                    LoadingView("加载媒体库...")
                        .frame(minHeight: 400)
                } else if viewModel.allItems.isEmpty {
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
            await viewModel.load()
        }
        .refreshable { await viewModel.load() }
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

            if !viewModel.recentlyAdded.isEmpty {
                mediaSection("最近添加", items: viewModel.recentlyAdded)
            }

            filterModePicker

            filterContent
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
    }

    // MARK: - Filter Mode Picker

    private var filterModePicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryFilterMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.filterMode = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.subheadline)
                        Text(mode.displayName)
                            .font(.caption)
                            .fontWeight(viewModel.filterMode == mode ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        viewModel.filterMode == mode
                            ? Color.vanmoPrimary.opacity(0.15)
                            : Color.clear
                    )
                    .foregroundStyle(viewModel.filterMode == mode ? Color.vanmoPrimary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Filter Content

    @ViewBuilder
    private var filterContent: some View {
        switch viewModel.filterMode {
        case .region:
            regionContent
        case .genre:
            genreContent
        case .person:
            personContent
        }
    }

    // MARK: - Region Mode

    private var regionContent: some View {
        ForEach(viewModel.regionSections) { section in
            mediaSection(section.displayTitle, items: section.items)
        }
    }

    // MARK: - Genre Mode

    private var genreContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GenreFilterView(
                allGenres: viewModel.allGenres,
                selectedGenres: $viewModel.selectedGenres
            )

            if viewModel.viewMode == .grid {
                genreGrid
            } else {
                genreList
            }
        }
    }

    private var genreGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.genreFilteredItems) { item in
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
            }
        }
        .padding(.horizontal)
    }

    private var genreList: some View {
        LazyVStack(spacing: 1) {
            ForEach(viewModel.genreFilteredItems) { item in
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

    // MARK: - Person Mode

    private var personContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            PersonFilterView(
                persons: viewModel.topPersons,
                selectedPerson: $viewModel.selectedPerson
            )

            if let _ = viewModel.selectedPerson {
                if viewModel.viewMode == .grid {
                    personGrid
                } else {
                    personList
                }
            } else {
                Text("选择一位导演或演员查看作品")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    private var personGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.personFilteredItems) { item in
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
            }
        }
        .padding(.horizontal)
    }

    private var personList: some View {
        LazyVStack(spacing: 1) {
            ForEach(viewModel.personFilteredItems) { item in
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

    // MARK: - Shared Sections

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
                                rating: item.rating,
                                progress: showProgress ? item.playbackProgress : nil,
                                originCountry: CountryMapper.regionGroup(for: item.originCountry)
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
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
