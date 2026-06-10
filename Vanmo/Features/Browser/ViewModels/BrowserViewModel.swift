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
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var currentPath = "/"
    @Published private(set) var pathStack: [String] = []
    @Published private(set) var files: [RemoteFile] = []
    @Published private(set) var isBrowsingFiles = false
    @Published private(set) var fileBrowserErrorMessage: String?
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""

    private var connectionStatuses: [UUID: ConnectionStatus] = [:]
    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    private var browserService: RemoteFileService?
    private var browserServiceConnectionID: UUID?
    /// 仅 localFolder 用：保留正在持有 security-scoped access 的 service 实例，
    /// 让 App 生命周期内 file:// URL 始终可读，避免播放时权限失效。
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func connectionStatus(for connection: SavedConnection) -> ConnectionStatus {
        connectionStatuses[connection.id] ?? .idle
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

        // savedConnections 已按 lastConnectedAt 倒序排列。
        guard let last = savedConnections.first(where: { $0.lastConnectedAt != nil }) else {
            VanmoLogger.network.info("[Connections] Auto-reconnect skipped: no previous connection")
            return
        }

        VanmoLogger.network.info("[Connections] Auto-reconnect to \(last.name)")
        await connectAndScan(last, showErrorAlert: false)
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
            connection.lastConnectedAt = Date()
            try? modelContext?.save()

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
            if showErrorAlert {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            librarySyncMessage = nil
            return false
        }
    }

    func saveConnection(
        name: String,
        type: ConnectionType,
        host: String,
        port: Int,
        username: String?,
        password: String?,
        path: String?,
        bookmarkData: Data? = nil
    ) async {
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
        }
    }

    func deleteConnection(_ connection: SavedConnection) {
        try? KeychainManager.shared.delete(for: "conn_\(connection.id)")

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

        modelContext?.delete(connection)
        try? modelContext?.save()
        connectionStatuses.removeValue(forKey: connection.id)
        let deletedSelectedConnection = selectedConnectionID == connection.id
        if deletedSelectedConnection {
            resetFileBrowser()
        }
        Task {
            await loadSavedConnections()
            if deletedSelectedConnection {
                await loadSelectedConnectionRootIfNeeded()
            }
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

    private func resetFileBrowser() {
        selectedConnectionID = nil
        currentPath = "/"
        pathStack = []
        files = []
        isBrowsingFiles = false
        fileBrowserErrorMessage = nil
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
