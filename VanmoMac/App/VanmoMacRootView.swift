import SwiftUI
import VanmoCore

struct VanmoMacRootView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                MacSidebarView()
                mainContent
            }
            .macTheme(activeTheme)

            if appState.isPlayerPresented, let playerItem = appState.playerItem {
                MacPlayerView(item: playerItem, startPosition: appState.playerStartPosition)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isPlayerPresented)
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
            connectionsViewModel.setModelContext(modelContext)
            libraryViewModel.setModelContext(modelContext)
            searchViewModel.setModelContext(modelContext)
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            await connectionsViewModel.loadSavedConnections()
            searchViewModel.setConnections(connectionsViewModel.savedConnections)
            await refreshLibrarySections()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                await connectionsViewModel.loadSavedConnections()
                searchViewModel.setConnections(connectionsViewModel.savedConnections)
                await refreshLibrarySections()
            }
        }
        .onChange(of: connectionsViewModel.savedConnections.map(\.id)) { _, _ in
            searchViewModel.setConnections(connectionsViewModel.savedConnections)
            if !searchViewModel.searchText.isEmpty {
                searchViewModel.search()
            }
        }
    }

    private func refreshLibraryAfterConnection() {
        Task {
            await refreshLibrarySections()
        }
    }

    private func refreshLibrarySections() async {
        await connectionsViewModel.loadSavedConnections()
        await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
        libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
    }

    private var activeTheme: MacThemeColors {
        let isDark = colorScheme == .dark
        if appState.selectedMediaItem == nil, libraryViewModel.isLibraryEmpty {
            return isDark ? .emptyDark : .light
        }
        return isDark ? .dark : .light
    }

    @ViewBuilder
    private var mainContent: some View {
        if let selectedItem = appState.selectedMediaItem {
            MacMediaDetailView(item: selectedItem)
        } else {
            switch appState.contentRoute {
            case .library:
                MacLibraryHomeView()
            case .libraryFavorites:
                MacFavoritesListView()
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
            case .connectionBrowser:
                MacConnectionsBrowseView()
            case .search:
                MacSearchResultsView()
            case .settings:
                MacSettingsView()
            }
        }
    }

    private var scannedCollectionType: EmbyCollectionType? {
        guard case let .libraryScannedLibrary(_, rawValue) = appState.contentRoute else { return nil }
        return EmbyCollectionType(raw: rawValue)
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
