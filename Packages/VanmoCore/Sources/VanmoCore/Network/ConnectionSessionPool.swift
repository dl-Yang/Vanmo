import Foundation

public actor ConnectionSessionPool {
    public static let shared = ConnectionSessionPool()

    private struct Entry {
        let service: RemoteFileService
        var leaseCount: Int
    }

    private var entries: [UUID: Entry] = [:]

    public func service(
        for connection: SavedConnection,
        password: String? = nil,
        localService: LocalFolderService? = nil
    ) async throws -> RemoteFileService {
        if connection.type == .localFolder, let localService {
            return localService
        }

        if let existing = entries[connection.id]?.service, existing.isConnected {
            entries[connection.id]?.leaseCount += 1
            return existing
        }

        let service: RemoteFileService
        if connection.type == .localFolder {
            let local = localService ?? LocalFolderService()
            let config = ConnectionConfig(from: connection)
            try await local.connect(config: config)
            service = local
        } else {
            let remote = RemoteServiceFactory.create(for: connection.type)
            let config = ConnectionConfig(from: connection, password: password)
            try await remote.connect(config: config)
            service = remote
        }

        entries[connection.id] = Entry(service: service, leaseCount: 1)
        return service
    }

    public func release(connectionId: UUID, disconnect: Bool = false) async {
        guard var entry = entries[connectionId] else { return }
        entry.leaseCount = max(0, entry.leaseCount - 1)
        if entry.leaseCount == 0 || disconnect {
            await entry.service.disconnect()
            entries.removeValue(forKey: connectionId)
        } else {
            entries[connectionId] = entry
        }
    }

    public func disconnectAll() async {
        for entry in entries.values {
            await entry.service.disconnect()
        }
        entries.removeAll()
    }
}
