import SwiftUI
import SwiftData
import VanmoCore

@main
struct VanmoMacApp: App {
    init() {
        OAuthCoordinator.shared.presentationContextProvider = AppKitOAuthPresentationContextProvider.shared
        PrefetchTemporaryStore.cleanupOrphans()
    }

    @StateObject private var cloudSyncCoordinator = CloudSyncCoordinator.shared

    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            VanmoMacRootView()
                .environmentObject(cloudSyncCoordinator)
                .frame(minWidth: 960, minHeight: 640)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
