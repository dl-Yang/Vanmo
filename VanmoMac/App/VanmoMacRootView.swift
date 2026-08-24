import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

struct VanmoMacRootView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var syncToastMessage: String?
    @State private var isDropTargeted = false

    private var isDarkAppearance: Bool {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme)
    }

    var body: some View {
        ZStack() {
            MacVibrancyBackground(isDark: isDarkAppearance, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            HStack(spacing: 0) {
                if appState.isSidebarExpanded {
                    MacSidebarView()
                        .transition(.move(edge: .leading))
                }
                mainContent
                    .background(activeTheme.appBackground)
//                    .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
            }
            .ignoresSafeArea(edges: .top)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(MacDesignTokens.accentBlue, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .padding(12)
                        .background(Color.black.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }

            // 顶部悬浮控制条：展开/折叠 + 下载，侧边栏收起时保持原位可用。
            MacSidebarToggleButton()
                .frame(width: appState.sidebarWidth - MacDesignTokens.Layout.trafficLightsLeadingInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, MacDesignTokens.Layout.trafficLightsLeadingInset + 5)
                .padding(.top, 2)
                .ignoresSafeArea(edges: .top)

            if let message = connectionsViewModel.librarySyncMessage {
                syncStatusOverlay(message: message)
            }

            if let syncToastMessage {
                VStack {
                    MacLibrarySyncToast(message: syncToastMessage)
                        .padding(.top, 20)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .macTheme(activeTheme)
        .background {
            MacMainWindowAccessor { window in
                appState.registerMainWindow(window)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isSidebarExpanded)
        .sheet(isPresented: $appState.isAddConnectionPresented, onDismiss: refreshLibraryAfterConnection) {
            MacAddConnectionView(viewModel: connectionsViewModel)
                .macTheme(activeTheme)
                .presentationBackground(.clear)
        }
        .sheet(item: $appState.editingConnection, onDismiss: refreshLibraryAfterConnection) { connection in
            MacAddConnectionView(viewModel: connectionsViewModel, editingConnection: connection)
                .macTheme(activeTheme)
                .presentationBackground(.clear)
        }
        .task {
            appState.configurePlayerDependencies(
                libraryViewModel: libraryViewModel,
                connectionsViewModel: connectionsViewModel,
                modelContainer: modelContext.container
            )
            connectionsViewModel.setModelContext(modelContext)
            libraryViewModel.setModelContext(modelContext)
            searchViewModel.setModelContext(modelContext)
            downloadManager.configure(modelContext: modelContext)
            await downloadManager.restoreAndResume()
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            appState.notifyWatchHistoryDidChange()
            await connectionsViewModel.loadSavedConnections()
            searchViewModel.setConnections(connectionsViewModel.savedConnections)
            await refreshLibrarySections()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                if newPhase == .active {
                    downloadManager.resume()
                    await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                    appState.notifyWatchHistoryDidChange()
                    await connectionsViewModel.loadSavedConnections()
                    searchViewModel.setConnections(connectionsViewModel.savedConnections)
                    // 不再全量刷新 library：folder preview / Emby live 数据只在冷启动时加载一次。
                } else if newPhase == .background {
                    await downloadManager.suspend()
                }
            }
        }
        .onChange(of: connectionsViewModel.savedConnections.map(\.id)) { _, _ in
            searchViewModel.setConnections(connectionsViewModel.savedConnections)
            if !searchViewModel.searchText.isEmpty {
                searchViewModel.search()
            }
        }
        .onChange(of: appState.pendingDownloadDetailTarget, initial: true) { _, target in
            guard let target else { return }
            openDownloadDetail(target)
        }
        .onAppear {
            appState.syncAppearance(with: colorScheme)
        }
        .onChange(of: appState.appearanceMode) { _, _ in
            appState.syncAppearance(with: colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            appState.syncAppearance(with: newScheme)
        }
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                // 扫描完成：只重载本地扫描/高亮/书签，不再重复拉取 Emby live 与 folder preview。
                await refreshLibrarySections(refreshEmbyLive: false)
                showSyncToast("数据同步完成")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            // 持久化到 AppState，避免 Favorites 未挂载时通知丢失。
            appState.notifyFavoriteDidChange()
        }
        .onChange(of: appState.watchHistoryChangeNonce) { _, _ in
            // 播放器窗口关闭（进度已落库）后刷新首页「历史记录」区。
            Task {
                await libraryViewModel.reloadWatchHistory()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
        }

    }

    private func openDownloadDetail(_ target: MacDownloadDetailTarget) {
        let item = storedMediaItem(for: target.request)
            ?? makeDownloadDetailFallback(for: target.request)
        appState.openDetail(item, focusedEpisode: target.focusedEpisode)
        appState.consumeDownloadDetailTarget()
    }

    private func storedMediaItem(for request: DownloadRequest) -> MediaItem? {
        if let mediaID = request.sourceMediaItemID {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { $0.id == mediaID }
            )
            if let item = try? modelContext.fetch(descriptor).first {
                return item
            }
        }

        let serverID = request.mediaType == .tvEpisode
            ? request.seriesServerID
            : request.sourceServerID
        guard let serverID, let connectionID = request.sourceConnectionId else {
            return nil
        }
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate {
                $0.serverId == serverID && $0.sourceConnectionId == connectionID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func makeDownloadDetailFallback(for request: DownloadRequest) -> MediaItem {
        let opensSeries = request.mediaType == .tvEpisode
        let item = MediaItem(
            title: opensSeries ? (request.showTitle ?? request.displayTitle) : request.displayTitle,
            fileURL: request.sourceFileURL ?? URL(fileURLWithPath: request.remotePath),
            mediaType: opensSeries ? .tvShow : request.mediaType,
            fileSize: request.totalBytes
        )
        item.posterURL = request.postUrl
        item.backdropURL = request.postUrl
        item.sourceConnectionId = request.sourceConnectionId
        item.serverId = opensSeries ? request.seriesServerID : request.sourceServerID
        item.seriesId = request.seriesServerID
        item.showTitle = request.showTitle
        return item
    }

    private func syncStatusOverlay(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 16)
            Spacer()
        }
        .zIndex(2)
        .allowsHitTesting(false)
    }

    private func showSyncToast(_ message: String) {
        syncToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if syncToastMessage == message {
                syncToastMessage = nil
            }
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                guard MacLocalFilePlayback.playDroppedURL(url, via: appState) else { return }
            }
        }

        return true
    }

    private func refreshLibraryAfterConnection() {
        Task {
            await refreshLibrarySections()
        }
    }

    private func refreshLibrarySections(refreshEmbyLive: Bool = true) async {
        await connectionsViewModel.loadSavedConnections()
        await libraryViewModel.refreshAfterLibrarySync(
            connections: connectionsViewModel.savedConnections,
            refreshEmbyLive: refreshEmbyLive
        )
        libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
    }

    private var activeTheme: MacThemeColors {
        if appState.selectedMediaItem == nil, libraryViewModel.isLibraryEmpty {
            return isDarkAppearance ? .emptyDark : .light
        }
        return isDarkAppearance ? .dark : .light
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            // 库根视图常驻：切 tab / 详情返回 / 子路由返回时仅切换透明度，不销毁重建，
            // 保留 ScrollView 位置与 Kingfisher 内存缓存。
            libraryRootContent

            // 库子路由覆盖层（collectionFolder 等从库根推入）
            librarySubrouteContent
                .opacity(isLibrarySubrouteActive ? 1 : 0)
                .allowsHitTesting(isLibrarySubrouteActive)

            // 独立路由覆盖层（连接浏览器 / 搜索 / 设置）
            standaloneRouteContent
                .opacity(isLibraryFamilyActive ? 0 : 1)
                .allowsHitTesting(!isLibraryFamilyActive)
        }
        .overlay {
            if let selectedItem = appState.selectedMediaItem {
                MacMediaDetailView(
                    item: selectedItem,
                    focusedEpisode: appState.detailEpisodeLocator
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
    }

    private var libraryRootContent: some View {
        ZStack {
            MacLibraryHomeView()
                .opacity(appState.contentRoute == .library ? 1 : 0)
                .allowsHitTesting(appState.contentRoute == .library)
            MacFavoritesListView()
                .opacity(appState.contentRoute == .libraryFavorites ? 1 : 0)
                .allowsHitTesting(appState.contentRoute == .libraryFavorites)
            MacHistoryListView()
                .opacity(appState.contentRoute == .libraryHistory ? 1 : 0)
                .allowsHitTesting(appState.contentRoute == .libraryHistory)
        }
    }

    /// 从库根推入的子页面（媒体库 / 剧集详情等），激活时覆盖在库根之上。
    @ViewBuilder
    private var librarySubrouteContent: some View {
        switch appState.contentRoute {
        case .libraryCollectionFolder:
            if let folder = appState.routeCollectionFolder,
               let connection = appState.routeConnection {
                MacCollectionFolderListView(folder: folder, connection: connection)
            }
        case .libraryScannedLibrary:
            if let connection = appState.routeConnection,
               let collectionType = scannedCollectionType {
                MacScannedLibraryListView(connection: connection, collectionType: collectionType)
            }
        case .libraryEmbyFolderBrowse:
            if let container = appState.routeContainerItem {
                MacEmbyFolderBrowseView(container: container)
            }
        case let .libraryScannedShowDetail(_, showTitle):
            if let connection = appState.routeConnection {
                MacScannedShowDetailView(connection: connection, showTitle: showTitle)
            }
        default:
            EmptyView()
        }
    }

    /// 与库互斥的独立页面（连接浏览器 / 搜索）。
    @ViewBuilder
    private var standaloneRouteContent: some View {
        switch appState.contentRoute {
        case .connectionBrowser:
            MacConnectionsBrowseView()
        case .search:
            MacSearchResultsView()
        default:
            EmptyView()
        }
    }

    private var isLibraryFamilyActive: Bool {
        switch appState.contentRoute {
        case .library, .libraryFavorites, .libraryHistory,
             .libraryCollectionFolder, .libraryScannedLibrary,
             .libraryEmbyFolderBrowse, .libraryScannedShowDetail:
            return true
        default:
            return false
        }
    }

    private var isLibrarySubrouteActive: Bool {
        switch appState.contentRoute {
        case .libraryCollectionFolder, .libraryScannedLibrary,
             .libraryEmbyFolderBrowse, .libraryScannedShowDetail:
            return true
        default:
            return false
        }
    }

    private var scannedCollectionType: EmbyCollectionType? {
        guard case let .libraryScannedLibrary(_, rawValue) = appState.contentRoute else { return nil }
        return EmbyCollectionType(raw: rawValue)
    }
}

private struct MacMainWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(view.window)
        }
    }
}

#Preview {
    VanmoMacRootView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .environmentObject(MacSearchViewModel())
        .environmentObject(CloudSyncCoordinator.shared)
}
