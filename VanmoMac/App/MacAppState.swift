import SwiftUI
import VanmoCore

enum MacSidebarSection: String, CaseIterable, Identifiable {
    case home
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .favorites: "heart"
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
    case libraryCollectionFolder(connectionId: UUID, folderId: String)
    case libraryScannedLibrary(connectionId: UUID, collectionTypeRaw: String)
    case libraryEmbyFolderBrowse
    case libraryScannedShowDetail(connectionId: UUID, showTitle: String)
    case connectionBrowser(activeConnectionId: UUID)
    case search
    case settings
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

    weak var activePlayerViewModel: MacPlayerViewModel?

    var nowPlayingTitle: String? {
        playerItem?.displayTitle ?? playerItem?.title
    }

    var theme: MacThemeColors {
        isDarkMode ? .dark : .light
    }

    func syncAppearance(with systemColorScheme: ColorScheme) {
        isDarkMode = appearanceMode.resolvedIsDark(systemColorScheme: systemColorScheme)
    }

    func openDetail(_ item: MediaItem) {
        selectedMediaItem = item
    }

    func closeDetail() {
        selectedMediaItem = nil
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

    var isSettingsActive: Bool {
        if case .settings = contentRoute { return true }
        return false
    }

    func selectLibrarySection(_ section: MacSidebarSection) {
        selectedSection = section
        clearLibrarySubRouteContext()
        contentRoute = section == .favorites ? .libraryFavorites : .library
        closeDetail()
    }

    func openFavoritesList() {
        selectedSection = .favorites
        clearLibrarySubRouteContext()
        contentRoute = .libraryFavorites
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
        contentRoute = .library
    }

    func selectSearch() {
        contentRoute = .search
        closeDetail()
    }

    func selectSettings() {
        contentRoute = .settings
        closeDetail()
    }

    func enterConnectionBrowser(_ connection: SavedConnection) {
        clearLibrarySubRouteContext()
        contentRoute = .connectionBrowser(activeConnectionId: connection.id)
        closeDetail()
    }

    func exitConnectionBrowser() {
        contentRoute = .library
    }

    func clearActiveConnectionIfDeleted(_ connectionId: UUID) {
        if activeConnectionId == connectionId {
            exitConnectionBrowser()
        }
    }

    func play(_ item: MediaItem, from position: TimeInterval = 0) {
        playerItem = item
        playerStartPosition = position
        isPlayerPresented = true
    }

    func closePlayer() {
        isPlayerPresented = false
        playerItem = nil
        playerStartPosition = 0
        unregisterActivePlayer()
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
