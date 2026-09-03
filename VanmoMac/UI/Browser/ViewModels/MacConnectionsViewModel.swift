import Foundation
import SwiftData
import VanmoCore

enum MacConnectionStatus {
    case idle
    case connecting
    case connected
    case failed
}

struct MacFolderBookmarkNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let connectionId: UUID
    let path: String
}

@MainActor
final class MacConnectionsViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published private(set) var librarySyncMessage: String?
    @Published private(set) var librarySyncCompletionID = 0
    @Published private(set) var connectionErrorMessages: [UUID: String] = [:]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var currentPath = "/"
    @Published private(set) var pathStack: [String] = []
    @Published private(set) var files: [RemoteFile] = []
    @Published private(set) var isBrowsingFiles = false
    @Published private(set) var fileBrowserErrorMessage: String?
    @Published private(set) var failedChannelPaths: Set<String> = []
    @Published private(set) var pendingFolderBookmarkNavigation: MacFolderBookmarkNavigationRequest?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private(set) var scanCoordinator = ScanCoordinator()
    @Published var scanToastMessage: String?
    @Published var pendingMissingCredentialConnection: SavedConnection?

    @Published private(set) var connectionStatuses: [UUID: MacConnectionStatus] = [:]
    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    private var selectedConnectionFallback: SavedConnection?
    private var isActivatingSyncedConnections = false
    private var browserService: RemoteFileService?
    private var browserServiceConnectionID: UUID?
    private var epgLoadID: UUID?
    /// 仅 localFolder 用：保留正在持有 security-scoped access 的 service 实例，
    /// 让 App 生命周期内 file:// URL 始终可读，避免播放时权限失效。
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        modelContext = context
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

    func connectionStatus(for connection: SavedConnection) -> MacConnectionStatus {
        connectionStatuses[connection.id] ?? .idle
    }

    func connectionErrorMessage(for connection: SavedConnection) -> String? {
        connectionErrorMessages[connection.id]
    }

    var selectedConnection: SavedConnection? {
        guard let selectedConnectionID else { return nil }
        return savedConnections.first { $0.id == selectedConnectionID }
            ?? selectedConnectionFallback
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

    // MARK: - Load & Auto-Reconnect

    func loadSavedConnections() async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SavedConnection>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.lastConnectedAt, order: .reverse)]
            )
            let fetched = try context.fetch(descriptor)
            // 内容未变化时跳过赋值，避免无谓的 objectWillChange 引发整树重绘。
            guard !savedConnectionsUnchanged(fetched) else { return }
            savedConnections = fetched
            reconcileSelectedConnection()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 比较 id/name/lastConnectedAt/type，忽略其它瞬时字段；仅凭是否相等决定是否需要发布。
    private func savedConnectionsUnchanged(_ fetched: [SavedConnection]) -> Bool {
        guard fetched.count == savedConnections.count else { return false }
        return zip(fetched, savedConnections).allSatisfy { new, old in
            new.id == old.id
                && new.name == old.name
                && new.type == old.type
                && new.lastConnectedAt == old.lastConnectedAt
        }
    }

    /// 应用启动时尝试自动重连最近一次成功连接过的服务。
    /// 在整个 App 生命周期内只会触发一次。失败时静默处理，不打扰用户。
    func attemptAutoReconnectIfNeeded() async {
        guard !didAttemptAutoReconnect else { return }
        didAttemptAutoReconnect = true

        if savedConnections.isEmpty {
            await loadSavedConnections()
        }

        await restoreLocalFolderAccess()

        guard let target = savedConnections.first(where: { $0.lastConnectedAt != nil }) else {
            VanmoLogger.network.info("[MacConnections] Auto-reconnect skipped: no previous connection")
            return
        }

        guard UserDefaults.standard.object(forKey: "library.autoScan") as? Bool ?? true else {
            VanmoLogger.network.info("[MacConnections] Auto-reconnect skipped: library.autoScan disabled")
            return
        }

        VanmoLogger.network.info("[MacConnections] Auto-reconnect to \(target.name)")
        await connectAndScan(target, showErrorAlert: false)
    }

    /// 仅打开本地文件夹的 bookmark 并保持 access，不触发扫描。
    private func restoreLocalFolderAccess() async {
        for connection in savedConnections where connection.type == .localFolder {
            await ensureLocalFolderAccess(for: connection.id)
        }
    }

    /// 确保指定本地文件夹连接已恢复 security-scoped 访问。
    func ensureLocalFolderAccess(for connectionId: UUID) async {
        guard activeLocalServices[connectionId] == nil else { return }
        guard let connection = savedConnections.first(where: { $0.id == connectionId }) else {
            return
        }
        await ensureLocalFolderAccess(for: connection)
    }

    func ensureLocalFolderAccess(for connection: SavedConnection) async {
        guard activeLocalServices[connection.id] == nil else { return }
        guard connection.type == .localFolder, connection.bookmarkData != nil else { return }

        let service = LocalFolderService()
        let config = ConnectionConfig(from: connection)
        do {
            try await service.connect(config: config)
            activeLocalServices[connection.id] = service
            VanmoLogger.network.info("[MacConnections] Restored local access: \(connection.name)")
        } catch {
            VanmoLogger.network.error(
                "[MacConnections] Restore local access failed for \(connection.name): \(error.localizedDescription)"
            )
        }
    }

    /// 播放前解析/刷新可访问的 stream URL（本地文件夹权限、远程凭据等）。
    func resolvePlaybackURL(for item: MediaItem, modelContext: ModelContext) async throws -> URL {
        guard let connectionId = item.sourceConnectionId,
              let serverPath = item.serverId else {
            let prepared = MacLocalFilePlayback.prepareLocalFileURL(item.fileURL)
            try MacLocalFilePlayback.verifyReadableFile(at: prepared)
            return prepared
        }

        let connection = savedConnections.first(where: { $0.id == connectionId })
            ?? (try? modelContext.fetch(
                FetchDescriptor<SavedConnection>(
                    predicate: #Predicate { $0.id == connectionId }
                )
            ).first)

        guard let connection else {
            let prepared = MacLocalFilePlayback.prepareLocalFileURL(item.fileURL)
            try MacLocalFilePlayback.verifyReadableFile(at: prepared)
            return prepared
        }

        if connection.type.usesEphemeralStreamURLs {
            return connection.type.catalogPlaybackURL(serverPath: serverPath)
        }

        let service = try await playbackFileService(for: connection)
        let playbackFileName = resolvedPlaybackFileName(for: item, connectionType: connection.type)
        let remoteFile = RemoteFile(
            name: playbackFileName,
            path: serverPath,
            size: item.fileSize,
            isDirectory: false,
            modifiedDate: nil,
            type: .video
        )
        let url = try await service.streamURL(for: remoteFile)

        if connection.type == .localFolder {
            let prepared = MacLocalFilePlayback.prepareLocalFileURL(url)
            try MacLocalFilePlayback.verifyReadableFile(at: prepared)
            return prepared
        }

        return url
    }

    private func resolvedPlaybackFileName(for item: MediaItem, connectionType: ConnectionType) -> String {
        let candidate = item.originalFileName ?? item.fileURL.lastPathComponent
        guard (candidate as NSString).pathExtension.isEmpty,
              let resolvedContainer = resolvedPlaybackContainer(for: item, connectionType: connectionType) else {
            return candidate
        }

        return "\(candidate).\(resolvedContainer)"
    }

    private func resolvedPlaybackContainer(for item: MediaItem, connectionType: ConnectionType) -> String? {
        if let container = item.container?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let sanitized = container.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        switch connectionType {
        case .emby, .jellyfin:
            return "mkv"
        default:
            return nil
        }
    }

    private func playbackFileService(for connection: SavedConnection) async throws -> RemoteFileService {
        if connection.type == .localFolder {
            await ensureLocalFolderAccess(for: connection)
            guard let service = activeLocalServices[connection.id] else {
                throw NetworkError.connectionFailed(L10n.tr("本地文件夹访问未恢复，请在连接页重新选择文件夹"))
            }
            return service
        }
        return try await browserFileService(for: connection)
    }

    // MARK: - Delete

    func deleteConnection(_ connection: SavedConnection) {
        let connectionId = connection.id

        try? KeychainManager.shared.delete(for: "conn_\(connection.id)")
        if connection.type.supportsOAuthLogin {
            try? OAuthCredentialStore.delete(connectionId: connection.id)
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
        softDeleteFolderBookmarks(for: connectionId)

        connection.deletedAt = Date()
        CloudSyncCoordinator.shared.markConnectionChanged(connection)
        try? modelContext?.save()
        CloudSyncCoordinator.shared.requestSync(reason: "connection-deleted", context: modelContext)
        CloudSyncedConnectionActivation.removeProcessed(connectionId)

        connectionStatuses.removeValue(forKey: connectionId)
        connectionErrorMessages.removeValue(forKey: connectionId)
        savedConnections.removeAll { $0.id == connectionId }

        let deletedSelectedConnection = selectedConnectionID == connectionId
        if deletedSelectedConnection {
            resetFileBrowser()
        }

        Task {
            await MacHomeCollectionCache.shared.removeConnection(connectionId)
            await loadSavedConnections()
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
            VanmoLogger.library.error("[MacConnections] Delete cached media failed: \(error.localizedDescription)")
        }
    }

    private func softDeleteFolderBookmarks(for connectionId: UUID) {
        guard let context = modelContext else { return }
        let targetConnectionId = connectionId
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId && bookmark.deletedAt == nil
            }
        )
        do {
            let bookmarks = try context.fetch(descriptor)
            for bookmark in bookmarks {
                bookmark.deletedAt = Date()
                CloudSyncCoordinator.shared.markFolderBookmarkChanged(bookmark)
            }
        } catch {
            VanmoLogger.library.error("[MacConnections] Soft-delete folder bookmarks failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Save / Update

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
        guard let saved = savedConnections.first(where: { $0.id == connection.id }) else {
            return false
        }
        CloudSyncedConnectionActivation.markProcessed([saved.id])
        await selectConnection(saved)
        return await connectAndScan(saved)
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

        let didConnect = await connectAndScan(connection)
        if didConnect {
            await loadSavedConnections()
            if selectedConnectionID == connection.id {
                await loadDirectory(path: currentPath)
            }
        }
        return didConnect
    }

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
        CloudSyncedConnectionActivation.markProcessed([saved.id])
        await selectConnection(saved)
        return await connectAndScan(saved)
    }

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
        return await connectAndScan(connection)
    }

    // MARK: - File Browsing

    func enterConnection(_ connection: SavedConnection) async {
        await selectConnection(connection)
    }

    func selectConnection(_ connection: SavedConnection) async {
        await ensureSavedConnectionVisible(connection)
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
        if promptIfMissingLocalCredential(connection) {
            fileBrowserErrorMessage = connectionErrorMessages[connection.id]
            files = []
            return
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
            connectionErrorMessages.removeValue(forKey: connection.id)
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
            VanmoLogger.network.error("[MacConnections] Failed to browse \(connection.name): \(error.localizedDescription)")
            files = []
            fileBrowserErrorMessage = userFacingFileBrowserMessage(for: error, connection: connection)
            if case NetworkError.sharePathRequired = error {
                connectionStatuses[connection.id] = .connected
                connectionErrorMessages.removeValue(forKey: connection.id)
            } else {
                connectionStatuses[connection.id] = .failed
                connectionErrorMessages[connection.id] = error.localizedDescription
            }
            isBrowsingFiles = false
            return false
        }
    }

    func navigateTo(_ file: RemoteFile) async {
        await openDirectory(file)
    }

    func openDirectory(_ file: RemoteFile) async {
        guard file.isDirectory, !isBrowsingFiles else { return }
        let targetPath = normalizedDirectoryPath(file.path)
        guard targetPath != currentPath else { return }
        let previousPath = currentPath
        if await loadDirectory(path: targetPath) {
            pathStack.append(previousPath)
        }
    }

    func navigateUp() async {
        await goBackDirectory()
    }

    func goBackDirectory() async {
        guard let previousPath = pathStack.popLast() else { return }
        if !(await loadDirectory(path: previousPath)) {
            pathStack.append(previousPath)
        }
    }

    func navigateToDirectory(_ targetPath: String) async {
        let normalized = normalizedDirectoryPath(targetPath)
        guard normalized != currentPath else { return }
        if await loadDirectory(path: normalized) {
            pathStack = parentPathsLeading(to: normalized)
        }
    }

    func refreshCurrentDirectory() async {
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

    func previewURL(for file: RemoteFile) async -> URL? {
        guard selectedConnection?.type == .localFolder, file.isVideo else { return nil }
        let url = try? await streamURL(for: file)
        guard let url, url.isFileURL else { return nil }
        return url
    }

    func play(_ file: RemoteFile, via appState: MacAppState) async {
        guard let connection = selectedConnection else { return }

        do {
            let url: URL
            if connection.type.usesEphemeralStreamURLs {
                url = connection.type.catalogPlaybackURL(serverPath: file.path)
            } else {
                url = try await streamURL(for: file)
            }

            let item: MediaItem
            if connection.type == .iptv {
                item = MediaItem(title: file.name, fileURL: url, mediaType: .movie, fileSize: file.size)
                item.isLiveStream = true
            } else if let factoryItem = MediaItemFactory.makeMediaItem(
                from: file,
                streamURL: url,
                connectionId: connection.id,
                directoryPath: currentPath
            ) {
                item = factoryItem
            } else {
                item = MediaItem(title: file.name, fileURL: url, mediaType: .movie, fileSize: file.size)
                item.serverId = file.path
                item.sourceConnectionId = connection.id
                item.originalFileName = file.name
            }
            if item.serverId == nil { item.serverId = file.path }
            if item.sourceConnectionId == nil { item.sourceConnectionId = connection.id }
            if item.originalFileName == nil { item.originalFileName = file.name }
            if item.container == nil {
                let ext = (file.name as NSString).pathExtension
                item.container = ext.isEmpty ? nil : ext.lowercased()
            }
            appState.play(item)
        } catch {
            if connection.type == .iptv {
                markChannelPlaybackFailed(file)
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func markChannelPlaybackFailed(_ file: RemoteFile) {
        failedChannelPaths.insert(file.path)
    }

    func isChannelPlaybackFailed(_ file: RemoteFile) -> Bool {
        failedChannelPaths.contains(file.path)
    }

    // MARK: - Folder Bookmarks

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
            VanmoLogger.library.error("[MacConnections] Folder bookmark save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Connect & Scan

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
        loadingMessage = forceFullScan
            ? "全量重扫 \(connection.name)..."
            : "连接到 \(connection.name)..."

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
                loadingMessage = forceFullScan
                    ? "全量重扫 \(connection.name)..."
                    : L10n.tr("扫描媒体文件...")
                librarySyncMessage = L10n.tr("正在同步数据...")
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
                for try await page in mediaServer.streamMediaItems(since: since, pageSize: 500) {
                    _ = try await scanner.importServerMediaItems(
                        page,
                        connectionId: connection.id,
                        in: context
                    )
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

            if !isLocal {
                await service.disconnect()
            }

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

    func requestOpenFolderBookmark(_ bookmark: FolderBookmark) {
        pendingFolderBookmarkNavigation = MacFolderBookmarkNavigationRequest(
            connectionId: bookmark.connectionId,
            path: bookmark.path
        )
    }

    func openFolderBookmarkRequest(_ request: MacFolderBookmarkNavigationRequest) async -> Bool {
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

    // MARK: - Private Helpers

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

    private func reconcileSelectedConnection() {
        if savedConnections.isEmpty {
            if selectedConnectionFallback == nil {
                resetFileBrowser()
            }
            return
        }

        if let selectedConnectionID,
           savedConnections.contains(where: { $0.id == selectedConnectionID }) {
            selectedConnectionFallback = nil
            return
        }

        if let selectedConnectionID,
           selectedConnectionFallback?.id == selectedConnectionID {
            return
        }

        selectedConnectionID = savedConnections.first?.id
        currentPath = savedConnections.first?.browserRootPath ?? "/"
        pathStack = []
        files = []
        fileBrowserErrorMessage = nil
    }

    private func ensureSavedConnectionVisible(_ connection: SavedConnection) async {
        if savedConnections.contains(where: { $0.id == connection.id }) {
            selectedConnectionFallback = nil
            return
        }
        await loadSavedConnections()
        if savedConnections.contains(where: { $0.id == connection.id }) {
            selectedConnectionFallback = nil
            return
        }
        selectedConnectionFallback = connection
    }

    @discardableResult
    func promptIfMissingLocalCredential(_ connection: SavedConnection) -> Bool {
        guard CloudSyncedConnectionActivation.needsLocalCredential(connection) else {
            return false
        }
        let message = L10n.tr("此设备还没有密码，iCloud 不同步凭据。")
        connectionStatuses[connection.id] = .failed
        connectionErrorMessages[connection.id] = message
        if pendingMissingCredentialConnection == nil {
            pendingMissingCredentialConnection = connection
        }
        #if DEBUG
        print("[Debug][CloudKit] missingCredential type=\(connection.type.rawValue)")
        #endif
        return true
    }

    /// Connects CloudKit-imported connections that this device has not handled yet.
    /// Returns true when a media server connected so the home live refresh can run.
    @discardableResult
    func activateNewlySyncedConnections() async -> Bool {
        guard !isActivatingSyncedConnections else { return false }
        isActivatingSyncedConnections = true
        defer { isActivatingSyncedConnections = false }

        let newcomers = CloudSyncedConnectionActivation.unprocessedConnections(from: savedConnections)
        guard !newcomers.isEmpty else { return false }

        var didConnectMediaServer = false
        for connection in newcomers {
            CloudSyncedConnectionActivation.markProcessed([connection.id])
            #if DEBUG
            print("[Debug][CloudKit] activate type=\(connection.type.rawValue) missingCredential=\(CloudSyncedConnectionActivation.needsLocalCredential(connection))")
            #endif

            if connection.type == .localFolder {
                await ensureLocalFolderAccess(for: connection.id)
                continue
            }

            if promptIfMissingLocalCredential(connection) {
                continue
            }

            let connected = await connectAndScan(connection, showErrorAlert: false)
            if connected, connection.type.requiresManualDirectorySync {
                _ = await syncAllBookmarks(for: connection)
            }
            if connected, connection.type.isMediaServer {
                didConnectMediaServer = true
            }
        }
        return didConnectMediaServer
    }

    private func loadEPGGuide(from service: RemoteFileService, connectionID: UUID) async {
        guard let iptvService = service as? IPTVService else {
            resetIPTVState()
            return
        }

        let loadID = UUID()
        epgLoadID = loadID
        _ = await iptvService.fetchEPGGuide()
        guard epgLoadID == loadID,
              selectedConnectionID == connectionID,
              selectedConnection?.type == .iptv else {
            return
        }
        epgLoadID = nil
    }

    private func resetIPTVState() {
        epgLoadID = nil
        failedChannelPaths = []
    }

    private func resetFileBrowser() {
        selectedConnectionID = nil
        selectedConnectionFallback = nil
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

    private func parentPathsLeading(to path: String) -> [String] {
        let normalized = normalizedDirectoryPath(path)
        guard normalized != "/" else { return [] }

        var segments = normalized.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return [] }
        segments.removeLast()

        guard !segments.isEmpty else { return ["/"] }

        var stack: [String] = ["/"]
        var current = ""
        for segment in segments {
            current = current.isEmpty ? "/\(segment)" : (current as NSString).appendingPathComponent(segment)
            stack.append(current)
        }
        return stack
    }

    private func folderBookmark(connectionId: UUID, path: String) -> FolderBookmark? {
        guard let context = modelContext else { return nil }
        let targetConnectionId = connectionId
        let targetPath = path
        let descriptor = FetchDescriptor<FolderBookmark>(
            predicate: #Predicate<FolderBookmark> { bookmark in
                bookmark.connectionId == targetConnectionId
                    && bookmark.path == targetPath
                    && bookmark.deletedAt == nil
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

    private func fileSortPredicate(_ lhs: RemoteFile, _ rhs: RemoteFile) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
            if showErrorAlert { scanToastMessage = partialSyncNotice }
        case .cancelled:
            scanToastMessage = "同步已取消，已保留 \(result.insertedItems.count + result.updatedCount) 项变更"
        case .failed:
            partialSyncNotice = result.issues.last?.message ?? L10n.tr("同步失败")
            if showErrorAlert { scanToastMessage = partialSyncNotice }
        }
    }
}

@MainActor
enum MacConnectionDeletion {
    static func delete(
        _ connection: SavedConnection,
        appState: MacAppState,
        libraryViewModel: MacLibraryViewModel,
        connectionsViewModel: MacConnectionsViewModel,
        searchViewModel: MacSearchViewModel
    ) {
        let connectionId = connection.id
        // 先清 UI 引用，再删库，避免 SwiftData detach 后读 mediaType 崩溃。
        appState.purgeMediaState(for: connectionId)
        libraryViewModel.removeItems(forConnectionId: connectionId)
        searchViewModel.removeResults(forConnectionId: connectionId)

        Task { @MainActor in
            // 让 SwiftUI 先卸掉仍持有 MediaItem 的子路由/详情/播放器视图，再 hard-delete。
            await Task.yield()
            connectionsViewModel.deleteConnection(connection)
            let remainingConnections = connectionsViewModel.savedConnections.filter {
                $0.id != connectionId && $0.deletedAt == nil
            }
            await libraryViewModel.refreshAfterLibrarySync(
                connections: remainingConnections,
                refreshEmbyLive: false
            )
            libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
            // 库已物理删除：广播历史变更，让 History 页从 offset 0 整体重载，避免分页空洞。
            appState.notifyWatchHistoryDidChange()
        }
    }
}
