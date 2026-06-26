import SwiftUI
import SwiftData
import Kingfisher

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = LibraryViewModel()

    @State private var syncToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            HomeDesign.base
                .ignoresSafeArea()

            backdropLayer

            if viewModel.isLibraryEmpty {
                emptyState
            } else {
                ScrollView {
                    libraryContent
                }
                .scrollIndicators(.hidden)
            }

            if let message = connectionsViewModel.librarySyncMessage {
                librarySyncStatusOverlay(message: message)
                    .zIndex(3)
            }

            if let syncToastMessage {
                LibrarySyncToast(message: syncToastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.setModelContext(modelContext)
            await connectionsViewModel.loadSavedConnections()
            await viewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            Task {
                await connectionsViewModel.loadSavedConnections()
                await viewModel.refreshEmbyHome(connections: connectionsViewModel.savedConnections)
            }
        }
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await viewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
                showSyncToast("数据同步完成")
            }
        }
    }

    // MARK: - Backdrop

    /// 模糊海报背景层 + 深色渐变遮罩，对应设计稿 `Blurred poster backdrop` / `Page dark overlay`
    private var backdropLayer: some View {
        GeometryReader { geo in
            ZStack {
                if let url = heroBackdropURL {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 21)
                        .opacity(0.45)
                }

                LinearGradient(
                    stops: [
                        .init(color: HomeDesign.base.opacity(0.30), location: 0),
                        .init(color: HomeDesign.base.opacity(0.80), location: 0.42),
                        .init(color: HomeDesign.base.opacity(0.98), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var heroBackdropURL: URL? {
        if let item = viewModel.recentlyPlayed.first {
            return item.backdropURL ?? item.posterURL
        }
        return viewModel.favorites.first?.posterURL
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            headerSection
                .padding(.top, 8)

            if !viewModel.recentlyPlayed.isEmpty {
                continueWatchingSection
            }

            if viewModel.totalFavoritesCount > 0 {
                favoritesStackedSection
            }

            if hasEmbyConnectionsConfigured {
                collectionFolderSections
            }

            scannedLibrarySections
        }
        .padding(.bottom, 44)
    }

    private var hasEmbyConnectionsConfigured: Bool {
        viewModel.hasConfiguredEmbyConnections || !viewModel.orderedEmbyConnections.isEmpty
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var posterWidth: CGFloat {
        isRegularWidth ? 120 : 104
    }

    private func usesServerCollectionAPI(_ connection: SavedConnection) -> Bool {
        connection.type == .emby || connection.type == .jellyfin
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("首页")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(HomeDesign.onSurface)

                    Text("继续观看、收藏和你的全部媒体库")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeDesign.subtitle)
                }

                Spacer(minLength: 8)
//                  隐藏搜索按钮
//                searchButton
            }

            if let syncPillText {
                syncPill(syncPillText)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
    }

    private var searchButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            appState.selectedTab = .search
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HomeDesign.onSurface.opacity(0.9))
                .frame(width: 40, height: 40)
                .background(HomeDesign.glassDark, in: Circle())
                .overlay {
                    Circle().stroke(HomeDesign.cardStroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索")
    }

    private var syncPillText: String? {
        let connections = connectionsViewModel.savedConnections
        guard !connections.isEmpty else { return nil }

        let libraryCount = connections.reduce(0) { partial, connection in
            if usesServerCollectionAPI(connection) {
                return partial + viewModel.homeVisibleFolders(for: connection.id).count
            } else {
                return partial + viewModel.homeVisibleScannedFolders(for: connection.id).count
            }
        }

        let sourceCount = connections.filter(\.type.isMediaServer).count
        let prefix = sourceCount > 1 ? "\(sourceCount) 个媒体服务器已同步" : "已同步"
        let count = libraryCount > 0 ? libraryCount : connections.count
        let unit = libraryCount > 0 ? "个库" : "个源"
        return "\(prefix) · \(count) \(unit)"
    }

    private func syncPill(_ text: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(HomeDesign.syncGreen)
                .frame(width: 7, height: 7)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HomeDesign.onSurface.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(HomeDesign.syncPillFill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    // MARK: - Continue Watching

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !viewModel.recentlyPlayed.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("历史记录")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.recentlyPlayed) { item in
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                appState.play(item)
                            } label: {
                                ContinueWatchingCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Favorites

    private var favoritesStackedSection: some View {
        NavigationLink {
            FavoritesListView()
        } label: {
            HomeFavoritesCard(
                entries: viewModel.favorites.prefix(3).map(\.posterURL),
                totalCount: viewModel.totalFavoritesCount,
                movieCount: viewModel.favoriteMovieCount,
                tvShowCount: viewModel.favoriteTVShowCount
            )
        }
        .buttonStyle(FavoritesCardButtonStyle())
        .padding(.horizontal, 24)
    }

    // MARK: - Collection Folder Sections

    @ViewBuilder
    private var collectionFolderSections: some View {
        if viewModel.isLoadingEmbyHome && viewModel.serverCollectionFolders.isEmpty {
            CollectionFolderLoadingSection()
        } else {
            ForEach(viewModel.orderedEmbyConnections) { connection in
                if let errorMessage = serverErrorMessage(for: connection) {
                    serverErrorSection(serverName: connection.name, message: errorMessage)
                } else {
                    let folders = viewModel.homeVisibleFolders(for: connection.id)
                    if !folders.isEmpty {
                        collectionFolderSection(serverName: connection.name, folders: folders, connection: connection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scannedLibrarySections: some View {
        ForEach(viewModel.orderedScannedConnections) { connection in
            if let errorMessage = serverErrorMessage(for: connection) {
                serverErrorSection(serverName: connection.name, message: errorMessage)
            } else {
                let folders = viewModel.homeVisibleScannedFolders(for: connection.id)
                if !folders.isEmpty {
                    collectionFolderSection(serverName: connection.name, folders: folders, connection: connection)
                }
            }
        }
    }

    private func collectionFolderSection(
        serverName: String,
        folders: [CollectionFolder],
        connection: SavedConnection
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            serverSectionHeader(serverName: serverName, folderCount: folders.count)

            ForEach(folders) { folder in
                folderRow(folder: folder, connection: connection)
            }
        }
    }

    private func serverErrorMessage(for connection: SavedConnection) -> String? {
        viewModel.serverConnectionErrors[connection.id] ?? connectionsViewModel.connectionErrorMessage(for: connection)
    }

    private func serverErrorSection(serverName: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            serverErrorHeader(serverName: serverName)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.vanmoAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.vanmoAccent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("连接服务器失败")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HomeDesign.onSurface)

                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(HomeDesign.onSurface.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(HomeDesign.syncPillFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeDesign.cardStroke, lineWidth: 1)
            }
            .padding(.horizontal, 24)
        }
    }

    private func serverErrorHeader(serverName: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.vanmoAccent.opacity(0.14))

                Image(systemName: "server.rack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.vanmoAccent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(serverName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)
                    .lineLimit(1)

                Text("连接异常")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.72))
            }

            Spacer(minLength: 12)

            Text("失败")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.vanmoAccent)
                .frame(minWidth: 42, minHeight: 28)
                .background(Color.vanmoAccent.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 24)
    }

    private func serverSectionHeader(serverName: String, folderCount: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(HomeDesign.serverIconFill)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HomeDesign.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(serverName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)
                    .lineLimit(1)

                Text("\(folderCount) 个媒体库")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.72))
            }

            Spacer(minLength: 12)

            Text("\(folderCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HomeDesign.onSurface.opacity(0.78))
                .frame(minWidth: 42, minHeight: 28)
                .background(HomeDesign.neutralPill, in: Capsule())
        }
        .padding(.horizontal, 24)
    }

    private func folderRow(folder: CollectionFolder, connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(folder.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)
                    .lineLimit(1)

                folderTypePill(folder.collectionType)

                Spacer(minLength: 8)

                NavigationLink {
                    folderDestination(folder: folder, connection: connection)
                } label: {
                    Text("查看全部")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HomeDesign.onSurface.opacity(0.84))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(HomeDesign.neutralPill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            folderPreviewContent(folder: folder, connection: connection)
        }
    }

    @ViewBuilder
    private func folderDestination(
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        if usesServerCollectionAPI(connection) {
            CollectionFolderListView(folder: folder, connection: connection)
        } else {
            ScannedLibraryListView(connection: connection, collectionType: folder.collectionType)
        }
    }

    @ViewBuilder
    private func folderPreviewContent(
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        let previewItems = viewModel.previewItems(for: folder)
        let isLoaded = viewModel.isFolderPreviewLoaded(folder)

        if !isLoaded {
            folderPreviewSkeletonRow
        } else if !previewItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(previewItems) { item in
                        NavigationLink {
                            previewDestination(item: item, folder: folder, connection: connection)
                        } label: {
                            LibraryPosterCard(
                                title: item.displayTitle,
                                subtitle: folderPreviewSubtitle(item),
                                posterURL: item.posterURL,
                                progress: item.playbackProgress > 0 ? item.playbackProgress : nil,
                                width: posterWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func previewDestination(
        item: MediaItem,
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        if !usesServerCollectionAPI(connection), folder.collectionType == .tvshows {
            ScannedShowDetailView(connection: connection, showTitle: item.showTitle ?? item.title)
        } else {
            LibraryItemDestination(item: item)
        }
    }

    private var folderPreviewSkeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    FolderPreviewPosterPlaceholder(width: posterWidth)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
        .redacted(reason: .placeholder)
    }

    private func folderTypePill(_ type: EmbyCollectionType) -> some View {
        Text(type.displayName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HomeDesign.typePillText.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(HomeDesign.typePillFill, in: Capsule())
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    // MARK: - Sync Status / Toast

    private func librarySyncStatusOverlay(message: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SyncActivityIndicator()
                    .frame(width: 22, height: 22)

                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在同步数据")
        .accessibilityValue(message)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Empty State

    /// 对应设计稿 `LibraryHome-Empty`：顶部沿用首页标题与「未连接到媒体库」药丸，
    /// 下方区域垂直居中展示数据库图标徽章、提示文案与「添加服务器」主按钮。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            emptyHeaderSection
                .padding(.top, 8)

            LibraryEmptyContentView {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                appState.selectedTab = .connections
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyHeaderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("首页")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)

                Text("继续观看、收藏和你的全部媒体库")
                    .font(.system(size: 13))
                    .foregroundStyle(HomeDesign.subtitle)
            }

            syncPill("未连接到媒体库")
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
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

// MARK: - Design Tokens

/// 「LibraryHome」设计稿专用色板，随明暗模式自动切换：
/// 深色对应 Figma `LibraryHome-Dark`，浅色对应 `LibraryHome-Light`。
/// 蓝色强调色 `Color.vanmoAccent` 与同步绿点在两种模式下保持一致；其余表面 / 文本 / 玻璃
/// 颜色通过 `UIColor { trait in }` 动态解析，跟随环境 `colorScheme`。
private enum HomeDesign {
    /// 构造一个随明暗模式切换的动态色
    private static func dyn(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// 屏幕基底：浅色 #f3f6f9 / 深色 #050608
    static let base = dyn(
        light: rgba(0.953, 0.965, 0.976),
        dark: rgba(0x05 / 255, 0x06 / 255, 0x08 / 255)
    )
    /// 蓝色强调色 #145cff（播放钮 / 进度 / 服务器图标 / 类型药丸），明暗一致
    static let accent = Color.vanmoAccent
    /// 同步绿点 #3dd97a，明暗一致
    static let syncGreen = Color(red: 0x3D / 255, green: 0xD9 / 255, blue: 0x7A / 255)

    /// 表面上的主文本：浅色近黑 #12161d / 深色纯白。配合 `.opacity()` 表达层级
    static let onSurface = dyn(
        light: rgba(0.071, 0.086, 0.114),
        dark: .white
    )
    /// 副标题灰：浅色 #5c666f / 深色 #b2b2bf
    static let subtitle = dyn(
        light: rgba(0.36, 0.40, 0.45),
        dark: rgba(0xB2 / 255, 0xB2 / 255, 0xBF / 255)
    )

    /// 深色玻璃（搜索按钮）：浅色白玻璃 / 深色 rgba(14,15,18,0.72)
    static let glassDark = dyn(
        light: rgba(1, 1, 1, 0.6),
        dark: rgba(0x0E / 255, 0x0F / 255, 0x12 / 255, 0.72)
    )
    /// 海报卡底色：浅色 #e6ebf0 / 深色 rgba(18,19,22,0.82)
    static let posterBase = dyn(
        light: rgba(0.901, 0.921, 0.941),
        dark: rgba(0x12 / 255, 0x13 / 255, 0x16 / 255, 0.82)
    )
    /// 收藏玻璃卡填充：浅色 white@0.62 / 深色 white@0.16
    static let favoritesCardFill = dyn(
        light: rgba(1, 1, 1, 0.62),
        dark: rgba(1, 1, 1, 0.16)
    )
    /// 同步药丸填充：浅色 white@0.72 / 深色 white@0.14
    static let syncPillFill = dyn(
        light: rgba(1, 1, 1, 0.72),
        dark: rgba(1, 1, 1, 0.14)
    )
    /// 中性药丸填充（查看全部 / 数量徽标）：浅色 black@0.05 / 深色 white@0.10
    static let neutralPill = dyn(
        light: rgba(0, 0, 0, 0.05),
        dark: rgba(1, 1, 1, 0.10)
    )
    /// 服务器图标块底色：浅色蓝调 accent@0.10 / 深色 white@0.10
    static let serverIconFill = dyn(
        light: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.10),
        dark: rgba(1, 1, 1, 0.10)
    )
    /// 类型药丸填充：浅色 accent@0.12 / 深色 accent@0.18
    static let typePillFill = dyn(
        light: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.12),
        dark: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.18)
    )
    /// 类型药丸文本：浅色蓝色强调 / 深色白色
    static let typePillText = dyn(
        light: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 1),
        dark: .white
    )
    /// 卡片描边：浅色 black@0.06 / 深色 white@0.14
    static let cardStroke = dyn(
        light: rgba(0, 0, 0, 0.06),
        dark: rgba(1, 1, 1, 0.14)
    )
    /// 骨架占位填充：浅色 black@0.06 / 深色 white@0.10
    static let skeletonFill = dyn(
        light: rgba(0, 0, 0, 0.06),
        dark: rgba(1, 1, 1, 0.10)
    )

    // MARK: Empty State（对应 `LibraryHome-Empty` 设计稿）

    /// 空状态标题：浅色 #18181b / 深色纯白
    static let emptyHeading = dyn(
        light: rgba(0x18 / 255, 0x18 / 255, 0x1B / 255),
        dark: .white
    )
    /// 空状态正文灰：浅色 #71717b / 深色 #9f9fa9
    static let emptyParagraph = dyn(
        light: rgba(0x71 / 255, 0x71 / 255, 0x7B / 255),
        dark: rgba(0x9F / 255, 0x9F / 255, 0xA9 / 255)
    )
    /// 图标徽章背后的蓝色光晕：浅色 accent@0.10 / 深色 accent@0.20
    static let emptyIconGlow = dyn(
        light: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.10),
        dark: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.20)
    )
    /// 图标玻璃卡片填充：浅色 white@0.60 / 深色 white@0.05
    static let emptyIconCardFill = dyn(
        light: rgba(1, 1, 1, 0.60),
        dark: rgba(1, 1, 1, 0.05)
    )
    /// 图标玻璃卡片描边：浅色 black@0.05 / 深色 white@0.10
    static let emptyIconCardStroke = dyn(
        light: rgba(0, 0, 0, 0.05),
        dark: rgba(1, 1, 1, 0.10)
    )
    /// 数据库图标描边色：浅色 accent@0.80 / 深色 white@0.40
    static let emptyIconTint = dyn(
        light: rgba(0x14 / 255, 0x5C / 255, 0xFF / 255, 0.80),
        dark: rgba(1, 1, 1, 0.40)
    )
}

// MARK: - Empty State Content

/// 「LibraryHome-Empty」中心内容：蓝色光晕 + 旋转玻璃卡数据库图标、
/// 标题「没有找到媒体内容」、说明文案与「添加服务器」主按钮，整体水平居中。
private struct LibraryEmptyContentView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            iconBadge
                .padding(.bottom, 24)

            Text("没有找到媒体内容")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.55)
                .foregroundStyle(HomeDesign.emptyHeading)
                .padding(.bottom, 12)

            Text("您的媒体库目前空空如也。\n请先连接您的 NAS 或 Emby 服务器以同步您的媒体库内容。")
                .font(.system(size: 14))
                .foregroundStyle(HomeDesign.emptyParagraph)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .frame(width: 260)
                .padding(.bottom, 32)

            addServerButton
        }
        .padding(.horizontal, 32)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(HomeDesign.emptyIconGlow)
                .frame(width: 160, height: 160)
                .blur(radius: 40)

            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(HomeDesign.emptyIconCardFill)
                .frame(width: 160, height: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(HomeDesign.emptyIconCardStroke, lineWidth: 1)
                }
                .overlay {
                    Image("EmptyStateDatabase")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(HomeDesign.emptyIconTint)
                }
                .shadow(color: .black.opacity(0.10), radius: 12.5, x: 0, y: 20)
                .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 8)
                .rotationEffect(.degrees(3))
        }
        .frame(width: 160, height: 160)
    }

    private var addServerButton: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("添加服务器")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 20, height: 20)

                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(HomeDesign.accent, in: Capsule())
            .shadow(
                color: HomeDesign.accent.opacity(0.25),
                radius: 5,
                x: 0,
                y: 10
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加服务器")
    }
}

