import AppKit
import SwiftData
import SwiftUI
import VanmoCore

enum MacSidebarSection: String, CaseIterable, Identifiable {
    case home
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .favorites: "Favorites"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .favorites: "heart"
        case .history: "clock"
        }
    }
}

enum MacLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case unwatched
    case recentlyAdded
    case movies
    case tvShows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unwatched: "Unwatched"
        case .recentlyAdded: "Recently Added"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }
}

enum MacLibraryViewMode: String {
    case grid
    case list
}

enum MacAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "mac.appearance.mode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    func resolvedIsDark(systemColorScheme: ColorScheme) -> Bool {
        switch self {
        case .system: systemColorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
}

enum MacContentRoute: Equatable {
    case library
    case libraryFavorites
    case libraryHistory
    case libraryCollectionFolder(connectionId: UUID, folderId: String)
    case libraryScannedLibrary(connectionId: UUID, collectionTypeRaw: String)
    case libraryEmbyFolderBrowse
    case libraryScannedShowDetail(connectionId: UUID, showTitle: String)
    case connectionBrowser(activeConnectionId: UUID)
    case search
}

struct MacMediaPurgeEvent: Equatable {
    let connectionId: UUID
    let nonce: UUID

    init(connectionId: UUID) {
        self.connectionId = connectionId
        self.nonce = UUID()
    }
}

struct MacEpisodeDetailLocator: Hashable {
    let serverID: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let requestID: UUID

    init(
        serverID: String?,
        seasonNumber: Int,
        episodeNumber: Int,
        requestID: UUID = UUID()
    ) {
        self.serverID = serverID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.requestID = requestID
    }
}

struct MacDownloadDetailTarget: Equatable {
    let request: DownloadRequest
    let focusedEpisode: MacEpisodeDetailLocator?
}

@MainActor
final class MacAppState: ObservableObject {
    @AppStorage(MacAppearanceMode.storageKey) var appearanceMode: MacAppearanceMode = .system
    @AppStorage("mac.sidebarWidth") private var storedSidebarWidth: Double = Double(MacDesignTokens.Layout.sidebarWidth)

    @Published var contentRoute: MacContentRoute = .library
    @Published var selectedSection: MacSidebarSection = .home
    @Published var selectedFilter: MacLibraryFilter = .all
    @Published var viewMode: MacLibraryViewMode = .grid
    @Published var isDarkMode = false
    @Published var selectedMediaItem: MediaItem?
    @Published private(set) var detailEpisodeLocator: MacEpisodeDetailLocator?
    @Published private(set) var pendingDownloadDetailTarget: MacDownloadDetailTarget?
    @Published var isPlayerPresented = false
    @Published var playerItem: MediaItem?
    @Published var playerStartPosition: TimeInterval = 0
    @Published var isAddConnectionPresented = false
    @Published var editingConnection: SavedConnection?
    @Published var isSidebarExpanded: Bool = true

