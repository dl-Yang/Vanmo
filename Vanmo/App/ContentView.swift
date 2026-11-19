import SwiftData
import SwiftUI
import VanmoCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @ObservedObject private var islandHandoff = DownloadIslandHandoff.shared
    @State private var isTabBarHidden = false
#if DEBUG
    /// 关闭播放器后 `.task` 会随根视图重新出现而重跑；调试起播每个进程只触发一次。
    private static var didOpenDebugPlayFile = false
#endif

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $appState.selectedTab) {
                NavigationStack {
                    LibraryView()
                }
                .accessibilityIdentifier("screen.library")
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.library)

                NavigationStack {
                    ConnectionsView()
                }
                .accessibilityIdentifier("screen.files")
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.connections)

                NavigationStack {
                    SearchView()
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.search)

                NavigationStack(path: $appState.settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsRoute.self) { route in
                            settingsDestination(for: route)
                        }
                }
                .accessibilityIdentifier("screen.settings")
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.settings)
            }
            .tint(CatDesign.accentAmber)

            if !isTabBarHidden {
                ZStack(alignment: .bottom) {
                    CatBottomBarScrim()
                        .transition(.opacity)
                    CatGlassTabBar(selectedTab: $appState.selectedTab)
                        .padding(.bottom, 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .onPreferenceChange(CatTabBarHiddenPreferenceKey.self) { hidden in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTabBarHidden = hidden
            }
        }
        .statusBarHidden(islandHandoff.hidesStatusBar)
        .modifier(PlayerPresentationModifier())
        .overlay {
            DownloadHeroHost()
        }
        .overlay(alignment: .top) {
            DownloadFallbackBarHost()
        }
        .overlay(alignment: .topLeading) {
            DownloadNotchStatusBarHost()
        }
        .overlay(alignment: .top) {
            DownloadIslandRingHost()
        }
        .onPreferenceChange(DownloadHeroFrameKey.self) { frames in
            if let source = frames["source"], DownloadHeroController.shared.sourceFrame != source {
                DispatchQueue.main.async {
                    DownloadHeroController.shared.sourceFrame = source
                }
            }
        }
        .onOpenURL { url in
            if YandexLoginAuthenticator.shared.handleOpenURL(url) { return }
            guard url.scheme == "vanmo", url.host == "downloads" else { return }
            appState.openDownloads()
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            _ = YandexLoginAuthenticator.shared.handleUserActivity(userActivity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            // 持久化到 AppState，避免 LibraryView 未挂载时通知丢失。
            appState.notifyFavoriteDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionLocalMediaWillDelete)) { notification in
            guard let connectionId = notification.object as? UUID else { return }
            appState.purgeMediaState(for: connectionId)
        }
        .onAppear {
            UITabBar.appearance().isHidden = true
            DownloadIslandHandoff.shared.applyStatusBarPolicy()
#if DEBUG
            IslandDebugDarwin.shared.openDownloadsHandler = { appState.openDownloads() }
#endif
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["VANMO_DEBUG_TAB"] == "files" {
                appState.selectedTab = .connections
            }
#endif
            connectionsViewModel.setModelContext(modelContext)
            DownloadManager.shared.configure(modelContext: modelContext)
            await DownloadManager.shared.restoreAndResume()
#if DEBUG
            let statuses = DownloadManager.shared.tasks.map(\.status.rawValue).joined(separator: ",")
            let restoreCount = DownloadManager.shared.tasks.count
            VanmoLogger.library.info("[Debug][Downloads] restore count=\(restoreCount, privacy: .public) statuses=\(statuses, privacy: .public)")
            for task in DownloadManager.shared.tasks where task.status != .completed {
                let taskID = task.id.uuidString
                let status = task.status.rawValue
                let received = task.receivedBytes
                let total = task.totalBytes
                VanmoLogger.library.info("[Debug][Downloads] restore task=\(taskID, privacy: .public) status=\(status, privacy: .public) received=\(received, privacy: .public) total=\(total, privacy: .public)")
            }
#endif
            await connectionsViewModel.attemptAutoReconnectIfNeeded()
            await cloudSyncCoordinator.performSync(reason: "app-launch", context: modelContext)
            await connectionsViewModel.loadSavedConnections()
            _ = await connectionsViewModel.activateNewlySyncedConnections()
#if DEBUG
            if let kind = DownloadHeroWalkFixtures.requestedKind {
                do {
                    let item = try DownloadHeroWalkFixtures.seedItem(kind: kind, in: modelContext)
                    appState.selectedTab = .library
                    NotificationCenter.default.post(
                        name: DownloadHeroWalkFixtures.openDetailNotification,
                        object: item.id
                    )
                    let kindName = kind.rawValue
                    VanmoLogger.library.info("[Debug][Downloads] hero walk presented kind=\(kindName, privacy: .public)")
                } catch {
                    VanmoLogger.library.error("[Debug][Downloads] hero walk seed failed")
                }
            }
            let debugPlayURL = ProcessInfo.processInfo.environment["VANMO_DEBUG_PLAY_FILE"].map { path in
                path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
            }
            if !Self.didOpenDebugPlayFile, let url = debugPlayURL, FileManager.default.fileExists(atPath: url.path) {
                Self.didOpenDebugPlayFile = true
                let descriptor = FetchDescriptor<MediaItem>()
                let existing = try? modelContext.fetch(descriptor).first { $0.fileURL.path == url.path }
                let item = existing ?? MediaItem(
                    title: "Player Walk",
                    fileURL: url,
                    mediaType: .movie,
                    duration: 3
                )
                if existing == nil {
                    item.originalFileName = url.lastPathComponent
                    modelContext.insert(item)
                    try? modelContext.save()
                }
                appState.play(item)
                VanmoLogger.player.info("[Debug][Player] debug play file opened")
            }
#endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                DownloadManager.shared.resume()
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                Task {
                    await cloudSyncCoordinator.performSync(reason: "foreground", context: modelContext)
                    await connectionsViewModel.loadSavedConnections()
                    _ = await connectionsViewModel.activateNewlySyncedConnections()
                }
            } else if newPhase == .inactive, oldPhase == .active {
                // Request before the home snapshot so iOS can absorb the scene into the island.
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
            } else if newPhase == .background {
                DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                Task {
                    await DownloadManager.shared.suspend()
                    guard DownloadIslandHandoff.shared.isParked else { return }
                    DownloadLiveActivityBridge.shared.sync(tasks: DownloadManager.shared.tasks)
                }
            }
        }
        .sheet(item: $connectionsViewModel.pendingMissingCredentialConnection) { connection in
            AddConnectionView(viewModel: connectionsViewModel, editingConnection: connection)
        }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .iCloudSync:
            ICloudSyncSettingsView()
        case .playback:
            PlaybackSettingsView()
        case .audio:
            AudioSettingsView()
        case .subtitles:
            SubtitlesSettingsView()
        case .libraryScan:
            LibraryScanSettingsView()
        case .metadataCache:
            MetadataCacheSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .storage:
            StorageDownloadsSettingsView()
        case .downloads:
            DownloadManagementView()
        }
    }
}

private struct PlayerPresentationModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .background {
                LandscapePlayerPresenter(
                    item: appState.currentPlayingItem,
                    isPresented: appState.isPlayerPresented,
                    modelContext: modelContext,
                    onDismiss: { appState.stopPlayback() }
                )
                .frame(width: 0, height: 0)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ConnectionsViewModel())
        .environmentObject(CloudSyncCoordinator.shared)
        .environmentObject(DownloadManager.shared)
        .environmentObject(DownloadHeroController.shared)
}
