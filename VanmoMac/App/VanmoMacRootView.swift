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
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            refreshLibraryAfterConnection()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                await connectionsViewModel.loadSavedConnections()
                refreshLibraryAfterConnection()
            }
        }
    }

    private func refreshLibraryAfterConnection() {
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
        } else {
            MacLibraryHomeView()
        }
    }
}

#Preview {
    VanmoMacRootView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .environmentObject(CloudSyncCoordinator.shared)
}
