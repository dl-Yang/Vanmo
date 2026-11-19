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
        ZStack(alignment: .topTrailing) {
            MacCatAmbientHalo()
                .offset(x: -70, y: -30)

            if libraryViewModel.isLibraryEmpty {
                MacLibraryEmptyStateView {
                    appState.presentAddConnection()
                }
            } else {
                homeContent
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
            VStack(alignment: .leading, spacing: 22) {
                if let heroItem = featuredHeroItem {
                    MacFeaturedHeroBanner(
                        item: heroItem,
                        sourceLabel: heroSourceLabel(for: heroItem),
                        onPlay: {
                            let startPosition = heroItem.lastPlaybackPosition > 0 ? heroItem.lastPlaybackPosition : 0
                            appState.play(heroItem, from: startPosition)
                        },
                        onInspectDetails: {
                            appState.openDetail(heroItem)
                        }
                    )
                }

                if !libraryViewModel.recentlyPlayed.isEmpty {
                    continueWatchingSection
                }

                if !recentlyAddedItems.isEmpty {
                    recentlyAddedSection
                }

                if !libraryViewModel.folderBookmarks.isEmpty {
                    folderBookmarksSection
                }

                if hasEmbyConnectionsConfigured {
                    embyCollectionSections
                }

                scannedLibrarySections
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.top, featuredHeroItem == nil ? 28 : 10)
            .padding(.bottom, 32)
        }
    }

    private var hasEmbyConnectionsConfigured: Bool {
        libraryViewModel.hasConfiguredEmbyConnections || !libraryViewModel.orderedEmbyConnections.isEmpty
    }

    // MARK: - Featured & Recently Added Data

    private var aggregatedPreviewItems: [MediaItem] {
        var seenKeys = Set<String>()
        var result: [MediaItem] = []

        let allOrderedFolders = libraryViewModel.orderedEmbyConnections.flatMap {
            libraryViewModel.homeVisibleFolders(for: $0.id)
        } + libraryViewModel.orderedScannedConnections.flatMap {
            libraryViewModel.homeVisibleScannedFolders(for: $0.id)
        }

        for folder in allOrderedFolders {
            for item in libraryViewModel.previewItems(for: folder) where !item.isDeleted {
                let key = item.serverId ?? item.id.uuidString
                if seenKeys.insert(key).inserted {
                    result.append(item)
                }
            }
        }

        for item in libraryViewModel.recentlyPlayed where !item.isDeleted {
            let key = item.serverId ?? item.id.uuidString
            if seenKeys.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }

    private var featuredHeroItem: MediaItem? {
        let candidates = aggregatedPreviewItems + libraryViewModel.recentlyPlayed.filter { !$0.isDeleted }
        if let withBackdrop = candidates.first(where: { $0.backdropURL != nil && ($0.overview?.isEmpty == false) }) {
            return withBackdrop
        }
        if let withBackdrop = candidates.first(where: { $0.backdropURL != nil }) {
            return withBackdrop
        }
        return candidates.first(where: { $0.posterURL != nil }) ?? candidates.first
    }

    private func heroSourceLabel(for item: MediaItem) -> String? {
        guard let connId = item.sourceConnectionId,
              let conn = connectionsViewModel.savedConnections.first(where: { $0.id == connId }) else {
            return nil
        }
        return conn.type.displayName
    }

    private var recentlyAddedItems: [MediaItem] {
        Array(aggregatedPreviewItems.prefix(12))
    }

    private var recentlyAddedBadgeText: String? {
        var sources: [String] = []
        if !libraryViewModel.orderedEmbyConnections.isEmpty {
            sources.append(contentsOf: libraryViewModel.orderedEmbyConnections.prefix(2).map(\.type.displayName))
        }
        if !libraryViewModel.orderedScannedConnections.isEmpty {
            sources.append(contentsOf: libraryViewModel.orderedScannedConnections.prefix(1).map(\.name))
        }
        let uniqueSources = Array(NSOrderedSet(array: sources)).compactMap { $0 as? String }
        let total = totalKnownTitleCount
        var parts = uniqueSources
        if total > 0 {
            parts.append(L10n.tr("%d 项", total))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var totalKnownTitleCount: Int {
        let embyCount = libraryViewModel.folderTotalCounts.values.reduce(0, +)
        let scannedCount = libraryViewModel.scannedFolderTotalCounts.values.reduce(0, +)
        return max(embyCount + scannedCount, recentlyAddedItems.count)
    }

    // MARK: - Sections

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacCatSectionHeaderRow(
                title: L10n.tr("继续观看"),
                actionTitle: L10n.tr("查看全部"),
                action: { appState.selectLibrarySection(.history) }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(libraryViewModel.recentlyPlayed.prefix(homeHistoryLimit)) { item in
                        MacContinueWatchingCard(
                            title: item.displayTitle,
                            subtitle: continueWatchingSubtitle(item),
                            posterURL: item.backdropURL ?? item.posterURL,
                            progress: item.playbackProgress
                        ) {
                            appState.play(item, from: item.lastPlaybackPosition)
                        }
                        .macMediaItemContextMenu(for: item)
                    }

                    if libraryViewModel.recentlyPlayed.count > homeHistoryLimit {
                        MacContinueWatchingMoreCard {
                            appState.selectLibrarySection(.history)
                        }
                    }
                }
            }
        }
    }

    private var homeHistoryLimit: Int { 8 }

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacCatSectionHeaderRow(
                title: L10n.tr("最近添加"),
                badgeText: recentlyAddedBadgeText,
                actionTitle: L10n.tr("查看全部"),
                action: {
                    if let firstConnection = libraryViewModel.orderedEmbyConnections.first,
                       let firstFolder = libraryViewModel.homeVisibleFolders(for: firstConnection.id).first {
                        openFolderList(folder: firstFolder, connection: firstConnection)
                    } else if let firstConnection = libraryViewModel.orderedScannedConnections.first,
                              let firstFolder = libraryViewModel.homeVisibleScannedFolders(for: firstConnection.id).first {
                        openFolderList(folder: firstFolder, connection: firstConnection)
                    } else {
                        appState.selectLibrarySection(.favorites)
                    }
                }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MacDesignTokens.Layout.posterSpacing) {
                    ForEach(recentlyAddedItems) { item in
                        MacPosterCard(
                            title: item.displayTitle,
                            subtitle: folderPreviewSubtitle(item),
                            posterURL: item.posterURL
                        ) {
                            if let connId = item.sourceConnectionId,
                               let conn = connectionsViewModel.savedConnections.first(where: { $0.id == connId }),
                               !usesServerCollectionAPI(conn),
                               item.mediaType == .tvEpisode || item.mediaType == .tvShow {
                                appState.openScannedShowDetail(
                                    connection: conn,
                                    showTitle: item.showTitle ?? item.title,
                                    parentDirectory: ScannedShowGrouping.parentDirectory(for: item)
                                )
                            } else {
                                appState.openDetail(item)
                            }
                        }
                        .macMediaItemContextMenu(for: item)
                    }
                }
            }
        }
    }

    private var folderBookmarksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MacLibrarySectionHeaderRow(
                title: L10n.tr("文件夹书签"),
                subtitle: L10n.tr("%d 个快捷入口", libraryViewModel.folderBookmarks.count)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.tr("正在加载媒体库…"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            }
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
                subtitle: L10n.tr("%d 个媒体库", folders.count)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(serverName)
                .font(MacDesignTokens.Typography.sectionTitle)
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("连接服务器失败：%@", message))
                .font(.caption)
                .foregroundStyle(theme.dangerRed)
        }
        .padding(14)
        .macCatGlassCard(theme: theme, cornerRadius: 14)
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
            $0.id == model.id
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
            appState.openScannedShowDetail(
                connection: connection,
                showTitle: item.showTitle ?? item.title,
                parentDirectory: ScannedShowGrouping.parentDirectory(for: item)
            )
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
        var parts: [String] = []
        if item.lastPlaybackPosition > 0, item.duration > 0 {
            parts.append(MacFormatters.formatDuration(item.lastPlaybackPosition))
            parts.append(MacFormatters.formatDuration(item.duration))
        } else if item.duration > 0 {
            parts.append(MacFormatters.formatDuration(item.duration))
        } else if let year = item.year {
            parts.append(String(year))
        }
        if let dr = item.dynamicRange, !dr.isEmpty {
            parts.append(dr.uppercased())
        } else if let h = item.videoHeight, h >= 2000 {
            parts.append("4K")
        }
        return parts.isEmpty ? item.mediaType.displayName : parts.joined(separator: " · ")
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }
}

private struct MacHomePreviewCardModel: Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let posterURL: URL?
    let posterPath: String

    init(item: MediaItem, subtitle: String) {
        id = item.id
        title = item.displayTitle
        self.subtitle = subtitle
        posterURL = item.posterURL
        posterPath = item.posterURL?.path ?? ""
    }
}

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
            MacCatSectionHeaderRow(
                title: folder.name,
                badgeText: folder.collectionType.displayName,
                actionTitle: L10n.tr("查看全部"),
                action: onOpenFolder
            )

            if !isLoaded {
                MacFolderPreviewSkeletonRow()
            } else if !previewItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MacDesignTokens.Layout.posterSpacing) {
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
        .macTheme(.dark)
}