    var sidebarWidth: CGFloat {
        get { Self.clampedSidebarWidth(CGFloat(storedSidebarWidth)) }
        set {
            let next = Double(Self.clampedSidebarWidth(newValue))
            guard next != storedSidebarWidth else { return }
            objectWillChange.send()
            storedSidebarWidth = next
        }
    }

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, MacDesignTokens.Layout.sidebarMinWidth), MacDesignTokens.Layout.sidebarMaxWidth)
    }

    @Published var routeCollectionFolder: CollectionFolder?
    @Published var routeConnection: SavedConnection?
    @Published var routeContainerItem: MediaItem?
    @Published private(set) var isPlayerPlaying = false
    /// 删除连接前发出，供收藏等本地 StateObject 在下一帧清理。
    @Published private(set) var mediaPurgeEvent: MacMediaPurgeEvent?
    /// 任意入口收藏变更后递增；Favorites 未挂载时也能在下次进入时强制 reload。
    @Published private(set) var favoriteChangeNonce = UUID()
    /// 播放进度保存（播放器窗口关闭）后递增，供首页「历史记录」与 History 页面刷新。
    @Published private(set) var watchHistoryChangeNonce = UUID()

    /// 同步 purge 回调（删除前立刻执行），避免仅依赖 onChange 时序。
    private var mediaPurgeHandlers: [UUID: (UUID) -> Void] = [:]

    /// 播放器 ViewModel 由 AppState 强持有，确保播放窗口以任何方式关闭（红点/快捷键/切歌）时
    /// `handlePlayerWindowClosed()` 都能拿到它执行 `cleanup()`，避免引擎残留继续播放。
    private var activePlayerViewModel: MacPlayerViewModel?

    private var playerWindowController: MacPlayerWindowController?
    private weak var mainWindow: NSWindow?
    private weak var playerLibraryViewModel: MacLibraryViewModel?
    private weak var playerConnectionsViewModel: MacConnectionsViewModel?
    private var playerModelContainer: ModelContainer?

    var nowPlayingTitle: String? {
        playerItem?.displayTitle ?? playerItem?.title
    }

    var theme: MacThemeColors {
        isDarkMode ? .dark : .light
    }

    func syncAppearance(with systemColorScheme: ColorScheme) {
        isDarkMode = appearanceMode.resolvedIsDark(systemColorScheme: systemColorScheme)
    }

    /// 主窗口挂载后注入播放窗口所需的依赖（library / connections / SwiftData 容器）。
    func configurePlayerDependencies(
        libraryViewModel: MacLibraryViewModel,
        connectionsViewModel: MacConnectionsViewModel,
        modelContainer: ModelContainer
    ) {
        playerLibraryViewModel = libraryViewModel
        playerConnectionsViewModel = connectionsViewModel
        playerModelContainer = modelContainer
    }

    func registerMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        mainWindow = window
    }

    func activateMainWindow() {
        guard let mainWindow else { return }
        if mainWindow.isMiniaturized {
            mainWindow.deminiaturize(nil)
        }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openDetail(_ item: MediaItem, focusedEpisode: MacEpisodeDetailLocator? = nil) {
        detailEpisodeLocator = focusedEpisode
        selectedMediaItem = item
    }

    func closeDetail() {
        selectedMediaItem = nil
        detailEpisodeLocator = nil
    }

    func requestDownloadDetail(
        for request: DownloadRequest,
        focusedEpisode: MacEpisodeDetailLocator?
    ) {
        pendingDownloadDetailTarget = MacDownloadDetailTarget(
            request: request,
            focusedEpisode: focusedEpisode
        )
    }

    func consumeDownloadDetailTarget() {
        pendingDownloadDetailTarget = nil
    }

    func notifyFavoriteDidChange() {
        favoriteChangeNonce = UUID()
    }

    func notifyWatchHistoryDidChange() {
        watchHistoryChangeNonce = UUID()
    }

    var activeConnectionId: UUID? {
        if case let .connectionBrowser(id) = contentRoute {
            return id
        }
        return nil
    }

    var isSearchActive: Bool {
        if case .search = contentRoute { return true }
        return false
    }

    func selectLibrarySection(_ section: MacSidebarSection) {
        selectedSection = section
        clearLibrarySubRouteContext()
        switch section {
        case .home:
            contentRoute = .library
        case .favorites:
            contentRoute = .libraryFavorites
        case .history:
            contentRoute = .libraryHistory
        }
        closeDetail()
    }

    func openCollectionFolderList(folder: CollectionFolder, connection: SavedConnection) {
        routeCollectionFolder = folder
        routeConnection = connection
        contentRoute = .libraryCollectionFolder(connectionId: connection.id, folderId: folder.id)
        closeDetail()
    }

    func openScannedLibraryList(connection: SavedConnection, collectionType: EmbyCollectionType) {
        routeConnection = connection
        contentRoute = .libraryScannedLibrary(
            connectionId: connection.id,
            collectionTypeRaw: collectionType.rawValue
        )
        closeDetail()
    }

    func openEmbyFolderBrowse(container: MediaItem) {
        routeContainerItem = container
        contentRoute = .libraryEmbyFolderBrowse
        closeDetail()
    }

    func openScannedShowDetail(connection: SavedConnection, showTitle: String) {
        routeConnection = connection
        contentRoute = .libraryScannedShowDetail(connectionId: connection.id, showTitle: showTitle)
        closeDetail()
    }

    func clearLibrarySubRouteContext() {
        routeCollectionFolder = nil
        routeConnection = nil
        routeContainerItem = nil
    }

    func backFromLibrarySubRoute() {
        clearLibrarySubRouteContext()
        if contentRoute == .libraryFavorites || contentRoute == .libraryHistory {
            selectedSection = .home
        }
        contentRoute = .library
    }

    /// 当前是否还有上一级页面可返回（处于 home 根页面时为 false）。
    var canGoBack: Bool {
        if selectedMediaItem != nil { return true }
        switch contentRoute {
        case .library: return false
        default: return true
        }
    }

    /// 返回上一步：详情 → 列表/收藏 → home。
    func goBack() {
        if selectedMediaItem != nil {
            closeDetail()
            return
        }
        switch contentRoute {
        case .libraryFavorites, .libraryHistory:
            selectLibrarySection(.home)
        case .libraryCollectionFolder, .libraryScannedLibrary,
             .libraryEmbyFolderBrowse, .libraryScannedShowDetail:
            backFromLibrarySubRoute()
        case .connectionBrowser:
            exitConnectionBrowser()
        case .search:
            contentRoute = .library
        case .library:
            break
        }
    }

    func selectSearch() {
        contentRoute = .search
        closeDetail()
    }

    func enterConnectionBrowser(_ connection: SavedConnection) {
        clearLibrarySubRouteContext()
        contentRoute = .connectionBrowser(activeConnectionId: connection.id)
        closeDetail()
    }

    func exitConnectionBrowser() {
        contentRoute = .library
        // 回到 home 根页面时同步重置选中 section，避免侧边栏高亮与主区内容不一致。
        selectedSection = .home
    }

    func clearActiveConnectionIfDeleted(_ connectionId: UUID) {
        purgeMediaState(for: connectionId)
    }

    /// 删除连接前同步清空所有可能持有该连接 MediaItem 的 UI 状态，避免 SwiftData detach 后读属性崩溃。
    func purgeMediaState(for connectionId: UUID) {
        if let item = selectedMediaItem, item.isDeleted || item.sourceConnectionId == connectionId {
            closeDetail()
        }

        if let item = playerItem, item.isDeleted || item.sourceConnectionId == connectionId {
            closePlayer()
        }

        if editingConnection?.id == connectionId {
            dismissEditConnection()
        }

        let shouldExitSubRoute: Bool = {
            switch contentRoute {
            case let .libraryCollectionFolder(id, _),
                 let .libraryScannedLibrary(id, _),
                 let .libraryScannedShowDetail(id, _):
                return id == connectionId
            case .libraryEmbyFolderBrowse:
                if let container = routeContainerItem,
                   container.isDeleted || container.sourceConnectionId == connectionId {
                    return true
                }
                return routeConnection?.id == connectionId
            default:
                if routeConnection?.id == connectionId { return true }
                if let container = routeContainerItem,
                   container.isDeleted || container.sourceConnectionId == connectionId {
                    return true
                }
                return false
            }
        }()

        if shouldExitSubRoute {
            backFromLibrarySubRoute()
        }

        if activeConnectionId == connectionId {
            exitConnectionBrowser()
        }

        for handler in mediaPurgeHandlers.values {
            handler(connectionId)
        }
        mediaPurgeEvent = MacMediaPurgeEvent(connectionId: connectionId)
    }

    @discardableResult
    func registerMediaPurgeHandler(_ handler: @escaping (UUID) -> Void) -> UUID {
        let id = UUID()
        mediaPurgeHandlers[id] = handler
        return id
    }

    func unregisterMediaPurgeHandler(_ id: UUID) {
        mediaPurgeHandlers.removeValue(forKey: id)
    }

    func play(_ item: MediaItem, from position: TimeInterval = 0) {
        if isPlayerPresented {
            closePlayer()
        }

        playerItem = item
        playerStartPosition = position
        isPlayerPresented = true

        guard let playerLibraryViewModel,
              let playerConnectionsViewModel,
              let playerModelContainer else {
            return
        }

        let controller = MacPlayerWindowController(
            item: item,
            startPosition: position,
            appState: self,
            libraryViewModel: playerLibraryViewModel,
            connectionsViewModel: playerConnectionsViewModel,
            modelContainer: playerModelContainer,
            onWindowClosed: { [weak self] in
                self?.handlePlayerWindowClosed()
            }
        )
        playerWindowController = controller
        controller.showPlayer()
    }

    func closePlayer() {
        playerWindowController?.closeWindow()
        playerWindowController = nil
        handlePlayerWindowClosed()
    }

    /// 播放窗口关闭（用户点红点 / 菜单关闭 / 切换新播放内容）后的统一收尾。
    private func handlePlayerWindowClosed() {
        // closeWindow() 会同步回调 windowWillClose → 本方法；closePlayer() 随后还会显式调用一次。
        // 以播放状态做幂等保护，避免收尾逻辑（含历史刷新通知）重复执行。
        guard isPlayerPresented || playerItem != nil else { return }
        activePlayerViewModel?.cleanup()
        isPlayerPresented = false
        playerItem = nil
        playerStartPosition = 0
        unregisterActivePlayer()
        // 播放进度在关闭前已落库，通知首页与 History 页面刷新观看记录。
        notifyWatchHistoryDidChange()
    }

    func registerActivePlayer(_ viewModel: MacPlayerViewModel) {
        activePlayerViewModel = viewModel
        isPlayerPlaying = viewModel.isPlaying
    }

    func syncPlayerPlayingState(_ isPlaying: Bool) {
        isPlayerPlaying = isPlaying
    }

    func unregisterActivePlayer() {
        activePlayerViewModel = nil
        isPlayerPlaying = false
    }

    func presentAddConnection() {
        isAddConnectionPresented = true
    }

    func dismissAddConnection() {
        isAddConnectionPresented = false
    }

    func presentEditConnection(_ connection: SavedConnection) {
        editingConnection = connection
    }

    func dismissEditConnection() {
        editingConnection = nil
    }
}
