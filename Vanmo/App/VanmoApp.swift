import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
import VanmoCore

@main
struct VanmoApp: App {
    init() {
        ColorTheme.migrateStoredValue()
        AppLanguage.lockForCurrentProcess()
        OAuthCoordinator.shared.presentationContextProvider = UIKitOAuthPresentationContextProvider.shared
        PrefetchTemporaryStore.cleanupOrphans()
        MediaProbeBootstrap.configure()
        ScanBackgroundTask.register()
        DownloadLiveActivityActionCenter.handler = { action in
            switch action {
            case .pause(let id):
                await DownloadManager.shared.pause(id)
            case .resume(let id):
                await DownloadManager.shared.resume(id)
            case .cancel(let id):
                await DownloadManager.shared.delete([id])
            }
        }
        Task {
            await OnlineSubtitleService.shared.register(OpenSubtitlesProvider())
            await OnlineSubtitleService.shared.register(ShooterSubtitleProvider())
            await OnlineSubtitleService.shared.register(SubhdSubtitleProvider())
        }
    }

    @StateObject private var appState = AppState()
    @StateObject private var connectionsViewModel = ConnectionsViewModel()
    @StateObject private var cloudSyncCoordinator = CloudSyncCoordinator.shared
    @UIApplicationDelegateAdaptor(VanmoAppDelegate.self) private var appDelegate
    @AppStorage(ColorTheme.storageKey) private var theme: ColorTheme = .system

    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(connectionsViewModel)
                .environmentObject(cloudSyncCoordinator)
                .environmentObject(DownloadManager.shared)
                .environmentObject(DownloadHeroController.shared)
                .preferredColorScheme(theme.preferredColorScheme)
                .id(theme)
        }
        .modelContainer(sharedModelContainer)
    }
}

final class VanmoAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : Self.orientationLock
    }
}
#endif
