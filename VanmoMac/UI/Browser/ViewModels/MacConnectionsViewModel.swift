import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacConnectionsViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""

    private var modelContext: ModelContext?
    private var didAttemptAutoReconnect = false
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        modelContext = context
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

        deleteMediaItems(for: connectionId)
        softDeleteFolderBookmarks(for: connectionId)

        connection.deletedAt = Date()
        CloudSyncCoordinator.shared.markConnectionChanged(connection)
        try? modelContext?.save()
        CloudSyncCoordinator.shared.requestSync(reason: "connection-deleted", context: modelContext)

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
        let didConnect = await connectAndScan(connection)
        if didConnect {
            await loadSavedConnections()
        }
        return didConnect
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

        activeLocalServices.removeValue(forKey: connection.id)
        let didConnect = await connectAndScan(connection)
        if didConnect {
            await loadSavedConnections()
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
        let didConnect = await connectAndScan(connection)
        if didConnect {
            await loadSavedConnections()
        }
        return didConnect
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

        return await connectAndScan(connection)
    }

    // MARK: - Connect & Scan

    @discardableResult
    func connectAndScan(
        _ connection: SavedConnection,
        showErrorAlert: Bool = true
    ) async -> Bool {
        isLoading = true
        loadingMessage = "连接到 \(connection.name)..."

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
                let since = connection.lastSyncedAt
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
                    let scanPath = connection.path ?? "/"
                    _ = try await scanner.scanRemoteDirectory(
                        service: service,
                        path: scanPath,
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
            if showErrorAlert {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            return false
        }
    }
}
