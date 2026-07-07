import SwiftUI
import VanmoCore

enum MacSidebarSection: String, CaseIterable, Identifiable {
    case home
    case movies
    case tvShows
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .tvShows: "tv"
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

enum MacContentRoute: Equatable {
    case library
    case libraryFavorites
    case libraryCollectionFolder(connectionId: UUID, folderId: String)
    case libraryScannedLibrary(connectionId: UUID, collectionTypeRaw: String)
    case libraryEmbyFolderBrowse
    case libraryScannedShowDetail(connectionId: UUID, showTitle: String)
    case connectionBrowser(activeConnectionId: UUID)
}

@MainActor
final class MacAppState: ObservableObject {
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

    @Published var routeCollectionFolder: CollectionFolder?
    @Published var routeConnection: SavedConnection?
    @Published var routeContainerItem: MediaItem?

    var theme: MacThemeColors {
        isDarkMode ? .dark : .light
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
