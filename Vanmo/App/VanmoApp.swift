import SwiftUI
import SwiftData

#if os(iOS)
import UIKit

@main
struct VanmoApp: App {
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
    @UIApplicationDelegateAdaptor(VanmoAppDelegate.self) private var appDelegate
    @AppStorage(ColorTheme.storageKey) private var theme: ColorTheme = .system

    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(connectionsViewModel)
                .environmentObject(cloudSyncCoordinator)
                .preferredColorScheme(theme.preferredColorScheme)
                .id(theme)
        }
        .modelContainer(sharedModelContainer)
    }
}

final class VanmoAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

enum AppOrientation {
    @MainActor
    static func lockForPlayer() {
        VanmoAppDelegate.orientationLock = .landscape
        requestGeometryUpdate(.landscape)
    }

    @MainActor
    static func restoreDefault() {
        VanmoAppDelegate.orientationLock = .allButUpsideDown
        requestGeometryUpdate(.allButUpsideDown)
    }

    @MainActor
    private static func requestGeometryUpdate(_ orientations: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
            #if DEBUG
            VanmoLogger.player.debug("[Debug][Player] Orientation update failed: \(error.localizedDescription)")
            #endif
        }
    }
}
#endif
