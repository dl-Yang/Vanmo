import SwiftUI
import SwiftData
import Combine
import VanmoCore

enum ConnectionStatus {
    case idle
    case connecting
    case connected
    case failed
}

struct FolderBookmarkNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let connectionId: UUID
    let path: String
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = "连接中..."
    @Published private(set) var librarySyncMessage: String?
    @Published private(set) var librarySyncCompletionID = 0
    @Published private(set) var activeMediaServerConnectionID: UUID?
    @Published private(set) var connectionErrorMessages: [UUID: String] = [:]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var currentPath = "/"
    @Published private(set) var pathStack: [String] = []
    @Published private(set) var files: [RemoteFile] = []
    @Published private(set) var isBrowsingFiles = false
    @Published private(set) var epgGuide = EPGGuide(programsByChannel: [:])
    @Published private(set) var isLoadingEPG = false
    @Published private(set) var failedChannelPaths: Set<String> = []
    @Published private(set) var fileBrowserErrorMessage: String?
    @Published private(set) var pendingFolderBookmarkNavigation: FolderBookmarkNavigationRequest?
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var scanCoordinator = ScanCoordinator()
    @Published var scanToastMessage: String?

    private var connectionStatuses: [UUID: ConnectionStatus] = [:]
    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    private var browserService: RemoteFileService?
    private var browserServiceConnectionID: UUID?
    private var epgLoadID: UUID?
    /// 仅 localFolder 用：保留正在持有 security-scoped access 的 service 实例，
    /// 让 App 生命周期内 file:// URL 始终可读，避免播放时权限失效。
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    private static let activeMediaServerKey = "activeMediaServerConnectionID"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.activeMediaServerKey),
           let id = UUID(uuidString: raw) {
            activeMediaServerConnectionID = id
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        configureMediaProbeQueue(context: context)
    }

    private func configureMediaProbeQueue(context: ModelContext) {
        MediaProbeBootstrap.configure()
        Task {
            await MediaProbeQueue.shared.setURLResolver { item in
                try await Self.resolveProbeURL(for: item, context: context)
            }
        }
    }

    private static func resolveProbeURL(for item: MediaItem, context: ModelContext) async throws -> URL {
        if !PlaybackURLResolver.isPlaceholder(item.fileURL) {
            return item.fileURL
        }
        guard let connectionId = item.sourceConnectionId else {
            throw NetworkError.invalidURL
        }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        let connection: SavedConnection? = await MainActor.run {
            try? context.fetch(descriptor).first
        }
        guard let connection else {
            throw NetworkError.notConnected
        }
        let service = RemoteServiceFactory.create(for: connection.type)
        let password = try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
        try await service.connect(config: ConnectionConfig(from: connection, password: password))
        defer { Task { await service.disconnect() } }
        return try await PlaybackURLResolver.resolvePlaybackURL(item: item, service: service)
    }

    private func isMediaServer(_ type: ConnectionType) -> Bool {
        type == .emby || type == .jellyfin || type == .plex
    }

    private func persistActiveMediaServerID() {
        if let id = activeMediaServerConnectionID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeMediaServerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeMediaServerKey)
        }
    }

    /// 兼容旧版本的最近媒体服务器记录；媒体库展示不再依赖单一 active server。
    private func setActiveMediaServer(_ connection: SavedConnection) {
        activeMediaServerConnectionID = connection.id
        persistActiveMediaServerID()
    }

    func connectionStatus(for connection: SavedConnection) -> ConnectionStatus {
        connectionStatuses[connection.id] ?? .idle
    }

    func connectionErrorMessage(for connection: SavedConnection) -> String? {
        connectionErrorMessages[connection.id]
    }

    var selectedConnection: SavedConnection? {
        guard let selectedConnectionID else { return nil }
        return savedConnections.first { $0.id == selectedConnectionID }
    }

    var canBookmarkFoldersInSelectedConnection: Bool {
        guard let selectedConnection else { return false }
        switch selectedConnection.type {
        case .localFolder, .smb, .webdav, .alist, .fnos:
            return true
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk, .baiduNetdisk:
            return true
        default:
            return false
        }
    }

    func loadSavedConnections() async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SavedConnection>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.lastConnectedAt, order: .reverse)]
            )
            savedConnections = try context.fetch(descriptor)
            await reconcileActiveMediaServer()
            reconcileSelectedConnection()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func loadSelectedConnectionRootIfNeeded() async {
        guard !savedConnections.isEmpty else {
            resetFileBrowser()
            return
        }
        guard files.isEmpty, fileBrowserErrorMessage == nil else { return }
        await loadDirectory(path: "/")
    }

    /// 应用启动时尝试自动重连最近一次成功连接过的服务。
    /// 在整个 App 生命周期内只会触发一次。失败时静默处理，不打扰用户。
    func attemptAutoReconnectIfNeeded() async {
        guard !didAttemptAutoReconnect else { return }
        didAttemptAutoReconnect = true

        if savedConnections.isEmpty {
            await loadSavedConnections()
        }

        // 优先恢复所有本地文件夹的 security-scoped access，让媒体库里的本地视频
        // 在 App 启动后无需用户重新进入"连接"页就能直接播放。
        await restoreLocalFolderAccess()

        // 优先重连上次激活的媒体服务器；否则回退到 lastConnectedAt 最近的连接。
        let target: SavedConnection?
        if let activeID = activeMediaServerConnectionID,
           let active = savedConnections.first(where: { $0.id == activeID }) {
            target = active
        } else {
            // savedConnections 已按 lastConnectedAt 倒序排列。
            target = savedConnections.first(where: { $0.lastConnectedAt != nil })
        }

        guard let target else {
            VanmoLogger.network.info("[Connections] Auto-reconnect skipped: no previous connection")
            return
        }

        guard UserDefaults.standard.object(forKey: "library.autoScan") as? Bool ?? true else {
            VanmoLogger.network.info("[Connections] Auto-reconnect skipped: library.autoScan disabled")
            return
        }

        VanmoLogger.network.info("[Connections] Auto-reconnect to \(target.name)")
        await connectAndScan(target, showErrorAlert: false)
    }

    /// 仅打开本地文件夹的 bookmark 并保持 access，不触发扫描。
    private func restoreLocalFolderAccess() async {
        for connection in savedConnections where connection.type == .localFolder {
            guard activeLocalServices[connection.id] == nil else { continue }
            guard connection.bookmarkData != nil else { continue }

            let service = LocalFolderService()
            let config = ConnectionConfig(from: connection)
            do {
                try await service.connect(config: config)
                activeLocalServices[connection.id] = service
                VanmoLogger.network.info("[Connections] Restored local access: \(connection.name)")
            } catch {
                VanmoLogger.network.error("[Connections] Restore local access failed for \(connection.name): \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func connectAndScan(
        _ connection: SavedConnection,
        showErrorAlert: Bool = true,
        forceFullScan: Bool = false,
        scanPath: String? = nil,
        isPartialScan: Bool = false
    ) async -> Bool {
        connectionStatuses[connection.id] = .connecting
        isLoading = true
        loadingMessage = forceFullScan ? "全量重扫 \(connection.name)..." : "连接到 \(connection.name)..."
        librarySyncMessage = "正在连接 \(connection.name)..."

        VanmoLogger.network.info("[Connections] Connecting to \(connection.name) (\(connection.type.rawValue)://\(connection.host):\(connection.port)) fullScan=\(forceFullScan)")

        let isLocal = connection.type == .localFolder

        do {
            let service: RemoteFileService
            if isLocal {
                if let cached = activeLocalServices[connection.id] {
                    service = cached
                } else {
                    let local = LocalFolderService()
                    let config = ConnectionConfig(from: connection)
                    try await local.connect(config: config)
                    activeLocalServices[connection.id] = local
                    service = local
                }
            } else {
                let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
                let config = ConnectionConfig(from: connection, password: password)
                let remote = RemoteServiceFactory.create(for: connection.type)
                try await remote.connect(config: config)
                service = remote
            }

            connectionStatuses[connection.id] = .connected
            connectionErrorMessages.removeValue(forKey: connection.id)
            connection.lastConnectedAt = Date()
            try? modelContext?.save()

            // 记录最近同步的媒体服务器用于旧版本兼容；首页会聚合所有已保存媒体服务器。
            if isMediaServer(connection.type) {
                setActiveMediaServer(connection)
            }

            let requiresDirectorySelection = connection.type.requiresManualDirectorySync
            let shouldScanRemoteFiles = !requiresDirectorySelection || scanPath != nil

            guard let context = modelContext else {
                isLoading = false
                librarySyncMessage = nil
                librarySyncCompletionID += 1
                return true
            }

            let scanner = MediaScanner(modelContainer: context.container)
            var shouldRefreshLibrary = true
            var partialSyncNotice: String?

            if shouldScanRemoteFiles {
                loadingMessage = forceFullScan ? "全量重扫 \(connection.name)..." : "扫描媒体文件..."
                librarySyncMessage = "正在同步数据..."
            } else {
                loadingMessage = "已连接 \(connection.name)"
                librarySyncMessage = nil
                shouldRefreshLibrary = false
            }

            if let mediaServer = service as? MediaServerService,
               connection.type != .emby,
               connection.type != .jellyfin {
                let since: Date? = forceFullScan ? nil : connection.lastSyncedAt
                let syncStart = Date()
                var totalImported = 0
                for try await page in mediaServer.streamMediaItems(since: since, pageSize: 500) {
                    let inserted = try await scanner.importServerMediaItems(
                        page,
                        connectionId: connection.id,
                        in: context
                    )
                    totalImported += inserted.count
                    let message = "已同步 \(totalImported) 项..."
                    loadingMessage = message
                    librarySyncMessage = message
                }
                connection.lastSyncedAt = syncStart
                try? modelContext?.save()
            } else if connection.type != .emby && connection.type != .jellyfin, shouldScanRemoteFiles {
                let resolvedScanPath = scanPath ?? connection.path ?? "/"
                let scope: ScanScope = isPartialScan ? .directory(path: resolvedScanPath) : .connectionRoot
                isLoading = false

                let scanResult = await performCoordinatorScan(
                    connection: connection,
                    service: service,
                    scope: scope,
                    forceFullScan: forceFullScan,
                    context: context
                )
                if scanResult.status == .completed || scanResult.status == .partial {
                    connection.lastSyncedAt = Date()
                    try? modelContext?.save()
                }
                publishScanFeedback(scanResult, showErrorAlert: showErrorAlert, partialSyncNotice: &partialSyncNotice)
                shouldRefreshLibrary = scanResult.hasLibraryChanges
            }

            // 本地文件夹保持 access，让媒体库里的视频后续可直接播放；
            // 远端协议照常释放连接。
            if !isLocal {
                await service.disconnect()
            }

            VanmoLogger.network.info("[Connections] Scan complete for \(connection.name)")
            isLoading = false
            if let partialSyncNotice {
                errorMessage = partialSyncNotice
                showError = true
            }
            librarySyncMessage = nil
            if shouldRefreshLibrary {
                librarySyncCompletionID += 1
            }
            return true
        } catch {
            VanmoLogger.network.error("[Connections] Connection failed: \(error.localizedDescription)")
            connectionStatuses[connection.id] = .failed
            connectionErrorMessages[connection.id] = error.localizedDescription
            if showErrorAlert {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            librarySyncMessage = nil
            if connection.type.isMediaServer {
                librarySyncCompletionID += 1
            }
            return false
        }
    }

    @discardableResult
    func saveConnection(
        name: String,
        type: ConnectionType,
        host: String,
        port: Int,
        username: String?,
        password: String?,
        path: String?,
        bookmarkData: Data? = nil
    ) async -> Bool {
        let connection = SavedConnection(
            name: name,
            type: type,
            host: host,
            port: port,
            username: username,
            path: path,
            bookmarkData: bookmarkData
        )

        modelContext?.insert(connection)

        if let password, !password.isEmpty {
            try? KeychainManager.shared.save(password, for: "conn_\(connection.id)")
        }

        try? modelContext?.save()
        CloudSyncCoordinator.shared.markConnectionChanged(connection)
        CloudSyncCoordinator.shared.requestSync(reason: "connection-created", context: modelContext)
        await loadSavedConnections()
        if let saved = savedConnections.first(where: { $0.id == connection.id }) {
            await selectConnection(saved)
            // 添加连接后立即建立连接；目录型源须用户在浏览页手动「同步当前目录」入库。
            return await connectAndScan(saved, showErrorAlert: true)
        }
        return false
    }

    @discardableResult
    func updateConnection(
        _ connection: SavedConnection,
        name: String,
        host: String,
        port: Int,
        username: String?,
        password: String?,
        path: String?,
        bookmarkData: Data? = nil
    ) async -> Bool {
        guard let context = modelContext else { return false }

        if let password, !password.isEmpty {
            do {
                try KeychainManager.shared.save(password, for: "conn_\(connection.id)")
            } catch {
                errorMessage = "保存密码失败: \(error.localizedDescription)"
                showError = true
                return false
            }
        }

        connection.name = name
        connection.host = host
        connection.port = port
        connection.username = username
        connection.path = path
        connection.bookmarkData = bookmarkData
        CloudSyncCoordinator.shared.markConnectionChanged(connection)
        updateFolderBookmarkConnectionNames(for: connection.id, to: name, in: context)

        do {
            try context.save()
            CloudSyncCoordinator.shared.requestSync(reason: "connection-updated", context: context)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }

        await resetCachedServiceAfterEditing(connection)
        resetBrowserStateAfterEditing(connection)
        connectionStatuses[connection.id] = .idle
        connectionErrorMessages.removeValue(forKey: connection.id)
        await loadSavedConnections()
        return true
    }

    /// 发起 OAuth 网盘登录：授权成功后落地连接并进入浏览；入库须用户在目录内手动「同步当前目录」。
    @discardableResult
    func beginOAuthConnection(type: ConnectionType, name: String?) async -> Bool {
        guard type.supportsOAuthLogin else { return false }

        let connectionId = UUID()
        do {
            let credential = try await OAuthCoordinator.shared.authenticate(type: type)
            try OAuthCredentialStore.save(credential, connectionId: connectionId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }

        let connection = SavedConnection(
            name: (name?.isEmpty == false ? name! : type.displayName),
            type: type,
            host: "oauth",
            port: type.defaultPort,
            username: nil,
            path: nil
        )
        connection.id = connectionId

        modelContext?.insert(connection)
        try? modelContext?.save()
        CloudSyncCoordinator.shared.markConnectionChanged(connection)
        CloudSyncCoordinator.shared.requestSync(reason: "oauth-connection-created", context: modelContext)
        await loadSavedConnections()

        guard let saved = savedConnections.first(where: { $0.id == connectionId }) else {
            return false
        }
        await selectConnection(saved)
        return await connectAndScan(saved, showErrorAlert: true)
    }

    /// 重新走一遍 OAuth 授权码流程，覆盖写入已有连接的凭据（用于 refresh token 失效等场景）。
    @discardableResult
    func reauthenticateOAuthConnection(_ connection: SavedConnection) async -> Bool {
        guard connection.type.supportsOAuthLogin else { return false }

        do {
            let credential = try await OAuthCoordinator.shared.authenticate(type: connection.type)
            try OAuthCredentialStore.save(credential, connectionId: connection.id)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }

        connectionStatuses[connection.id] = .idle
        connectionErrorMessages.removeValue(forKey: connection.id)
        return await connectAndScan(connection, showErrorAlert: true)
    }

    func deleteConnection(_ connection: SavedConnection) {
        let connectionId = connection.id
        let isMediaServerConnection = connection.type.isMediaServer

        try? KeychainManager.shared.delete(for: "conn_\(connection.id)")
        if connection.type.supportsOAuthLogin {
            try? OAuthCredentialStore.delete(connectionId: connection.id)
        }

        let deletedActiveMediaServer = activeMediaServerConnectionID == connection.id && isMediaServer(connection.type)
        if deletedActiveMediaServer {
            activeMediaServerConnectionID = nil
            persistActiveMediaServerID()
        }

        if let active = activeLocalServices.removeValue(forKey: connection.id) {
            Task { await active.disconnect() }
        }

        if browserServiceConnectionID == connection.id {
            let service = browserService
            browserService = nil
            browserServiceConnectionID = nil
            if !(service is LocalFolderService) {
                Task { await service?.disconnect() }
            }
        }

        deleteMediaItems(for: connectionId)
        deleteFolderBookmarks(for: connectionId)
        modelContext?.delete(connection)
        try? modelContext?.save()
        CloudSyncCoordinator.shared.requestSync(reason: "connection-deleted", context: modelContext)
        connectionStatuses.removeValue(forKey: connectionId)
        connectionErrorMessages.removeValue(forKey: connectionId)
        let deletedSelectedConnection = selectedConnectionID == connectionId
        if deletedSelectedConnection {
            resetFileBrowser()
        }
        Task {
            await HomeCollectionCache.shared.removeConnection(connectionId)
            await loadSavedConnections()
            if deletedSelectedConnection {
                await loadSelectedConnectionRootIfNeeded()
            }
            if isMediaServerConnection {
                librarySyncCompletionID += 1
            }
        }
    }

    private func resetCachedServiceAfterEditing(_ connection: SavedConnection) async {
        if let active = activeLocalServices.removeValue(forKey: connection.id) {
            await active.disconnect()
        }

        if browserServiceConnectionID == connection.id {
            await disconnectBrowserServiceIfNeeded()
        }
    }

    private func resetBrowserStateAfterEditing(_ connection: SavedConnection) {
        guard selectedConnectionID == connection.id else { return }
        currentPath = connection.browserRootPath
        pathStack = []
        files = []
        isBrowsingFiles = false
        fileBrowserErrorMessage = nil
        resetIPTVState()
    }

    private func updateFolderBookmarkConnectionNames(
        for connectionId: UUID,
        to connectionName: String,
        in context: ModelContext
    ) {
        let targetConnectionId = connectionId
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId
            }
        )

        do {
            let bookmarks = try context.fetch(descriptor)
            for bookmark in bookmarks {
                bookmark.connectionName = connectionName
            }
        } catch {
            VanmoLogger.library.error("[Connections] Update folder bookmark names failed: \(error.localizedDescription)")
        }
    }

    private func deleteMediaItems(for connectionId: UUID) {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate<MediaItem> { item in
                    item.sourceConnectionId == connectionId
                }
            )
            let items = try context.fetch(descriptor)
            for item in items {
                context.delete(item)
            }
        } catch {
            VanmoLogger.library.error("[Connections] Delete cached media failed: \(error.localizedDescription)")
        }
    }

    func isFolderBookmarked(_ file: RemoteFile) -> Bool {
        guard file.isDirectory,
              let connectionId = selectedConnectionID else {
            return false
        }
        return folderBookmark(connectionId: connectionId, path: file.path) != nil
    }

    func toggleFolderBookmark(_ file: RemoteFile) {
        guard file.isDirectory,
              canBookmarkFoldersInSelectedConnection,
              let context = modelContext,
              let connection = selectedConnection else {
            return
        }

        if let existing = folderBookmark(connectionId: connection.id, path: file.path) {
            context.delete(existing)
        } else {
            let bookmark = FolderBookmark(
                title: folderBookmarkTitle(for: file),
                connectionId: connection.id,
                connectionName: connection.name,
                path: file.path
            )
            context.insert(bookmark)
            CloudSyncCoordinator.shared.markFolderBookmarkChanged(bookmark)
        }
        do {
            try context.save()
            CloudSyncCoordinator.shared.requestSync(reason: "folder-bookmark", context: context)
        } catch {
            VanmoLogger.library.error("[FolderBookmark] Save failed: \(error.localizedDescription)")
        }
    }

    func requestOpenFolderBookmark(_ bookmark: FolderBookmark) {
        pendingFolderBookmarkNavigation = FolderBookmarkNavigationRequest(
            connectionId: bookmark.connectionId,
            path: bookmark.path
        )
    }

    func openFolderBookmarkRequest(_ request: FolderBookmarkNavigationRequest) async -> Bool {
        if savedConnections.isEmpty {
            await loadSavedConnections()
        }

        guard let connection = savedConnections.first(where: { $0.id == request.connectionId }) else {
            if pendingFolderBookmarkNavigation?.id == request.id {
                pendingFolderBookmarkNavigation = nil
            }
            return false
        }

        if selectedConnectionID != connection.id {
            selectedConnectionID = connection.id
            currentPath = "/"
            pathStack = []
            files = []
            fileBrowserErrorMessage = nil
            await disconnectBrowserServiceIfNeeded()
        }

        pathStack = []
        let didLoad = await loadDirectory(path: request.path)
        if pendingFolderBookmarkNavigation?.id == request.id {
            pendingFolderBookmarkNavigation = nil
        }
        return didLoad
    }

    private func folderBookmark(connectionId: UUID, path: String) -> FolderBookmark? {
        guard let context = modelContext else { return nil }
        let targetConnectionId = connectionId
        let targetPath = path
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId && bookmark.path == targetPath && bookmark.deletedAt == nil
            }
        )
        return try? context.fetch(descriptor).first
    }

    private func folderBookmarkTitle(for file: RemoteFile) -> String {
        let trimmed = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let last = (file.path as NSString).lastPathComponent
        return last.isEmpty ? file.path : last
    }

    private func deleteFolderBookmarks(for connectionId: UUID) {
        guard let context = modelContext else { return }
        let targetConnectionId = connectionId
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId
            }
        )
        do {
            let bookmarks = try context.fetch(descriptor)
            for bookmark in bookmarks {
                context.delete(bookmark)
            }
        } catch {
            VanmoLogger.library.error("[Connections] Delete folder bookmarks failed: \(error.localizedDescription)")
        }
    }

    func selectConnection(_ connection: SavedConnection) async {
        let isSameConnection = selectedConnectionID == connection.id
        if !isSameConnection {
            selectedConnectionID = connection.id
            currentPath = connection.browserRootPath
            pathStack = []
            files = []
            fileBrowserErrorMessage = nil
            resetIPTVState()
            await disconnectBrowserServiceIfNeeded()
        }
        await loadDirectory(path: currentPath)
    }

    @discardableResult
    func loadDirectory(path: String) async -> Bool {
        guard let connection = selectedConnection else {
            resetFileBrowser()
            return false
        }

        isBrowsingFiles = true
        fileBrowserErrorMessage = nil
        connectionStatuses[connection.id] = .connecting

        do {
            let service = try await browserFileService(for: connection)
            let normalizedPath = resolvedBrowserPath(path, for: connection)
            let listedFiles = try await service.listDirectory(path: normalizedPath)
            files = listedFiles.sorted(by: fileSortPredicate)
            currentPath = normalizedPath
            connectionStatuses[connection.id] = .connected
            connection.lastConnectedAt = Date()
            try? modelContext?.save()
            isBrowsingFiles = false
            if connection.type == .iptv {
                await loadEPGGuide(from: service, connectionID: connection.id)
            } else {
                resetIPTVState()
            }
            return true
        } catch {
            VanmoLogger.network.error("[Files] Failed to browse \(connection.name): \(error.localizedDescription)")
            files = []
            fileBrowserErrorMessage = userFacingFileBrowserMessage(for: error, connection: connection)
            if case NetworkError.sharePathRequired = error {
                connectionStatuses[connection.id] = .connected
            } else {
                connectionStatuses[connection.id] = .failed
            }
            isBrowsingFiles = false
            return false
        }
    }

    func openDirectory(_ file: RemoteFile) async {
        guard file.isDirectory else { return }
        let previousPath = currentPath
        if await loadDirectory(path: file.path) {
            pathStack.append(previousPath)
        }
    }

    func goBackDirectory() async {
        guard let previousPath = pathStack.popLast() else { return }
        if !(await loadDirectory(path: previousPath)) {
            pathStack.append(previousPath)
        }
    }

    func refreshCurrentDirectory() async {
        // IPTV 频道列表在 connect() 时一次性下载解析并缓存在 service 内存中，
        // 普通 listDirectory 不会重新拉取 M3U；刷新时强制重建 service 以重新下载播放列表。
        if selectedConnection?.type == .iptv {
            resetIPTVState()
            await disconnectBrowserServiceIfNeeded()
        }
        await loadDirectory(path: currentPath)
    }

    func scanSelectedConnection(forceFullScan: Bool = false) async -> Bool {
        guard let selectedConnection else { return false }
        if selectedConnection.type.requiresManualDirectorySync {
            return await connectAndScan(
                selectedConnection,
                forceFullScan: forceFullScan,
                scanPath: currentPath,
                isPartialScan: true
            )
        }
        return await connectAndScan(selectedConnection, forceFullScan: forceFullScan)
    }

    func scanCurrentDirectory(forceFullScan: Bool = false) async -> Bool {
        guard let selectedConnection else { return false }
        return await connectAndScan(
            selectedConnection,
            forceFullScan: forceFullScan,
            scanPath: currentPath,
            isPartialScan: true
        )
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let connection = selectedConnection else {
            throw NetworkError.notConnected
        }
        let service = try await browserFileService(for: connection)
        return try await service.streamURL(for: file)
    }

    func markChannelPlaybackFailed(_ file: RemoteFile) {
        failedChannelPaths.insert(file.path)
    }

    func isChannelPlaybackFailed(_ file: RemoteFile) -> Bool {
        failedChannelPaths.contains(file.path)
    }

    private func reconcileSelectedConnection() {
        if savedConnections.isEmpty {
            resetFileBrowser()
            return
        }

        if let selectedConnectionID,
           savedConnections.contains(where: { $0.id == selectedConnectionID }) {
            return
        }

        selectedConnectionID = savedConnections.first?.id
        currentPath = savedConnections.first?.browserRootPath ?? "/"
        pathStack = []
        files = []
        fileBrowserErrorMessage = nil
    }

    private func reconcileActiveMediaServer() async {
        guard let activeMediaServerConnectionID else { return }
        guard savedConnections.contains(where: { $0.id == activeMediaServerConnectionID && isMediaServer($0.type) }) else {
            self.activeMediaServerConnectionID = nil
            persistActiveMediaServerID()
            return
        }
    }

    private func loadEPGGuide(from service: RemoteFileService, connectionID: UUID) async {
        guard let iptvService = service as? IPTVService else {
            epgGuide = EPGGuide(programsByChannel: [:])
            isLoadingEPG = false
            return
        }

        let loadID = UUID()
        epgLoadID = loadID
        isLoadingEPG = true
        let guide = await iptvService.fetchEPGGuide()
        guard epgLoadID == loadID,
              selectedConnectionID == connectionID,
              selectedConnection?.type == .iptv else {
            return
        }
        epgGuide = guide
        isLoadingEPG = false
    }

    private func resetIPTVState() {
        epgLoadID = nil
        epgGuide = EPGGuide(programsByChannel: [:])
        isLoadingEPG = false
        failedChannelPaths = []
    }

    private func resetFileBrowser() {
        selectedConnectionID = nil
        currentPath = "/"
        pathStack = []
        files = []
        isBrowsingFiles = false
        fileBrowserErrorMessage = nil
        resetIPTVState()
    }

    private func browserFileService(for connection: SavedConnection) async throws -> RemoteFileService {
        if browserServiceConnectionID == connection.id, let browserService {
            return browserService
        }

        await disconnectBrowserServiceIfNeeded()

        let service: RemoteFileService
        if connection.type == .localFolder {
            if let cached = activeLocalServices[connection.id] {
                service = cached
            } else {
                let local = LocalFolderService()
                try await local.connect(config: ConnectionConfig(from: connection))
                activeLocalServices[connection.id] = local
                service = local
            }
        } else {
            let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            let remote = RemoteServiceFactory.create(for: connection.type)
            try await remote.connect(config: ConnectionConfig(from: connection, password: password))
            service = remote
        }

        browserService = service
        browserServiceConnectionID = connection.id
        return service
    }

    private func disconnectBrowserServiceIfNeeded() async {
        guard let browserService else { return }
        if !(browserService is LocalFolderService) {
            await browserService.disconnect()
        }
        self.browserService = nil
        browserServiceConnectionID = nil
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private func resolvedBrowserPath(_ path: String, for connection: SavedConnection) -> String {
        let normalized = normalizedDirectoryPath(path)
        if normalized == "/" {
            return connection.browserRootPath
        }
        return normalized
    }

    private func fileSortPredicate(_ lhs: RemoteFile, _ rhs: RemoteFile) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    func pauseScan() {
        scanCoordinator.pause()
    }

    func resumeScan() {
        scanCoordinator.resume()
    }

    func cancelScan() {
        scanCoordinator.cancel()
    }

    func syncAllBookmarks(for connection: SavedConnection) async -> Bool {
        guard let context = modelContext else { return false }
        let targetConnectionId = connection.id
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId && bookmark.deletedAt == nil
            }
        )
        guard let bookmarks = try? context.fetch(descriptor), !bookmarks.isEmpty else { return false }
        return await syncBookmarks(connection: connection, bookmarks: bookmarks)
    }

    func syncBookmark(_ bookmark: FolderBookmark) async -> Bool {
        await syncBookmarks(connection: nil, bookmarks: [bookmark], explicitConnectionId: bookmark.connectionId)
    }

    private func syncBookmarks(
        connection: SavedConnection?,
        bookmarks: [FolderBookmark],
        explicitConnectionId: UUID? = nil
    ) async -> Bool {
        guard let context = modelContext else { return false }
        let connectionId = connection?.id ?? explicitConnectionId
        guard let connectionId,
              let resolvedConnection = connection ?? savedConnections.first(where: { $0.id == connectionId }) else {
            return false
        }

        do {
            let service = try await browserFileService(for: resolvedConnection)
            let result = await performCoordinatorScan(
                connection: resolvedConnection,
                service: service,
                scope: .bookmarks(paths: bookmarks.map(\.path)),
                forceFullScan: false,
                context: context
            )
            var notice: String?
            publishScanFeedback(result, showErrorAlert: true, partialSyncNotice: &notice)
            return result.status == .completed || result.status == .partial
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
    }

    private func performCoordinatorScan(
        connection: SavedConnection,
        service: RemoteFileService,
        scope: ScanScope,
        forceFullScan: Bool,
        context: ModelContext
    ) async -> ScanResult {
        await withCheckedContinuation { continuation in
            scanCoordinator.start(
                connection: connection,
                service: service,
                scope: scope,
                forceFullScan: forceFullScan,
                modelContainer: context.container,
                context: context
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func publishScanFeedback(
        _ result: ScanResult,
        showErrorAlert: Bool,
        partialSyncNotice: inout String?
    ) {
        switch result.status {
        case .completed:
            scanToastMessage = result.stats.lowConfidenceCount > 0
                ? "同步完成，\(result.stats.lowConfidenceCount) 项待确认"
                : ScanProgress(
                    scannedDirectories: 0,
                    discoveredVideos: 0,
                    insertedCount: result.insertedItems.count,
                    updatedCount: result.updatedCount,
                    unchangedCount: result.unchangedCount,
                    prunedCount: result.prunedCount,
                    currentDirectory: "",
                    stats: result.stats
                ).completionSummary
        case .partial:
            partialSyncNotice = "同步部分完成，\(result.issues.count) 个问题"
            if showErrorAlert {
                scanToastMessage = partialSyncNotice
            }
        case .cancelled:
            scanToastMessage = "同步已取消，已保留 \(result.insertedItems.count + result.updatedCount) 项变更"
        case .failed:
            partialSyncNotice = result.issues.last?.message ?? "同步失败"
            if showErrorAlert {
                scanToastMessage = partialSyncNotice
            }
        }
        #if os(iOS)
        if result.status != .failed {
            ScanBackgroundTask.scheduleIfNeeded()
        }
        #endif
    }

    private func userFacingFileBrowserMessage(for error: Error, connection: SavedConnection) -> String {
        if connection.type == .mega {
            return "MEGA 完整接入需要官方 SDK（端到端加密）支持，当前仅保留入口，暂不可浏览。"
        }
        if connection.type.isOfficialCloudDrive {
            return "\(connection.type.displayName) 官方接入仍在合规调研中，当前不会使用非官方接口。可先通过 AList/WebDAV 间接连接。"
        }
        if connection.type.supportsOAuthLogin {
            return "\(connection.type.displayName) 接入尚未就绪：\(error.localizedDescription)"
        }
        if connection.type == .nfs || connection.type == .dlna {
            return "\(connection.type.displayName) 文件浏览暂不可用或该目录为空"
        }
        return error.localizedDescription
    }
}

typealias BrowserViewModel = ConnectionsViewModel
