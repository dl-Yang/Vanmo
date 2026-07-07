import SwiftUI
import SwiftData
import VanmoCore

struct MacLibraryHomeView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @Environment(\.macTheme) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var syncToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                MacHeaderToolbar(
                    title: appState.selectedSection.title,
                    isEmptyLibrary: libraryViewModel.isLibraryEmpty
                )

                if libraryViewModel.isLibraryEmpty {
                    MacLibraryEmptyStateView {
                        appState.presentAddConnection()
                    }
                } else if appState.selectedSection == .home {
                    homeContent
                } else {
                    sectionFilteredContent
                }
            }

            if let message = connectionsViewModel.librarySyncMessage {
                syncStatusOverlay(message: message)
            }

            if let syncToastMessage {
                syncToast(message: syncToastMessage)
            }
        }
        .background(theme.appBackground)
        .onAppear {
            libraryViewModel.setModelContext(modelContext)
        }
        .task {
            await connectionsViewModel.loadSavedConnections()
            await libraryViewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
            libraryViewModel.refreshFolderBookmarks(connections: connectionsViewModel.savedConnections)
        }
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
                libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
                showSyncToast("数据同步完成")
            }
        }
        .onChange(of: appState.selectedFilter) { _, newValue in
            libraryViewModel.reload(filter: newValue, section: appState.selectedSection)
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            libraryViewModel.reload(filter: appState.selectedFilter, section: newValue)
        }
        .onChange(of: libraryViewModel.sortOption) { _, _ in
            libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !libraryViewModel.recentlyPlayed.isEmpty {
                    continueWatchingSection
                }

                if libraryViewModel.totalFavoritesCount > 0 {
                    favoritesSection
                }

                if !libraryViewModel.folderBookmarks.isEmpty {
                    folderBookmarksSection
                }

                if hasEmbyConnectionsConfigured {
                    embyCollectionSections
                }

                scannedLibrarySections
            }
            .padding(MacDesignTokens.Layout.contentPadding)
            .padding(.bottom, 32)
        }
    }

    private var sectionFilteredContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if appState.selectedSection != .favorites {
                    MacFilterPills()
                        .padding(.bottom, 24)
                }

                MacLibraryMediaLayout(viewMode: appState.viewMode) {
                    MacLibraryPosterGrid(items: libraryViewModel.sortedSectionItems()) { item in
                        appState.openDetail(item)
                    }
                } listContent: {
                    MacLibraryPosterList(items: libraryViewModel.sortedSectionItems()) { item in
                        appState.openDetail(item)
                    }
                }
            }
            .padding(MacDesignTokens.Layout.contentPadding)
        }
    }

    private var hasEmbyConnectionsConfigured: Bool {
        libraryViewModel.hasConfiguredEmbyConnections || !libraryViewModel.orderedEmbyConnections.isEmpty
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacLibrarySectionHeader(title: "历史记录")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(libraryViewModel.recentlyPlayed) { item in
                        MacContinueWatchingCard(
                            title: item.displayTitle,
                            subtitle: continueWatchingSubtitle(item),
                            posterURL: item.posterURL ?? item.backdropURL,
                            progress: item.playbackProgress
                        ) {
                            appState.play(item, from: item.lastPlaybackPosition)
                        }
                    }
                }
            }
        }
    }

    private var favoritesSection: some View {
        MacFavoritesStackedCard(
            posterURLs: libraryViewModel.favorites.prefix(3).map(\.posterURL),
            totalCount: libraryViewModel.totalFavoritesCount,
            movieCount: libraryViewModel.favoriteMovieCount,
            tvShowCount: libraryViewModel.favoriteTVShowCount
        ) {
            appState.openFavoritesList()
        }
    }

    private var folderBookmarksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacLibrarySectionHeaderRow(
                title: "文件夹书签",
                subtitle: "\(libraryViewModel.folderBookmarks.count) 个快捷入口"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(libraryViewModel.folderBookmarks) { bookmark in
                        MacFolderBookmarkCard(
                            title: bookmark.title,
                            connectionName: bookmark.connectionName
                        ) {
                            openFolderBookmark(bookmark)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var embyCollectionSections: some View {
        if libraryViewModel.isLoadingEmbyHome && libraryViewModel.serverCollectionFolders.isEmpty {
            ProgressView("正在加载媒体库…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(libraryViewModel.orderedEmbyConnections) { connection in
                if let errorMessage = serverErrorMessage(for: connection) {
                    serverErrorSection(serverName: connection.name, message: errorMessage)
                } else {
                    let folders = libraryViewModel.homeVisibleFolders(for: connection.id)
                    if !folders.isEmpty {
                        collectionFolderSection(serverName: connection.name, folders: folders, connection: connection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scannedLibrarySections: some View {
        ForEach(libraryViewModel.orderedScannedConnections) { connection in
            if let errorMessage = serverErrorMessage(for: connection) {
                serverErrorSection(serverName: connection.name, message: errorMessage)
            } else {
                let folders = libraryViewModel.homeVisibleScannedFolders(for: connection.id)
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
        VStack(alignment: .leading, spacing: 16) {
            MacLibrarySectionHeaderRow(
                title: serverName,
                subtitle: "\(folders.count) 个媒体库"
            )

            ForEach(folders) { folder in
                folderRow(folder: folder, connection: connection)
            }
        }
    }

    private func folderRow(folder: CollectionFolder, connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MacLibrarySectionHeaderRow(
                title: folder.name,
                subtitle: folder.collectionType.displayName,
                actionTitle: "查看全部"
            ) {
                openFolderList(folder: folder, connection: connection)
            }

            folderPreviewContent(folder: folder, connection: connection)
        }
    }

    @ViewBuilder
    private func folderPreviewContent(folder: CollectionFolder, connection: SavedConnection) -> some View {
        let previewItems = libraryViewModel.previewItems(for: folder)
        let isLoaded = libraryViewModel.isFolderPreviewLoaded(folder)

        if !isLoaded {
            MacFolderPreviewSkeletonRow()
        } else if !previewItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(previewItems) { item in
                        MacPosterCard(
                            title: item.displayTitle,
                            subtitle: folderPreviewSubtitle(item),
                            posterURL: item.posterURL
                        ) {
                            openPreviewItem(item, folder: folder, connection: connection)
                        }
                    }
                }
            }
        }
    }

    private func serverErrorSection(serverName: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(serverName)
                .font(MacDesignTokens.Typography.sectionTitle)
            Text("连接服务器失败：\(message)")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(14)
        .background(theme.secondaryButtonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func serverErrorMessage(for connection: SavedConnection) -> String? {
        libraryViewModel.serverConnectionErrors[connection.id]
            ?? connectionsViewModel.connectionErrorMessage(for: connection)
    }

    private func usesServerCollectionAPI(_ connection: SavedConnection) -> Bool {
        connection.type == .emby || connection.type == .jellyfin
    }

    private func openFolderList(folder: CollectionFolder, connection: SavedConnection) {
        if usesServerCollectionAPI(connection) {
            appState.openCollectionFolderList(folder: folder, connection: connection)
        } else {
            appState.openScannedLibraryList(connection: connection, collectionType: folder.collectionType)
        }
    }

    private func openPreviewItem(
        _ item: MediaItem,
        folder: CollectionFolder,
        connection: SavedConnection
    ) {
        if !usesServerCollectionAPI(connection), folder.collectionType == .tvshows {
            appState.openScannedShowDetail(connection: connection, showTitle: item.showTitle ?? item.title)
        } else {
            switch item.mediaType {
            case .folder, .collectionFolder, .season, .boxSet:
                if item.serverId != nil {
                    appState.openEmbyFolderBrowse(container: item)
                } else {
                    appState.openDetail(item)
                }
            default:
                appState.openDetail(item)
            }
        }
    }

    private func openFolderBookmark(_ bookmark: FolderBookmark) {
        guard let connection = connectionsViewModel.savedConnections.first(where: { $0.id == bookmark.connectionId }) else {
            return
        }
        connectionsViewModel.requestOpenFolderBookmark(bookmark)
        appState.enterConnectionBrowser(connection)
        Task {
            if let request = connectionsViewModel.pendingFolderBookmarkNavigation {
                _ = await connectionsViewModel.openFolderBookmarkRequest(request)
            }
        }
    }

    private func continueWatchingSubtitle(_ item: MediaItem) -> String {
        if item.lastPlaybackPosition > 0, item.duration > 0 {
            return MacFormatters.remainingDuration(position: item.lastPlaybackPosition, total: item.duration)
        }
        if let year = item.year {
            return String(year)
        }
        return item.mediaType.displayName
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func syncStatusOverlay(message: String) -> some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(12)
        .background(theme.headerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 64)
    }

    private func syncToast(message: String) -> some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.headerBackground)
            .clipShape(Capsule())
            .padding(.top, 12)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    syncToastMessage = nil
                }
            }
    }

    private func showSyncToast(_ message: String) {
        syncToastMessage = message
    }
}

#Preview {
    MacLibraryHomeView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .macTheme(.light)
}
