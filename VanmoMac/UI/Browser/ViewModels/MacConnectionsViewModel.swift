import Foundation
import SwiftData
import VanmoCore

enum MacConnectionStatus {
    case idle
    case connecting
    case connected
    case failed
}

@MainActor
final class MacConnectionsViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published private(set) var connectionErrorMessages: [UUID: String] = [:]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var currentPath = "/"
    @Published private(set) var pathStack: [String] = []
    @Published private(set) var files: [RemoteFile] = []
    @Published private(set) var isBrowsingFiles = false
    @Published private(set) var fileBrowserErrorMessage: String?
    @Published private(set) var failedChannelPaths: Set<String> = []
    @Published var showError = false
    @Published var errorMessage = ""

    private var connectionStatuses: [UUID: MacConnectionStatus] = [:]
    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    private var browserService: RemoteFileService?
    private var browserServiceConnectionID: UUID?
    private var epgLoadID: UUID?
    /// 仅 localFolder 用：保留正在持有 security-scoped access 的 service 实例，
    /// 让 App 生命周期内 file:// URL 始终可读，避免播放时权限失效。
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        modelContext = context
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
            savedConnections = try context.fetch(descriptor)
            reconcileSelectedConnection()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
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
            guard activeLocalServices[connection.id] == nil else { continue }
            guard connection.bookmarkData != nil else { continue }

            let service = LocalFolderService()
            let config = ConnectionConfig(from: connection)
            do {
                try await service.connect(config: config)
                activeLocalServices[connection.id] = service
                VanmoLogger.network.info("[MacConnections] Restored local access: \(connection.name)")
            } catch {
                VanmoLogger.network.error("[MacConnections] Restore local access failed for \(connection.name): \(error.localizedDescription)")
            }
        }
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

        connectionStatuses.removeValue(forKey: connectionId)
        connectionErrorMessages.removeValue(forKey: connectionId)

        let deletedSelectedConnection = selectedConnectionID == connectionId
        if deletedSelectedConnection {
            resetFileBrowser()
        }

        Task {
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
        let isSameConnection = selectedConnectionID == connection.id
        if !isSameConnection {
            selectedConnectionID = connection.id
            currentPath = "/"
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
            let normalizedPath = normalizedDirectoryPath(path)
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
            connectionStatuses[connection.id] = .failed
            connectionErrorMessages[connection.id] = error.localizedDescription
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
        return await connectAndScan(selectedConnection, forceFullScan: forceFullScan)
    }

    func scanCurrentDirectory(forceFullScan: Bool = false) async -> Bool {
        guard let selectedConnection else { return false }
        return await connectAndScan(
            selectedConnection,
            forceFullScan: forceFullScan,
            scanPath: currentPath
        )
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let connection = selectedConnection else {
            throw NetworkError.notConnected
        }
        let service = try await browserFileService(for: connection)
        return try await service.streamURL(for: file)
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
            } else {
                let parsed = FileNameParser.parse(file.name)
                item = MediaItem(
                    title: parsed.title,
                    fileURL: url,
                    mediaType: parsed.isTV ? .tvEpisode : .movie,
                    fileSize: file.size
                )
                item.year = parsed.year
                item.seasonNumber = parsed.season
                item.episodeNumber = parsed.episode
                item.showTitle = parsed.isTV ? parsed.title : nil
            }
            item.serverId = file.path
            item.sourceConnectionId = connection.id
            item.originalFileName = file.name
            let ext = (file.name as NSString).pathExtension
            item.container = ext.isEmpty ? nil : ext.lowercased()
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
        scanPath: String? = nil
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

            loadingMessage = "扫描媒体文件..."
            guard let context = modelContext else {
                isLoading = false
                return true
            }

            let scanner = MediaScanner(modelContainer: context.container)

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
            } else if connection.type != .emby && connection.type != .jellyfin {
                if connection.type != .baiduNetdisk {
                    let resolvedScanPath = scanPath ?? connection.path ?? "/"
                    _ = try await scanner.scanRemoteDirectory(
                        service: service,
                        path: resolvedScanPath,
                        connectionId: connection.id,
                        in: context
                    )
                }
            }

            if !isLocal {
                await service.disconnect()
            }

            isLoading = false
            return true
        } catch {
            connectionStatuses[connection.id] = .failed
            connectionErrorMessages[connection.id] = error.localizedDescription
            if showErrorAlert {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            return false
        }
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
        currentPath = "/"
        pathStack = []
        files = []
        isBrowsingFiles = false
        fileBrowserErrorMessage = nil
        resetIPTVState()
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
        currentPath = "/"
        pathStack = []
        files = []
        fileBrowserErrorMessage = nil
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
        if connection.type == .ftp || connection.type == .sftp || connection.type == .nfs || connection.type == .dlna {
            return "\(connection.type.displayName) 文件浏览暂不可用或该目录为空"
        }
        return error.localizedDescription
    }
}
