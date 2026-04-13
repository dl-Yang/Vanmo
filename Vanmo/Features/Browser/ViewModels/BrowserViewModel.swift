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
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""

    private var connectionStatuses: [UUID: ConnectionStatus] = [:]
    private var modelContext: ModelContext?

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

    @discardableResult
    func connectAndScan(_ connection: SavedConnection) async -> Bool {
        connectionStatuses[connection.id] = .connecting
        isLoading = true
        loadingMessage = "连接到 \(connection.name)..."

        VanmoLogger.network.info("[Connections] Connecting to \(connection.name) (\(connection.type.rawValue)://\(connection.host):\(connection.port))")

        do {
            let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            let config = ConnectionConfig(from: connection, password: password)
            let service = RemoteServiceFactory.create(for: connection.type)

            try await service.connect(config: config)
            connectionStatuses[connection.id] = .connected

            connection.lastConnectedAt = Date()
            try? modelContext?.save()

            loadingMessage = "扫描媒体文件..."
            guard let context = modelContext else {
                isLoading = false
                return true
            }

            let scanner = MediaScanner(modelContainer: context.container)

            if let mediaServer = service as? MediaServerService {
                let serverItems = try await mediaServer.fetchAllMediaItems()
                _ = try await scanner.importServerMediaItems(serverItems, in: context)
            } else {
                let scanPath = connection.path ?? "/"
                _ = try await scanner.scanRemoteDirectory(
                    service: service,
                    path: scanPath,
                    in: context
                )
            }

            await service.disconnect()

            VanmoLogger.network.info("[Connections] Scan complete for \(connection.name)")
            isLoading = false
            return true
        } catch {
            VanmoLogger.network.error("[Connections] Connection failed: \(error.localizedDescription)")
            connectionStatuses[connection.id] = .failed
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
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
        path: String?
    ) async {
        let connection = SavedConnection(
            name: name,
            type: type,
            host: host,
            port: port,
            username: username,
            path: path
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
        modelContext?.delete(connection)
        try? modelContext?.save()
        connectionStatuses.removeValue(forKey: connection.id)
        Task { await loadSavedConnections() }
    }
}

typealias BrowserViewModel = ConnectionsViewModel
