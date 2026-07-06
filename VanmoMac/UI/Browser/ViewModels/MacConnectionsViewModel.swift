import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacConnectionsViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var loadingMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""

    private var modelContext: ModelContext?
    private var activeLocalServices: [UUID: LocalFolderService] = [:]

    func setModelContext(_ context: ModelContext) {
        modelContext = context
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
        return await connectAndScan(connection)
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
        return await connectAndScan(connection)
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
        return await connectAndScan(connection)
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
    func connectAndScan(_ connection: SavedConnection) async -> Bool {
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
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
            return false
        }
    }
}