// MARK: - Continue Watching Card

private struct ContinueWatchingCard: View {
    let item: MediaItem
    
    private var progress: Double {
        min(max(item.playbackProgress, 0), 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                KFImage(item.backdropURL ?? item.posterURL)
                    .placeholder {
                        ZStack {
                            HomeDesign.posterBase
                            Image(systemName: item.mediaType.icon)
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 90)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.3))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(HomeDesign.accent) // Usually light blue
                                .frame(width: max(0, geo.size.width * progress), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
            .frame(width: 160, height: 90)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)
                    .lineLimit(1)
                
                Text("\(item.lastPlaybackPosition.shortDuration) · 共 \(item.duration.shortDuration)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
        }
    }
}

// MARK: - Favorites Glass Card

/// 对应设计稿 `Favorites stacked glass card`：左侧三张旋转海报，
/// 中部「收藏」标题 + 查看全部药丸，右侧收藏统计，末尾 chevron。
private struct HomeFavoritesCard: View {
    let entries: [URL?]
    let totalCount: Int
    let movieCount: Int
    let tvShowCount: Int

    var body: some View {
        HStack(spacing: 0) {
            posterStack
                .frame(width: 138, height: 84)

            Spacer(minLength: 5)
            VStack(alignment: .leading, spacing: 10) {
                Text("收藏")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HomeDesign.onSurface)

                viewAllPill
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(totalCount) 部收藏")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.76))

                Text("\(movieCount) · 电影")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.76))

