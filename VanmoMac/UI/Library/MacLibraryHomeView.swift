import SwiftUI
import SwiftData
import VanmoCore

struct MacLibraryHomeView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @Environment(\.macTheme) private var theme
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .top) {

            VStack(spacing: 0) {
                MacHeaderToolbar(
                    title: MacSidebarSection.home.title,
                    isEmptyLibrary: libraryViewModel.isLibraryEmpty
                )

                if libraryViewModel.isLibraryEmpty {
                    MacLibraryEmptyStateView {
                        appState.presentAddConnection()
                    }
                } else {
                    homeContent
                }
            }

        }
        .background(theme.appBackground)
        .onAppear {
            libraryViewModel.setModelContext(modelContext)
        }
        .task {
            // loadInitialSections 内部有 hasLoadedInitial guard，重活只在冷启动执行一次；
            // 连接/书签刷新轻量且带等价保护，内容不变不会触发重绘。
            await connectionsViewModel.loadSavedConnections()
            await libraryViewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
            libraryViewModel.refreshFolderBookmarks(connections: connectionsViewModel.savedConnections)
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
                MacHomeFolderPreviewRow(
                    folder: folder,
                    isLoaded: libraryViewModel.isFolderPreviewLoaded(folder),
                    previewItems: libraryViewModel.previewItems(for: folder).map {
                        MacHomePreviewCardModel(item: $0, subtitle: folderPreviewSubtitle($0))
                    },
                    onOpenFolder: {
                        openFolderList(folder: folder, connection: connection)
                    },
                    onOpenItem: { model in
                        openPreviewModel(model, folder: folder, connection: connection)
                    }
                )
                .equatable()
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

    private func openPreviewModel(
        _ model: MacHomePreviewCardModel,
        folder: CollectionFolder,
        connection: SavedConnection
    ) {
        guard let item = libraryViewModel.previewItems(for: folder).first(where: {
            if let serverId = model.serverId {
                return $0.serverId == serverId
            }
            return $0.title == model.title && $0.posterURL?.path == model.posterPath
        }) else {
            return
        }
        openPreviewItem(item, folder: folder, connection: connection)
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
}

private struct MacHomePreviewCardModel: Equatable, Identifiable {
    let id: String
    let serverId: String?
    let title: String
    let subtitle: String
    let posterURL: URL?
    let posterPath: String

    init(item: MediaItem, subtitle: String) {
        serverId = item.serverId
        title = item.displayTitle
        self.subtitle = subtitle
        posterURL = item.posterURL
        posterPath = item.posterURL?.path ?? ""
        id = item.serverId ?? "\(item.title)|\(posterPath)"
    }
}

/// 单个媒体库 preview 行。Equatable 后，内容未变的 folder 不会因其它 folder 更新而重绘。
private struct MacHomeFolderPreviewRow: View, Equatable {
    let folder: CollectionFolder
    let isLoaded: Bool
    let previewItems: [MacHomePreviewCardModel]
    let onOpenFolder: () -> Void
    let onOpenItem: (MacHomePreviewCardModel) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder.id == rhs.folder.id
            && lhs.folder.name == rhs.folder.name
            && lhs.folder.collectionType == rhs.folder.collectionType
            && lhs.isLoaded == rhs.isLoaded
            && lhs.previewItems == rhs.previewItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacLibrarySectionHeaderRow(
                title: folder.name,
                subtitle: folder.collectionType.displayName,
                actionTitle: "查看全部",
                action: onOpenFolder
            )

            if !isLoaded {
                MacFolderPreviewSkeletonRow()
            } else if !previewItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(previewItems) { item in
                            MacPosterCard(
                                title: item.title,
                                subtitle: item.subtitle,
                                posterURL: item.posterURL
                            ) {
                                onOpenItem(item)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    MacLibraryHomeView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .macTheme(.light)
}
