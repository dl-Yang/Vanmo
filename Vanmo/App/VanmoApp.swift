import SwiftUI
import SwiftData
import UIKit

@main
struct VanmoApp: App {
    init() {
        PrefetchTemporaryStore.cleanupOrphans()
    }

    @StateObject private var appState = AppState()
    @StateObject private var connectionsViewModel = ConnectionsViewModel()
    @UIApplicationDelegateAdaptor(VanmoAppDelegate.self) private var appDelegate
    @AppStorage(ColorTheme.storageKey) private var theme: ColorTheme = .system

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MediaItem.self,
            SavedConnection.self,
            PlaybackRecord.self,
            FolderBookmark.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(connectionsViewModel)
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
