import SwiftUI
import Kingfisher
import VanmoCore

/// CollectionFolder 二级列表页：展示媒体库内的 Movie / Series / Video。
struct CollectionFolderListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let folder: CollectionFolder
    let connection: SavedConnection

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var startIndex = 0
    @State private var totalRecordCount = 0
    @State private var errorMessage: String?
    @State private var loadMoreErrorMessage: String?
    @State private var hasLoadedOnce = false
    @State private var selectedFilter: CollectionFilter = .all

    private let pageSize = 50
    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
        count: 3
    )

    private var filteredItems: [MediaItem] {
        items.filter { selectedFilter.matches($0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            CatAmberHalo(width: 180, height: 70, opacity: 0.22)
                .padding(.top, 12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navHeader
                filterChipsRow
                stateContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .task(id: folder.id) {
            guard !hasLoadedOnce else { return }
            await loadInitialPage()
        }
    }

    private var navHeader: some View {
        HStack(spacing: 11) {
            CatBackButton { dismiss() }

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            CatStretchingDivider()
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var subtitleLine: String {
        let countText = totalRecordCount > 0 ? L10n.tr("%d 项", totalRecordCount) : L10n.tr("%d 项", filteredItems.count)
        return "\(connection.name) · \(countText)"
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CollectionFilter.allCases) { filter in
                    CatFilterChipPill(title: filter.title, isActive: selectedFilter == filter) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            CollectionFolderListLoadingView(gridColumns: gridColumns)
        } else if let errorMessage {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: L10n.tr("无法加载内容"),
                message: errorMessage
            )
        } else if filteredItems.isEmpty {
            EmptyStateView(
                icon: folder.collectionType.icon,
                title: L10n.tr("媒体库为空"),
                message: L10n.tr("此媒体库下没有可显示的项目")
            )
        } else {
            ScrollView {
                mediaGrid
                loadStateFooter
            }
            .refreshable {
                await loadInitialPage()
            }
        }
    }

    private var mediaGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(filteredItems) { item in
                NavigationLink {
                    LibraryItemDestination(item: item)
                } label: {
                    CatMediaPosterCard(item: item, subtitle: listItemSubtitle(item), width: nil)
                }
                .buttonStyle(.plain)
                .contextMenu { listItemContextMenu(item) }
                .onAppear {
                    Task { await loadNextPageIfNeeded(currentItem: item) }
                }
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var loadStateFooter: some View {
        if loadMoreErrorMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                Text(L10n.tr("加载中断"))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(CatDesign.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(CatDesign.accentAmber)
                Text(L10n.tr("继续加载..."))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CatDesign.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if !hasMore {
            Text(loadedSummaryText)
                .font(.caption)
                .foregroundStyle(CatDesign.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private var loadedSummaryText: String {
        if totalRecordCount > 0 {
            return "已加载全部 \(totalRecordCount) 项"
        }
        return L10n.tr("已加载全部")
    }

    @ViewBuilder
    private func listItemContextMenu(_ item: MediaItem) -> some View {
        if item.mediaType == .movie || item.mediaType == .tvEpisode {
            Button {
                appState.play(item)
            } label: {
                Label(L10n.tr("播放"), systemImage: "play.fill")
            }
        }
    }

    private func listItemSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func loadInitialPage() async {
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        items = []
        startIndex = 0
        totalRecordCount = 0
        hasMore = true

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                collectionType: folder.collectionType,
                startIndex: 0,
                pageSize: pageSize
            )
            items = page.items.map { serverItem in
                let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                item.sourceConnectionId = connection.id
                return item
            }
            startIndex = page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = startIndex < page.totalRecordCount
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let threshold = 5
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard index >= items.count - threshold else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                collectionType: folder.collectionType,
                startIndex: startIndex,
                pageSize: pageSize
            )
            let newItems = page.items.map { serverItem in
                let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
                item.sourceConnectionId = connection.id
                return item
            }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: newItems.filter { !existingIDs.contains($0.id) })
            startIndex += page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = !page.items.isEmpty && startIndex < page.totalRecordCount
        } catch {
            loadMoreErrorMessage = error.localizedDescription
            hasMore = false
        }
    }
}

private enum CollectionFilter: String, CaseIterable, Identifiable {
    case all, movies, tvShows, fourK, unwatched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.tr("全部")
        case .movies: return L10n.tr("电影")
        case .tvShows: return L10n.tr("电视剧")
        case .fourK: return "4K"
        case .unwatched: return L10n.tr("未观看")
        }
    }

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .movies: return item.mediaType == .movie
        case .tvShows: return item.mediaType == .tvShow
        case .fourK:
            if (item.videoWidth ?? 0) >= 3600 { return true }
            let text = (item.originalFileName ?? item.title).uppercased()
            return text.contains("2160") || text.contains("4K") || text.contains("UHD")
        case .unwatched:
            return !item.isWatched
        }
    }
}

private struct CollectionFolderListLoadingView: View {
    let gridColumns: [GridItem]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                            .fill(CatDesign.surfacePill)
                            .aspectRatio(106.0 / 150.0, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CatDesign.surfacePill)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CatDesign.surfacePill.opacity(0.6))
                            .frame(width: 58, height: 10)
                    }
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
        }
        .redacted(reason: .placeholder)
    }
}

#Preview {
    NavigationStack {
        CollectionFolderListView(
            folder: CollectionFolder(
                id: "preview",
                name: "电影 - 华语",
                collectionType: .movies,
                posterURL: nil,
                serverConnectionId: UUID(),
                serverConnectionName: "Emby"
            ),
            connection: SavedConnection(
                name: "Emby",
                type: .emby,
                host: "192.168.1.1",
                port: 8096
            )
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
