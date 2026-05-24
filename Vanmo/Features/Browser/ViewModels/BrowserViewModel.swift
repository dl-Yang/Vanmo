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
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""

    private var connectionStatuses: [UUID: ConnectionStatus] = [:]
    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    /// 仅 localFolder 用：保留正在持有 security-scoped access 的 service 实例，
    /// 让 App 生命周期内 file:// URL 始终可读，避免播放时权限失效。
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func connectionStatus(for connection: SavedConnection) -> ConnectionStatus {
        connectionStatuses[connection.id] ?? .idle
    }

    func loadSavedConnections() async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SavedConnection>(
                sortBy: [SortDescriptor(\.lastConnectedAt, order: .reverse)]
            )
            savedConnections = try context.fetch(descriptor)
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
        forceFullScan: Bool = false
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
                    let inserted = try await scanner.importServerMediaItems(page, in: context)
                    totalImported += inserted.count
                    let message = "已同步 \(totalImported) 项..."
                    loadingMessage = message
                    librarySyncMessage = message
                }
                connection.lastSyncedAt = syncStart
                try? modelContext?.save()
            } else if connection.type != .emby && connection.type != .jellyfin {
                let scanPath = connection.path ?? "/"
                _ = try await scanner.scanRemoteDirectory(
                    service: service,
                    path: scanPath,
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
    }

    func deleteConnection(_ connection: SavedConnection) {
        try? KeychainManager.shared.delete(for: "conn_\(connection.id)")

        if let active = activeLocalServices.removeValue(forKey: connection.id) {
            Task { await active.disconnect() }
        }

        modelContext?.delete(connection)
        try? modelContext?.save()
        connectionStatuses.removeValue(forKey: connection.id)
        Task { await loadSavedConnections() }
    }
}

typealias BrowserViewModel = ConnectionsViewModel
