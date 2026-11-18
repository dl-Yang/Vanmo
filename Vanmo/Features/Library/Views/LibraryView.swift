import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = LibraryViewModel()

    @State private var syncToastMessage: String?
    @State private var selectedMediaItemID: UUID?
    @State private var showAllHistory = false

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian
                .ignoresSafeArea()

            if !viewModel.isLibraryEmpty {
                ambientBackdropLayer
            } else {
                emptyAmbientHalo
            }

            mainContentLayer

            syncToastOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedMediaItemID) { itemID in
            libraryNavigationDestination(for: itemID)
        }
        .navigationDestination(isPresented: $showAllHistory) {
            LibraryContinueWatchingListView(
                items: viewModel.recentlyPlayed,
                onPlay: { appState.play($0) },
                onInspect: { selectedMediaItemID = $0.id }
            )
        }
        .task {
            viewModel.setModelContext(modelContext)
            await connectionsViewModel.loadSavedConnections()
            await viewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
            viewModel.refreshFolderBookmarks(connections: connectionsViewModel.savedConnections)
        }
        .onChange(of: appState.favoriteChangeCount) { _, _ in
            Task {
                await viewModel.refreshFavoritesAfterChange(connections: connectionsViewModel.savedConnections)
            }
        }
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await viewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
                showSyncToast(L10n.tr("数据同步完成"))
            }
        }
        .onChange(of: appState.selectedTab) { _, newValue in
            guard newValue == .library else { return }
            viewModel.refreshFolderBookmarks(connections: connectionsViewModel.savedConnections)
            Task {
                await viewModel.refreshFavoritesAfterChange(connections: connectionsViewModel.savedConnections)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionLocalMediaWillDelete)) { notification in
            guard let connectionId = notification.object as? UUID else { return }
            viewModel.removeItems(forConnectionId: connectionId)
        }
#if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DownloadHeroWalkFixtures.openDetailNotification)) { notification in
            guard let itemID = notification.object as? UUID else { return }
            selectedMediaItemID = itemID
        }
