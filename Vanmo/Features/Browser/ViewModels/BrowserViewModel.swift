import SwiftUI
import SwiftData
import Combine
import os.log

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection] = []
    @Published private(set) var currentFiles: [RemoteFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isConnected = false
    @Published private(set) var currentPath: String = "/"
    @Published var pathHistory: [String] = ["/"]
    @Published var showAddConnection = false
    @Published var showError = false
    @Published var errorMessage = ""

    private var service: RemoteFileService?
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
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

    func connect(to connection: SavedConnection) async {
        isLoading = true
        defer { isLoading = false }

        VanmoLogger.network.info("[Browser] Connecting to \(connection.name) (\(connection.type.rawValue)://\(connection.host):\(connection.port))")

        do {
            let password = try KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            VanmoLogger.network.debug("[Browser] Password loaded: \(password != nil ? "yes" : "no")")

            let config = ConnectionConfig(from: connection, password: password)
            let newService = RemoteServiceFactory.create(for: connection.type)
            VanmoLogger.network.debug("[Browser] Service created, starting connect...")

            try await newService.connect(config: config)

            service = newService
            isConnected = true
            currentPath = connection.path ?? "/"
            pathHistory = [currentPath]

            connection.lastConnectedAt = Date()
            try? modelContext?.save()

            VanmoLogger.network.info("[Browser] Connected successfully, loading directory: \(self.currentPath)")
            await loadDirectory(currentPath)
        } catch {
            VanmoLogger.network.error("[Browser] Connection failed: \(error.localizedDescription)")
            VanmoLogger.network.error("[Browser] Error type: \(String(describing: error))")
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func disconnect() async {
        await service?.disconnect()
        service = nil
        isConnected = false
        currentFiles = []
        currentPath = "/"
        pathHistory = ["/"]
    }

    func loadDirectory(_ path: String) async {
        guard let service else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            currentFiles = try await service.listDirectory(path: path)
            currentPath = path
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func navigateTo(_ file: RemoteFile) async {
        guard file.isDirectory else { return }
        let newPath = currentPath == "/" ? "/\(file.name)" : "\(currentPath)/\(file.name)"
        pathHistory.append(newPath)
        await loadDirectory(newPath)
    }

    func navigateBack() async {
        guard pathHistory.count > 1 else {
            await disconnect()
            return
        }
        pathHistory.removeLast()
        if let previousPath = pathHistory.last {
            await loadDirectory(previousPath)
        }
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard let service else { throw NetworkError.notConnected }
        return try await service.streamURL(for: file)
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
        Task { await loadSavedConnections() }
    }
}
