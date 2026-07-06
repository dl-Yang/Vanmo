import SwiftUI
import VanmoCore

struct VanmoMacRootView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @Environment(\.colorScheme) private var colorScheme
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
        .onAppear {
            connectionsViewModel.setModelContext(modelContext)
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
