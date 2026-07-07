import SwiftData
import SwiftUI
import VanmoCore

@main
struct VanmoMacApp: App {
    init() {
        OAuthCoordinator.shared.presentationContextProvider = AppKitOAuthPresentationContextProvider.shared
        PrefetchTemporaryStore.cleanupOrphans()
    }

    @StateObject private var cloudSyncCoordinator = CloudSyncCoordinator.shared
    @StateObject private var appState = MacAppState()
    @StateObject private var libraryViewModel = MacLibraryViewModel()
    @StateObject private var connectionsViewModel = MacConnectionsViewModel()
    @StateObject private var searchViewModel = MacSearchViewModel()

    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            VanmoMacRootView()
                .environmentObject(cloudSyncCoordinator)
                .environmentObject(appState)
                .environmentObject(libraryViewModel)
                .environmentObject(connectionsViewModel)
                .environmentObject(searchViewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.selectSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
