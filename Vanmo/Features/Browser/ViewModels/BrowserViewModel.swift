import SwiftUI
import SwiftData
import Combine

enum ConnectionStatus {
    case idle
    case connecting
    case connected
    case failed
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
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""

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

    func loadSavedConnections() async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SavedConnection>(
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
        scanPath: String? = nil
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

            loadingMessage = "扫描媒体文件..."
            librarySyncMessage = "正在同步数据..."
            guard let context = modelContext else {
                isLoading = false
                librarySyncMessage = nil
                librarySyncCompletionID += 1
                return true
            }

            let scanner = MediaScanner(modelContainer: context.container)

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
            } else if connection.type != .emby && connection.type != .jellyfin {
                let scanPath = scanPath ?? connection.path ?? "/"
                _ = try await scanner.scanRemoteDirectory(
                    service: service,
                    path: scanPath,
                    connectionId: connection.id,
                    in: context
                )
            }

            // 本地文件夹保持 access，让媒体库里的视频后续可直接播放；
            // 远端协议照常释放连接。
            if !isLocal {
                await service.disconnect()
            }

            VanmoLogger.network.info("[Connections] Scan complete for \(connection.name)")
            isLoading = false
            librarySyncMessage = nil
            librarySyncCompletionID += 1
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
        await loadSavedConnections()
        if let saved = savedConnections.first(where: { $0.id == connection.id }) {
            await selectConnection(saved)
            // 添加连接后立即连接并扫描，触发 librarySyncCompletionID 递增，使首页主动刷新
            // 显示该服务内容（修复首次添加后首页不刷新的问题）。
            return await connectAndScan(saved, showErrorAlert: true)
        }
        return false
    }

    func deleteConnection(_ connection: SavedConnection) {
        let connectionId = connection.id
        let isMediaServerConnection = connection.type.isMediaServer

        try? KeychainManager.shared.delete(for: "conn_\(connection.id)")

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
        modelContext?.delete(connection)
        try? modelContext?.save()
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
            connectionStatuses[connection.id] = .failed
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
        currentPath = "/"
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

    private func fileSortPredicate(_ lhs: RemoteFile, _ rhs: RemoteFile) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func userFacingFileBrowserMessage(for error: Error, connection: SavedConnection) -> String {
        if connection.type == .ftp || connection.type == .sftp || connection.type == .nfs || connection.type == .dlna {
            return "\(connection.type.displayName) 文件浏览暂不可用或该目录为空"
        }
        return error.localizedDescription
    }
}

typealias BrowserViewModel = ConnectionsViewModel
