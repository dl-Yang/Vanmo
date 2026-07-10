import SwiftUI
import UniformTypeIdentifiers
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

            if appState.isPlayerPresented, let playerItem = appState.playerItem {
                MacPlayerView(item: playerItem, startPosition: appState.playerStartPosition)
                    .transition(.opacity)
                    .zIndex(1)
            }

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
            HStack{
                MacSidebarToggleButton()
                    .padding(.bottom, 12)
            }
            .ignoresSafeArea(edges: .top)
            .position(
                x: MacDesignTokens.Layout.trafficLightsLeadingInset + 30,
                y: MacDesignTokens.Layout.trafficLightsTopInset + 7)
            
        }
        .macTheme(activeTheme)
        .animation(.easeInOut(duration: 0.2), value: appState.isPlayerPresented)
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
                await refreshLibrarySections()
                showSyncToast("数据同步完成")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
        }

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

    private func refreshLibrarySections() async {
        await connectionsViewModel.loadSavedConnections()
        await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
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
