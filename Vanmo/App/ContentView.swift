import SwiftUI
import VanmoCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var downloadManager: DownloadManager

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
            .tabItem {
                Label(AppTab.connections.title, systemImage: AppTab.connections.icon)
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
        .modifier(PlayerPresentationModifier())
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            // 持久化到 AppState，避免 LibraryView 未挂载时通知丢失。
            appState.notifyFavoriteDidChange()
        }
        .task {
            connectionsViewModel.setModelContext(modelContext)
            downloadManager.configure(modelContext: modelContext)
            await downloadManager.restoreAndResume()
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                if newPhase == .active {
                    downloadManager.resume()
                    await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                    await connectionsViewModel.loadSavedConnections()
                } else if newPhase == .background {
                    await downloadManager.suspend()
                }
            }
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
}
