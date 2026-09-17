import SwiftUI
import VanmoCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @ObservedObject private var islandHandoff = DownloadIslandHandoff.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .accessibilityIdentifier("screen.library")
            .tabItem {
                Label(AppTab.library.title, systemImage: AppTab.library.icon)
                    .accessibilityIdentifier("tab.library")
            }
            .tag(AppTab.library)

            NavigationStack {
                ConnectionsView()
            }
            .accessibilityIdentifier("screen.files")
            .tabItem {
                Label(AppTab.connections.title, systemImage: AppTab.connections.icon)
                    .accessibilityIdentifier("tab.connections")
            }
            .tag(AppTab.connections)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label(AppTab.search.title, systemImage: AppTab.search.icon)
            }
            .tag(AppTab.search)

            NavigationStack(path: $appState.settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsRoute.self) { route in
                        switch route {
                        case .appearance:
                            AppearanceSettingsView()
                        case .downloads:
                            DownloadManagementView()
                        }
                    }
            }
            .accessibilityIdentifier("screen.settings")
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
                    .accessibilityIdentifier("tab.settings")
            }
            .tag(AppTab.settings)
        }
        .tint(.vanmoPrimary)
        .statusBarHidden(islandHandoff.hidesStatusBar)
        .modifier(PlayerPresentationModifier())
        .overlay {
            DownloadHeroHost()
        }
        .overlay(alignment: .top) {
            DownloadFallbackBarHost()
        }
        .overlay(alignment: .topLeading) {
            DownloadNotchStatusBarHost()
        }
        .overlay(alignment: .top) {
            DownloadIslandRingHost()
        }
        .onPreferenceChange(DownloadHeroFrameKey.self) { frames in
            if let source = frames["source"], DownloadHeroController.shared.sourceFrame != source {
                DispatchQueue.main.async {
                    DownloadHeroController.shared.sourceFrame = source
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "vanmo", url.host == "downloads" else { return }
            appState.openDownloads()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            // 持久化到 AppState，避免 LibraryView 未挂载时通知丢失。
            appState.notifyFavoriteDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionLocalMediaWillDelete)) { notification in
            guard let connectionId = notification.object as? UUID else { return }
            appState.purgeMediaState(for: connectionId)
        }
        .onAppear {
            DownloadIslandHandoff.shared.applyStatusBarPolicy()
#if DEBUG
            IslandDebugDarwin.shared.openDownloadsHandler = { appState.openDownloads() }
#endif
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["VANMO_DEBUG_TAB"] == "files" {
                appState.selectedTab = .connections
            }
#endif
            connectionsViewModel.setModelContext(modelContext)
            DownloadManager.shared.configure(modelContext: modelContext)
            await DownloadManager.shared.restoreAndResume()
#if DEBUG
            let statuses = DownloadManager.shared.tasks.map(\.status.rawValue).joined(separator: ",")
            print("[Debug][Downloads] restore count=\(DownloadManager.shared.tasks.count) statuses=\(statuses)")
            for task in DownloadManager.shared.tasks where task.status != .completed {
                print("[Debug][Downloads] restore task=\(task.id.uuidString) status=\(task.status.rawValue) received=\(task.receivedBytes) total=\(task.totalBytes)")
            }
#endif
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            await connectionsViewModel.loadSavedConnections()
            _ = await connectionsViewModel.activateNewlySyncedConnections()
#if DEBUG
            if let kind = DownloadHeroWalkFixtures.requestedKind {
                do {
                    let item = try DownloadHeroWalkFixtures.seedItem(kind: kind, in: modelContext)
                    appState.selectedTab = .library
                    NotificationCenter.default.post(
                        name: DownloadHeroWalkFixtures.openDetailNotification,
                        object: item.id
                    )
                    print("[Debug][Downloads] hero walk presented kind=\(kind.rawValue) title=\(item.title)")
                } catch {
                    print("[Debug][Downloads] hero walk seed failed")
                }
            }
#endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                DownloadManager.shared.resume()
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                Task {
                    await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                    await connectionsViewModel.loadSavedConnections()
                    _ = await connectionsViewModel.activateNewlySyncedConnections()
                }
            } else if newPhase == .inactive, oldPhase == .active {
                // Request before the home snapshot so iOS can absorb the scene into the island.
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
            } else if newPhase == .background {
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                Task {
                    await DownloadManager.shared.suspend()
                    guard DownloadIslandHandoff.shared.isParked else { return }
                    DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                }
            }
        }
        .sheet(item: $connectionsViewModel.pendingMissingCredentialConnection) { connection in
            AddConnectionView(viewModel: connectionsViewModel, editingConnection: connection)
        }
    }
}

private struct PlayerPresentationModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $appState.isPlayerPresented) {
                if let item = appState.currentPlayingItem {
                    PlayerView(item: item)
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ConnectionsViewModel())
        .environmentObject(CloudSyncCoordinator.shared)
        .environmentObject(DownloadManager.shared)
        .environmentObject(DownloadHeroController.shared)
}