#endif
    }

    @ViewBuilder
    private var mainContentLayer: some View {
        if viewModel.isLibraryEmpty {
            emptyState
        } else {
            ScrollView {
                libraryContent
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.refreshEmbyHome(connections: connectionsViewModel.savedConnections)
            }
        }
    }

    @ViewBuilder
    private var syncToastOverlay: some View {
        if let syncToastMessage {
            CatSyncToastPill(kind: .synced, message: syncToastMessage)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
        }
    }

    // MARK: - Ambient Backdrop (`01 · Home Media Library` & `15 · Empty Library State`)

    private var ambientBackdropLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                heroBackdropFill(width: geo.size.width)

                LinearGradient(
                    stops: [
                        .init(color: CatDesign.bgObsidian.opacity(0.25), location: 0),
                        .init(color: CatDesign.bgObsidian.opacity(0.90), location: 0.65),
                        .init(color: CatDesign.bgObsidian, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 420)

                CatAmberHalo(width: 170, height: 110, opacity: 0.20)
                    .padding(.top, 86)
                    .padding(.trailing, 30)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var emptyAmbientHalo: some View {
        VStack {
            Spacer().frame(height: 180)
            CatAmberHalo(width: 260, height: 240, opacity: 0.24)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var heroBackdropURL: URL? {
        if let hero = viewModel.featuredHeroItem {
            return hero.backdropURL ?? hero.posterURL
        }
        return viewModel.recentlyPlayed.first?.backdropURL ?? viewModel.favorites.first?.posterURL
    }

    private func heroBackdropFill(width: CGFloat) -> some View {
        Group {
            if let url = heroBackdropURL {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("DefaultHeroBackdrop")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: 380)
        .clipped()
        .blur(radius: 20)
        .opacity(0.24)
    }

    // MARK: - Library Content (`01 · Home Media Library`)

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            topSearchAndStatusBar
                .padding(.top, 10)

            if let heroItem = viewModel.featuredHeroItem {
                heroSection(item: heroItem)
                    .padding(.top, 10)
            }

            if !viewModel.recentlyPlayed.isEmpty {
                continueWatchingSection
            }

            if viewModel.totalFavoritesCount > 0 {
                favoritesStackedSection
            }

            if !viewModel.folderBookmarks.isEmpty {
                folderBookmarksSection
            }

            if hasEmbyConnectionsConfigured {
                collectionFolderSections
            }

            scannedLibrarySections
        }
        .padding(.bottom, 110)
    }

    private var hasEmbyConnectionsConfigured: Bool {
        viewModel.hasConfiguredEmbyConnections || !viewModel.orderedEmbyConnections.isEmpty
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var posterWidth: CGFloat {
        isRegularWidth ? 120 : 106
    }

    private func usesServerCollectionAPI(_ connection: SavedConnection) -> Bool {
        connection.type == .emby || connection.type == .jellyfin
    }

    // MARK: - Top Bar

    private var topSearchAndStatusBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.selectedTab = .search
            } label: {
                HStack(spacing: 9) {
                    Image("CatSearchIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(CatDesign.textMuted)

                    Text(L10n.tr("搜索媒体库、文件..."))
                        .font(.system(size: 13))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .catGlassCard(cornerRadius: CatDesign.radiusPill)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("搜索"))

            serverStatusPill
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    private var syncedServerCount: Int {
        connectionsViewModel.savedConnections.filter { connection in
            guard serverErrorMessage(for: connection) == nil else { return false }
            if usesServerCollectionAPI(connection) {
                return !viewModel.homeVisibleFolders(for: connection.id).isEmpty
            }
            return !viewModel.homeVisibleScannedFolders(for: connection.id).isEmpty
        }.count
    }

    private var serverStatusPill: some View {
        let isSyncing = connectionsViewModel.librarySyncMessage != nil
        let isActive = isSyncing || syncedServerCount > 0
        let labelText = isSyncing
            ? L10n.tr("同步中")
            : L10n.tr("%d 已同步", syncedServerCount)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await viewModel.refreshEmbyHome(connections: connectionsViewModel.savedConnections) }
        } label: {
            HStack(spacing: 8) {
                if isActive {
                    Image("CatEyeStatus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 8)
                        .shadow(color: CatDesign.glowAmber.opacity(0.7), radius: 2.5)
                } else {
                    Circle()
                        .fill(CatDesign.textDim)
                        .frame(width: 6, height: 6)
                }

                Text(labelText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .catGlassCard(cornerRadius: CatDesign.radiusPill, amberStroke: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(labelText)
    }

    // MARK: - Hero Section (`664:74`)

    private func heroSection(item: MediaItem) -> some View {
        let sourceLabel = viewModel.connectionName(for: item) ?? L10n.tr("本地库")
        let featuredText = "\(L10n.tr("精选")) · \(sourceLabel.uppercased())"

        return Button {
            selectedMediaItemID = item.id
        } label: {
            CatHeroCard(
                item: item,
                featuredTag: featuredText
            )
        }
        .buttonStyle(CatScaleButtonStyle())
        .padding(.top, 32)
        .overlay(alignment: .topTrailing) {
            Image("CatHeroLounging")
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 64)
                .offset(x: -14, y: -4)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    // MARK: - Continue Watching (`664:95`)

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatSectionHeader(title: L10n.tr("继续观看"), showSeeAll: true) {
                showAllHistory = true
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(viewModel.recentlyPlayed) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            appState.play(item)
                        } label: {
                            CatContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                selectedMediaItemID = item.id
                            } label: {
                                Label(L10n.tr("查看详情"), systemImage: "info.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Favorites Stacked Section

    private var favoritesStackedSection: some View {
        NavigationLink {
            FavoritesListView()
        } label: {
            CatHomeFavoritesCard(
                entries: viewModel.favorites.prefix(3).map(\.posterURL),
                totalCount: viewModel.totalFavoritesCount,
                movieCount: viewModel.favoriteMovieCount,
                tvShowCount: viewModel.favoriteTVShowCount
            )
        }
        .buttonStyle(CatScaleButtonStyle())
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    // MARK: - Folder Bookmarks

    private var folderBookmarksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatSectionHeader(
                title: L10n.tr("文件夹书签"),
                badgeText: "\(viewModel.folderBookmarks.count)",
                showSeeAll: false
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.folderBookmarks) { bookmark in
                        Button {
                            openFolderBookmark(bookmark)
                        } label: {
                            CatFolderBookmarkCard(bookmark: bookmark)
                        }
                        .buttonStyle(CatScaleButtonStyle())
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func openFolderBookmark(_ bookmark: FolderBookmark) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        connectionsViewModel.requestOpenFolderBookmark(bookmark)
        appState.selectedTab = .connections
    }

    // MARK: - Collection & Scanned Sections (`664:150`)

    @ViewBuilder
    private var collectionFolderSections: some View {
        if viewModel.isLoadingEmbyHome && viewModel.serverCollectionFolders.isEmpty {
            CatCollectionLoadingSection(posterWidth: posterWidth)
        } else {
            ForEach(viewModel.orderedEmbyConnections) { connection in
                if let errorMessage = serverErrorMessage(for: connection) {
                    serverErrorSection(connection: connection, message: errorMessage)
                } else {
                    let folders = viewModel.homeVisibleFolders(for: connection.id)
                    if !folders.isEmpty {
                        collectionFolderSection(folders: folders, connection: connection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scannedLibrarySections: some View {
        ForEach(viewModel.orderedScannedConnections) { connection in
            if let errorMessage = serverErrorMessage(for: connection) {
                serverErrorSection(connection: connection, message: errorMessage)
            } else {
                let folders = viewModel.homeVisibleScannedFolders(for: connection.id)
                if !folders.isEmpty {
                    collectionFolderSection(folders: folders, connection: connection)
                }
            }
        }
    }

    private func collectionFolderSection(
        folders: [CollectionFolder],
        connection: SavedConnection
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(folders) { folder in
                folderRow(folder: folder, connection: connection)
            }
        }
    }

    private func serverErrorMessage(for connection: SavedConnection) -> String? {
        viewModel.serverConnectionErrors[connection.id] ?? connectionsViewModel.connectionErrorMessage(for: connection)
    }

    private func serverErrorSection(connection: SavedConnection, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image("CatEyeStatus")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 9)
                .padding(8)
                .background(CatDesign.amberTintFill, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(connection.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Text(L10n.tr("连接异常"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CatDesign.amberTintFill, in: Capsule())
                }

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(CatDesign.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .catGlassCard(cornerRadius: CatDesign.radiusSquircleMd, amberStroke: true)
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    private func folderRow(folder: CollectionFolder, connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(folder.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(connection.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CatDesign.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CatDesign.surfacePill, in: Capsule())
                    .lineLimit(1)

                Spacer(minLength: 6)

                CatStretchingDivider()

                NavigationLink {
                    folderDestination(folder: folder, connection: connection)
                } label: {
                    Text(L10n.tr("查看全部"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CatDesign.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CatDesign.surfacePill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CatDesign.horizontalMargin)

            folderPreviewContent(folder: folder)
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
    private func folderPreviewContent(folder: CollectionFolder) -> some View {
        let previewItems = viewModel.previewItems(for: folder)
        let isLoaded = viewModel.isFolderPreviewLoaded(folder)

        if !isLoaded {
            folderPreviewSkeletonRow
        } else if !previewItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(previewItems, id: \.id) { item in
                        Button {
                            selectedMediaItemID = item.id
                        } label: {
                            CatMediaPosterCard(
                                item: item,
                                subtitle: folderPreviewSubtitle(item),
                                width: posterWidth
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var folderPreviewSkeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    CatPosterPlaceholder(width: posterWidth)
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
        }
        .redacted(reason: .placeholder)
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func libraryNavigationDestination(for itemID: UUID) -> some View {
        if let resolved = resolvePreviewNavigation(id: itemID) {
            previewDestination(item: resolved.item, folder: resolved.folder, connection: resolved.connection)
        } else if let item = fetchMediaItem(id: itemID) {
            LibraryItemDestination(item: item)
        } else {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: L10n.tr("无法加载内容"),
                message: L10n.tr("找不到该条目")
            )
        }
    }

    private func resolvePreviewNavigation(
        id: UUID
    ) -> (item: MediaItem, folder: CollectionFolder, connection: SavedConnection)? {
        for connection in connectionsViewModel.savedConnections {
            let folders = usesServerCollectionAPI(connection)
                ? viewModel.homeVisibleFolders(for: connection.id)
                : viewModel.homeVisibleScannedFolders(for: connection.id)
            for folder in folders {
                if let item = viewModel.previewItems(for: folder).first(where: { $0.id == id }) {
                    return (item, folder, connection)
                }
            }
        }
        return nil
    }

    private func fetchMediaItem(id: UUID) -> MediaItem? {
        let descriptor = FetchDescriptor<MediaItem>()
        return (try? modelContext.fetch(descriptor))?.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func previewDestination(
        item: MediaItem,
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        if !usesServerCollectionAPI(connection), folder.collectionType == .tvshows {
            ScannedShowDetailView(
                connection: connection,
                showTitle: item.showTitle ?? item.title,
                parentDirectory: ScannedShowGrouping.parentDirectory(for: item)
            )
        } else {
            LibraryItemDestination(item: item)
        }
    }

    // MARK: - Empty State (`15 · Empty Library State`)

    private var emptyState: some View {
        VStack(spacing: 0) {
            emptyHeader
                .padding(.top, 12)

            Spacer()

            CatEmptyLibraryCanvas {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.selectedTab = .connections
            }

            Spacer()
            Spacer().frame(height: 76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHeader: some View {
        HStack {
            Text(L10n.tr("媒体库"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(CatDesign.textDim)
                    .frame(width: 6, height: 6)

                Text(L10n.tr("没有来源"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CatDesign.textMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .catGlassCard(cornerRadius: CatDesign.radiusPill)
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
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

// MARK: - Subviews

private struct CatEmptyLibraryCanvas: View {
    let connectAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image("CatDoorwayLookingBack")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 184)

            VStack(spacing: 8) {
                Text(L10n.tr("你的媒体库还是空的"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .multilineTextAlignment(.center)

                Text(L10n.tr("连接 Emby、Jellyfin、Plex 或 SMB 服务器，或挂载本地文件夹即可开始观看。"))
                    .font(.system(size: 13))
                    .foregroundStyle(CatDesign.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(action: connectAction) {
                HStack(spacing: 8) {
                    Image("CatAddSourceIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text(L10n.tr("连接服务器或文件夹"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CatDesign.glowAmber)
                }
                .padding(.leading, 20)
                .padding(.trailing, 22)
                .frame(height: 50)
                .background {
                    Capsule()
                        .fill(CatDesign.catSilhouette.opacity(0.88))
                }
                .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 1.15))
                .shadow(color: CatDesign.amberGlowShadow, radius: 14, y: 8)
            }
            .buttonStyle(CatScaleButtonStyle())
            .accessibilityLabel(L10n.tr("连接服务器或文件夹"))
        }
        .padding(.horizontal, 24)
    }
}

private struct CatHeroCard: View {
    let item: MediaItem
    let featuredTag: String

    private var metaLine: String {
        var parts: [String] = []
        if let year = item.year { parts.append("\(year)") }
        if let genre = item.genres.first { parts.append(genre) }
        if item.duration > 0 { parts.append(item.duration.shortDuration) }
        if let dr = item.dynamicRange, !dr.isEmpty { parts.append(dr) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork

            LinearGradient(
                stops: [
                    .init(color: CatDesign.catSilhouette.opacity(0.13), location: 0),
                    .init(color: CatDesign.catSilhouette.opacity(0.50), location: 0.45),
                    .init(color: CatDesign.catSilhouette.opacity(0.95), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                featuredPill
                Spacer(minLength: 0)
                heroFooter
            }
            .padding(16)
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CatDesign.radiusSquircleLg, style: .continuous)
                .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
    }

    private var heroArtwork: some View {
        GeometryReader { proxy in
            KFImage(item.backdropURL ?? item.posterURL)
                .placeholder {
                    ZStack {
                        CatDesign.mediaPlaceholder
                        Image(systemName: item.mediaType.icon)
                            .font(.largeTitle)
                            .foregroundStyle(CatDesign.Cinema.textMuted.opacity(0.35))
                    }
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }

    private var featuredPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CatDesign.glowAmber)
                .frame(width: 6, height: 6)

            Text(featuredTag)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.Cinema.textIvory)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.75))
    }

    private var heroFooter: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CatDesign.Cinema.textIvory)
                    .lineLimit(1)

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CatDesign.Cinema.textMuted)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let rating = item.rating, rating > 0 {
                        Text(String(format: "★ %.1f", rating))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CatDesign.glowAmber)

                        Text(L10n.tr("· 点击查看详情"))
                            .font(.system(size: 11))
                            .foregroundStyle(CatDesign.Cinema.textMuted)
                            .lineLimit(1)
                    } else {
                        Text(L10n.tr("点击查看详情"))
                            .font(.system(size: 11))
                            .foregroundStyle(CatDesign.Cinema.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(L10n.tr("详情 ›"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CatDesign.glowAmber)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 1))
        }
    }
}

private struct CatSectionHeader: View {
    let title: String
    var badgeText: String? = nil
    var showSeeAll: Bool = true
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(1)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CatDesign.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CatDesign.surfacePill, in: Capsule())
            }

            Spacer(minLength: 6)

            CatStretchingDivider()

            if showSeeAll, let onSeeAll {
                Button(action: onSeeAll) {
                    Text(L10n.tr("查看全部"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CatDesign.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CatDesign.surfacePill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }
}

private struct CatContinueWatchingCard: View {
    let item: MediaItem

    private var progress: Double {
        min(max(item.playbackProgress, 0), 1)
    }

    private var subtitleLine: String {
        if item.isWatched {
            return item.duration > 0
                ? L10n.tr("已看完 · %@", item.duration.shortDuration)
                : L10n.tr("已看完")
        }
        if item.duration > 0 {
            return "\(item.lastPlaybackPosition.shortDuration) · \(item.duration.shortDuration)"
        }
        return item.lastPlaybackPosition.shortDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                KFImage(item.backdropURL ?? item.posterURL)
                    .placeholder {
                        ZStack {
                            CatDesign.mediaPlaceholder
                            Image(systemName: item.mediaType.icon)
                                .font(.title3)
                                .foregroundStyle(CatDesign.textMuted.opacity(0.45))
                        }
                    }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 164, height: 92)
                    .clipped()

                LinearGradient(
                    colors: [.clear, CatDesign.catSilhouette.opacity(0.91)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 56)

                if item.isWatched {
                    HStack {
                        Spacer()
                        CatWatchedEarBadge(padding: 4)
                            .padding(7)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else if progress > 0 {
                    CatPawProgressBar(progress: progress, trackColor: Color.white.opacity(0.22))
                        .padding(.horizontal, 9)
                        .padding(.bottom, 7)
                }
            }
            .frame(width: 164, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }
            .frame(width: 164, alignment: .leading)
        }
    }
}

struct CatMediaPosterCard: View {
    let item: MediaItem
    let subtitle: String?
    var width: CGFloat? = 106

    private var progress: Double? {
        item.playbackProgress > 0 ? item.playbackProgress : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            posterFrame
            infoBlock
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous))
    }

    private var posterFrame: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay {
                    KFImage(item.posterURL)
                        .placeholder {
                            ZStack {
                                CatDesign.mediaPlaceholder
                                Image(systemName: item.mediaType.icon)
                                    .font(.title3)
                                    .foregroundStyle(CatDesign.textMuted.opacity(0.45))
                            }
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()

            LinearGradient(
                colors: [.clear, CatDesign.catSilhouette.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)

            if item.isWatched {
                HStack {
                    Spacer()
                    CatWatchedEarBadge(padding: 3)
                        .padding(7)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else if let progress, progress > 0, progress < 1 {
                CatPawProgressBar(
                    progress: progress,
                    trackHeight: 3,
                    showPawDot: false,
                    trackColor: Color.white.opacity(0.22)
                )
                .padding(.horizontal, 7)
                .padding(.bottom, 8)
            }
        }
        .aspectRatio(106.0 / 150.0, contentMode: .fit)
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
        )
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }
        }
    }
}

private struct CatHomeFavoritesCard: View {
    let entries: [URL?]
    let totalCount: Int
    let movieCount: Int
    let tvShowCount: Int

    var body: some View {
        HStack(spacing: 12) {
            posterStack
                .frame(width: 118, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image("CatPawStamp")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(CatDesign.accentAmber)

                    Text(L10n.tr("收藏"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)
                }

                Text("\(L10n.tr("%d · 电影", movieCount)) · \(L10n.tr("%d · 剧集", tvShowCount))")
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Text("\(totalCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CatDesign.accentAmber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(CatDesign.amberTintFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.75))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .catGlassCard(cornerRadius: CatDesign.radiusSquircleLg, elevated: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("收藏，共 %d 部", totalCount))
    }

    @ViewBuilder
    private var posterStack: some View {
        let urls = Array(entries.prefix(3))
        ZStack {
            if urls.count >= 3 {
                miniPoster(urls[2]).rotationEffect(.degrees(-8)).offset(x: -24, y: 2)
                miniPoster(urls[1]).rotationEffect(.degrees(8)).offset(x: 24, y: 2)
                miniPoster(urls[0]).offset(y: -2)
            } else if urls.count == 2 {
                miniPoster(urls[1]).rotationEffect(.degrees(-6)).offset(x: -16, y: 2)
                miniPoster(urls[0]).rotationEffect(.degrees(5)).offset(x: 16, y: -2)
            } else {
                miniPoster(urls.first ?? nil)
            }
        }
    }

    private func miniPoster(_ url: URL?) -> some View {
        KFImage(url)
            .placeholder {
                ZStack {
                    CatDesign.mediaPlaceholder
                    Image(systemName: "film")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CatDesign.textMuted.opacity(0.5))
                }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(width: 50, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
    }
}

private struct CatFolderBookmarkCard: View {
    let bookmark: FolderBookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("CatFolderTileAmber")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 20)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text("\(bookmark.connectionName) · \(bookmark.path)")
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 184, alignment: .leading)
        .catGlassCard(cornerRadius: CatDesign.radiusSquircleMd)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bookmark.title)，\(bookmark.connectionName)")
    }
}

private struct CatPosterPlaceholder: View {
    let width: CGFloat

    private var imageHeight: CGFloat {
        (width * 150 / 106).rounded()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                .fill(CatDesign.surfacePill)
                .frame(width: width, height: imageHeight)

            RoundedRectangle(cornerRadius: 4)
                .fill(CatDesign.surfacePill)
                .frame(width: width * 0.78, height: 12)

            RoundedRectangle(cornerRadius: 4)
                .fill(CatDesign.surfacePill.opacity(0.65))
                .frame(width: width * 0.48, height: 10)
        }
    }
}

private struct CatCollectionLoadingSection: View {
    let posterWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(CatDesign.surfacePill)
                .frame(width: 140, height: 18)
                .padding(.horizontal, CatDesign.horizontalMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        CatPosterPlaceholder(width: posterWidth)
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct CatScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct LibraryContinueWatchingListView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [MediaItem]
    let onPlay: (MediaItem) -> Void
    let onInspect: (MediaItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    CatBackButton { dismiss() }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.tr("继续观看"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CatDesign.textIvory)
                        Text(L10n.tr("%d 项", items.count))
                            .font(.system(size: 11))
                            .foregroundStyle(CatDesign.textMuted)
                    }

                    Spacer()
                    CatStretchingDivider()
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            Button {
                                onPlay(item)
                            } label: {
                                CatContinueWatchingCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    dismiss()
                                    onInspect(item)
                                } label: {
                                    Label(L10n.tr("查看详情"), systemImage: "info.circle")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                    .padding(.vertical, 12)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
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