                Text("\(tvShowCount) · 剧集")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeDesign.onSurface.opacity(0.76))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeDesign.onSurface.opacity(0.7))
                .padding(.leading, 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(height: 112)
        .background(HomeDesign.favoritesCardFill, in: RoundedRectangle(cornerRadius: 26))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
//        .overlay {
//            RoundedRectangle(cornerRadius: 26)
//                .stroke(HomeDesign.cardStroke, lineWidth: 1)
//        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("收藏，共 \(totalCount) 部")
    }

    private var viewAllPill: some View {
        Text("查看全部")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HomeDesign.onSurface.opacity(0.94))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(HomeDesign.neutralPill, in: Capsule())
    }

    private var posterStack: some View {
        let urls = paddedEntries
        return ZStack {
            favoritePoster(urls[0])
                .rotationEffect(.degrees(6))
                .offset(x: -34, y: 2)

            favoritePoster(urls[2])
                .rotationEffect(.degrees(-6))
                .offset(x: 34, y: -2)

            favoritePoster(urls[1])
                .offset(x: 0, y: -4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var paddedEntries: [URL?] {
        var urls = entries
        while urls.count < 3 { urls.append(nil) }
        return urls
    }

    private func favoritePoster(_ url: URL?) -> some View {
        KFImage(url)
            .placeholder {
                ZStack {
                    HomeDesign.posterBase
                    Image(systemName: "film")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HomeDesign.onSurface.opacity(0.4))
                }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(width: 58, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 8)
    }
}

// MARK: - Library Poster Card

/// 对应设计稿电影区海报卡：海报图 + 底部渐隐 + 蓝色进度条，下方标题/副标题。
private struct LibraryPosterCard: View {
    let title: String
    let subtitle: String?
    let posterURL: URL?
    let progress: Double?
    let width: CGFloat

    private var imageHeight: CGFloat {
        width * 124 / 88
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                KFImage(posterURL)
                    .placeholder {
                        ZStack {
                            HomeDesign.posterBase
                            Image(systemName: "film")
                                .font(.title3)
                                .foregroundStyle(HomeDesign.onSurface.opacity(0.4))
                        }
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: imageHeight)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 32)

                if let progress, progress > 0, progress < 1 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            HStack {
                                Capsule()
                                    .fill(HomeDesign.accent)
                                    .frame(width: max(4, geo.size.width * progress), height: 3)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .frame(width: width, height: imageHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeDesign.onSurface)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(HomeDesign.onSurface.opacity(0.62))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
        }
        .background(HomeDesign.posterBase)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Loading Skeletons

private struct FolderPreviewPosterPlaceholder: View {
    var width: CGFloat = 104

    private var imageHeight: CGFloat {
        width * 124 / 88
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(HomeDesign.skeletonFill)
                .frame(width: width, height: imageHeight)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(HomeDesign.skeletonFill)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(HomeDesign.skeletonFill.opacity(0.6))
                    .frame(width: 48, height: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
        }
        .background(HomeDesign.posterBase)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CollectionFolderLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(HomeDesign.skeletonFill)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(HomeDesign.skeletonFill)
                        .frame(width: 120, height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(HomeDesign.skeletonFill.opacity(0.6))
                        .frame(width: 86, height: 10)
                }

                Spacer()
            }
            .padding(.horizontal, 24)

            ForEach(0..<2, id: \.self) { _ in
                CollectionFolderLoadingRow()
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct CollectionFolderLoadingRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(HomeDesign.skeletonFill)
                    .frame(width: 80, height: 16)

                RoundedRectangle(cornerRadius: 12)
                    .fill(HomeDesign.skeletonFill.opacity(0.7))
                    .frame(width: 48, height: 22)

                Spacer()

                RoundedRectangle(cornerRadius: 14)
                    .fill(HomeDesign.skeletonFill.opacity(0.7))
                    .frame(width: 72, height: 28)
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        FolderPreviewPosterPlaceholder()
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Sync Indicator / Toast

private struct SyncActivityIndicator: View {
    private let cycleDuration = 1.05

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let rotation = (elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration) * 360

            ZStack {
                Circle()
                    .stroke(
                        HomeDesign.accent.opacity(0.18),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(
                        HomeDesign.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(HomeDesign.accent)
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
                .foregroundStyle(HomeDesign.accent)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeDesign.onSurface)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            HomeDesign.accent.opacity(0.28),
                            .white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: HomeDesign.accent.opacity(0.1), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

#Preview("Light") {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
