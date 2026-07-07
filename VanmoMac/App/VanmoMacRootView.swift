import SwiftUI
import VanmoCore

struct VanmoMacRootView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
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
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            await refreshLibrarySections()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                await connectionsViewModel.loadSavedConnections()
                await refreshLibrarySections()
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
        } else if case .connectionBrowser = appState.contentRoute {
            MacConnectionsBrowseView()
        } else if case .libraryFavorites = appState.contentRoute {
            MacFavoritesListView()
        } else if case .libraryCollectionFolder = appState.contentRoute,
                  let folder = appState.routeCollectionFolder,
                  let connection = appState.routeConnection {
            MacCollectionFolderListView(folder: folder, connection: connection)
        } else if case .libraryScannedLibrary = appState.contentRoute,
                  let connection = appState.routeConnection,
                  let collectionType = scannedCollectionType {
            MacScannedLibraryListView(connection: connection, collectionType: collectionType)
        } else if case .libraryEmbyFolderBrowse = appState.contentRoute,
                  let container = appState.routeContainerItem {
            MacEmbyFolderBrowseView(container: container)
        } else if case let .libraryScannedShowDetail(_, showTitle) = appState.contentRoute,
                  let connection = appState.routeConnection {
            MacScannedShowDetailView(connection: connection, showTitle: showTitle)
        } else {
            MacLibraryHomeView()
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
        .environmentObject(CloudSyncCoordinator.shared)
}
