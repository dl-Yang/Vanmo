import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

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
                BrowserView()
            }
            .tabItem {
                Label(AppTab.browse.title, systemImage: AppTab.browse.icon)
            }
            .tag(AppTab.browse)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label(AppTab.search.title, systemImage: AppTab.search.icon)
            }
            .tag(AppTab.search)

            NavigationStack {
                SettingsView()
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
