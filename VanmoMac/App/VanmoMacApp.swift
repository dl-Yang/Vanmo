import SwiftData
import SwiftUI
import VanmoCore

@main
struct VanmoMacApp: App {
    init() {
        OAuthCoordinator.shared.presentationContextProvider = AppKitOAuthPresentationContextProvider.shared
        PrefetchTemporaryStore.cleanupOrphans()
        Task {
            await OnlineSubtitleService.shared.register(OpenSubtitlesProvider())
            await OnlineSubtitleService.shared.register(ShooterSubtitleProvider())
            await OnlineSubtitleService.shared.register(SubhdSubtitleProvider())
        }
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

            CommandMenu("播放") {
                Button("播放/暂停") {
                    MacPlayerCommandRouter.post(.macPlayerTogglePlayPause)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("后退 15 秒") {
                    MacPlayerCommandRouter.post(.macPlayerSkipBackward)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("前进 15 秒") {
                    MacPlayerCommandRouter.post(.macPlayerSkipForward)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Divider()

                Button("增大音量") {
                    MacPlayerCommandRouter.post(.macPlayerVolumeUp)
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("减小音量") {
                    MacPlayerCommandRouter.post(.macPlayerVolumeDown)
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Divider()

                Button("切换全屏") {
                    MacPlayerCommandRouter.post(.macPlayerToggleFullScreen)
                }
                .keyboardShortcut("f", modifiers: [])

                Button("关闭播放器") {
                    MacPlayerCommandRouter.post(.macPlayerClose)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.selectSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
