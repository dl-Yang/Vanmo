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

@MainActor
final class MacAppState: ObservableObject {
    @Published var selectedSection: MacSidebarSection = .home
    @Published var selectedFilter: MacLibraryFilter = .all
    @Published var viewMode: MacLibraryViewMode = .grid
    @Published var isDarkMode = false
    @Published var selectedMediaItem: MediaItem?
    @Published var isPlayerPresented = false
    @Published var playerItem: MediaItem?
    @Published var playerStartPosition: TimeInterval = 0
    @Published var isAddConnectionPresented = false

    var theme: MacThemeColors {
        isDarkMode ? .dark : .light
    }

    func openDetail(_ item: MediaItem) {
        selectedMediaItem = item
    }

    func closeDetail() {
        selectedMediaItem = nil
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
}
