import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label(AppTab.library.title, systemImage: AppTab.library.icon)
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
                        }
                    }
            }
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
            }
            .tag(AppTab.settings)
        }
        .tint(.vanmoPrimary)
        .fullScreenCover(isPresented: $appState.isPlayerPresented) {
            if let item = appState.currentPlayingItem {
                PlayerView(item: item)
            }
        }
        .task {
            // App 启动后自动重连最近一次连接成功的服务，刷新媒体库。
            // ConnectionsViewModel 是 App 级别的 @StateObject，跨 ContentView 重建仍能保留
            // didAttemptAutoReconnect 标志，避免主题切换时重复触发。
            connectionsViewModel.setModelContext(modelContext)
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ConnectionsViewModel())
}
