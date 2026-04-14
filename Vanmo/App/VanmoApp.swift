import SwiftUI
import SwiftData

@main
struct VanmoApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearance.theme") private var appearance = AppearanceMode.system

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MediaItem.self,
            SavedConnection.self,
            PlaybackRecord.self,
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
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
