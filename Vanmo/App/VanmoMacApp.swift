import SwiftUI
import SwiftData

#if os(macOS)

@main
struct VanmoMacApp: App {
    init() {
        PrefetchTemporaryStore.cleanupOrphans()
        Task {
            await OnlineSubtitleService.shared.register(OpenSubtitlesProvider())
            await OnlineSubtitleService.shared.register(ShooterSubtitleProvider())
            await OnlineSubtitleService.shared.register(SubhdSubtitleProvider())
        }
    }

    @StateObject private var appState = AppState()
    @StateObject private var connectionsViewModel = ConnectionsViewModel()
    @StateObject private var cloudSyncCoordinator = CloudSyncCoordinator.shared
    @AppStorage(ColorTheme.storageKey) private var theme: ColorTheme = .system

    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(connectionsViewModel)
                .environmentObject(cloudSyncCoordinator)
                .preferredColorScheme(theme.preferredColorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

#endif
