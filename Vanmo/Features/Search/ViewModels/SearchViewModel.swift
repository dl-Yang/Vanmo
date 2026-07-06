import SwiftUI
import SwiftData
import Combine
import VanmoCore

struct SearchResultSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let items: [SearchResultItem]
}

struct SearchResultItem: Identifiable {
    let id: String
    let item: MediaItem
    let isRemoteResult: Bool
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var sections: [SearchResultSection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchedSourceCount = 0

    private var modelContext: ModelContext?
    private var connectionSnapshots: [SearchConnectionSnapshot] = []
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private let maxConcurrentRemoteSearches = 4

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setConnections(_ connections: [SavedConnection]) {
        connectionSnapshots = connections.map { connection in
            let password = connection.type == .localFolder ? nil : try? KeychainManager.shared.loadString(for: "conn_\(connection.id)")
            return SearchConnectionSnapshot(connection: connection, password: password)
        }
    }

    func search() {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            sections = []
            searchedSourceCount = 0
            isSearching = false
            return
        }

        searchTask = Task {
            isSearching = true
            defer {
                if isCurrentSearch(generation) {
                    isSearching = false
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, isCurrentSearch(generation) else { return }
            await searchAll(query, generation: generation)
        }
    }

    private func searchAll(_ query: String, generation: UUID) async {
        let localSections = searchLibrary(query)
        let remotePayloads = await searchRemoteConnections(query)
        let remoteSections = remotePayloads.compactMap { makeRemoteSection(from: $0) }
        let nextSections = mergedSections(localSections + remoteSections)
            .filter { !$0.items.isEmpty }

        guard !Task.isCancelled, isCurrentSearch(generation) else { return }
        sections = nextSections
        results = nextSections.flatMap { section in section.items.map(\.item) }
        searchedSourceCount = nextSections.count
    }

    private func isCurrentSearch(_ generation: UUID) -> Bool {
        searchGeneration == generation
    }

    private func searchLibrary(_ query: String) -> [SearchResultSection] {
        guard let context = modelContext else { return [] }
        do {
            let descriptor = FetchDescriptor<MediaItem>()
            let allItems = try context.fetch(descriptor)
            let lowered = query.lowercased()
            let matchedItems = allItems.filter { item in
                item.title.lowercased().contains(lowered) ||
                (item.originalTitle?.lowercased().contains(lowered) ?? false) ||
                (item.director?.lowercased().contains(lowered) ?? false) ||
                item.cast.contains { $0.lowercased().contains(lowered) } ||
                item.genres.contains { $0.lowercased().contains(lowered) }
            }

            let grouped: [UUID?: [MediaItem]] = Dictionary(grouping: matchedItems) { item in
                item.sourceConnectionId
            }
            let snapshotsById = Dictionary(uniqueKeysWithValues: connectionSnapshots.map { ($0.id, $0) })

            let sortedSourceIds: [UUID?] = grouped.keys.sorted { lhs, rhs in
                localSourceSort(lhs, rhs)
            }
            let sections: [SearchResultSection] = sortedSourceIds.compactMap { sourceId -> SearchResultSection? in
                guard let groupItems = grouped[sourceId] else { return nil }
                let items = deduplicated(groupItems).map { item in
                    SearchResultItem(
                        id: "local-\(item.id.uuidString)",
                        item: item,
                        isRemoteResult: false
                    )
                }
                guard !items.isEmpty else { return nil }

                let snapshot = sourceId.flatMap { snapshotsById[$0] }
                return SearchResultSection(
                    id: sourceSectionId(sourceId),
                    title: snapshot?.name ?? localSourceTitle(for: sourceId),
                    subtitle: snapshot.map { "已同步媒体 · \($0.type.displayName)" } ?? "已同步媒体",
                    items: items
                )
            }
            return sections
        } catch {
            return []
        }
    }

    private func localSourceSort(_ lhs: UUID?, _ rhs: UUID?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (lhs?, rhs?):
            return sourceName(for: lhs).localizedStandardCompare(sourceName(for: rhs)) == .orderedAscending
        }
    }

    private func sourceName(for id: UUID) -> String {
        connectionSnapshots.first { $0.id == id }?.name ?? id.uuidString
    }

    private func localSourceTitle(for sourceId: UUID?) -> String {
        sourceId == nil ? "本地媒体库" : "已同步来源"
    }

    private func sourceSectionId(_ sourceId: UUID?) -> String {
        if let sourceId {
            return "source-\(sourceId.uuidString)"
        }
        return "source-local-library"
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seenKeys: Set<String> = []
        return items.filter { item in
            let key = [
                item.displayTitle.lowercased(),
                item.year.map(String.init) ?? "",
                item.duration > 0 ? String(Int(item.duration)) : ""
            ].joined(separator: "|")
            return seenKeys.insert(key).inserted
        }
    }

    private func searchRemoteConnections(_ query: String) async -> [RemoteSearchPayload] {
        let snapshots = connectionSnapshots.filter(\.isSearchEligible)
        guard !snapshots.isEmpty else { return [] }

        return await withTaskGroup(of: RemoteSearchPayload?.self) { group in
            var iterator = snapshots.makeIterator()
            for _ in 0..<maxConcurrentRemoteSearches {
                guard let snapshot = iterator.next() else { break }
                group.addTask {
                    await Self.remoteSearchPayload(query: query, snapshot: snapshot)
                }
            }

            var payloads: [RemoteSearchPayload] = []
            while let payload = await group.next() {
                if let payload, !Task.isCancelled {
                    payloads.append(payload)
                }
                if let snapshot = iterator.next() {
                    group.addTask {
                        await Self.remoteSearchPayload(query: query, snapshot: snapshot)
                    }
                }
            }
            return payloads.sorted { $0.sourceName.localizedStandardCompare($1.sourceName) == .orderedAscending }
        }
    }

    private nonisolated static func remoteSearchPayload(
        query: String,
        snapshot: SearchConnectionSnapshot
    ) async -> RemoteSearchPayload? {
        let service = RemoteServiceFactory.create(for: snapshot.type)

        do {
            try Task.checkCancellation()
            try await service.connect(config: snapshot.config)

            if let provider = service as? MediaSearchProviding {
                let items = try await provider.searchMedia(query: query, limit: 30)
                await service.disconnect()
                return RemoteSearchPayload(
                    connectionId: snapshot.id,
                    sourceName: snapshot.name,
                    sourceSubtitle: snapshot.type.displayName,
                    serverItems: items,
                    files: []
                )
            }

            guard snapshot.isFileSearchable else {
                await service.disconnect()
                return nil
            }

            let rootPath = (snapshot.path?.isEmpty == false ? snapshot.path : nil) ?? "/"
            let matches = try await service.search(query: query, path: rootPath, maxDepth: 2, limit: 40)
            let fileHits = await fileHits(from: matches.filter(\.isVideo), service: service)

            await service.disconnect()
            return RemoteSearchPayload(
                connectionId: snapshot.id,
                sourceName: snapshot.name,
                sourceSubtitle: snapshot.type.displayName,
                serverItems: [],
                files: fileHits
            )
        } catch {
            await service.disconnect()
            return nil
        }
    }

    private nonisolated static func fileHits(
        from files: [RemoteFile],
        service: RemoteFileService
    ) async -> [RemoteFileHit] {
        var hits: [RemoteFileHit] = []
        for file in files {
            do {
                try Task.checkCancellation()
                let streamURL = try await service.streamURL(for: file)
                hits.append(
                    RemoteFileHit(
                        name: file.name,
                        path: file.path,
                        size: file.size,
                        streamURL: streamURL
                    )
                )
            } catch is CancellationError {
                break
            } catch {
                continue
            }
        }
        return hits.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func makeRemoteSection(from payload: RemoteSearchPayload) -> SearchResultSection? {
        let serverItems = payload.serverItems.map { serverItem -> SearchResultItem in
            let item = ServerMediaItemMapper.makeMediaItem(from: serverItem)
            item.sourceConnectionId = payload.connectionId
            return SearchResultItem(
                id: "server-\(payload.connectionId.uuidString)-\(serverItem.serverId)",
                item: item,
                isRemoteResult: true
            )
        }

        let fileItems = payload.files.map { hit -> SearchResultItem in
            let item = makeMediaItem(from: hit, connectionId: payload.connectionId)
            return SearchResultItem(
                id: "file-\(payload.connectionId.uuidString)-\(hit.path)",
                item: item,
                isRemoteResult: true
            )
        }

        let items = deduplicatedResultItems(serverItems + fileItems)
        guard !items.isEmpty else { return nil }

        return SearchResultSection(
            id: sourceSectionId(payload.connectionId),
            title: payload.sourceName,
            subtitle: payload.sourceSubtitle,
            items: items
        )
    }

    private func mergedSections(_ sections: [SearchResultSection]) -> [SearchResultSection] {
        var order: [String] = []
        var byId: [String: SearchResultSection] = [:]

        for section in sections {
            if let existing = byId[section.id] {
                let mergedItems = deduplicatedResultItems(existing.items + section.items)
                byId[section.id] = SearchResultSection(
                    id: existing.id,
                    title: existing.title,
                    subtitle: mergedSubtitle(existing.subtitle, section.subtitle),
                    items: mergedItems
                )
            } else {
                order.append(section.id)
                byId[section.id] = section
            }
        }

        return order.compactMap { byId[$0] }
    }

    private func mergedSubtitle(_ lhs: String?, _ rhs: String?) -> String? {
        let parts = [lhs, rhs]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: " · ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        let uniqueParts = parts.filter { seen.insert($0).inserted }
        guard !uniqueParts.isEmpty else {
            return nil
        }
        return uniqueParts.joined(separator: " · ")
    }

    private func makeMediaItem(from hit: RemoteFileHit, connectionId: UUID) -> MediaItem {
        let parsed = FileNameParser.parse(hit.name)
        let item = MediaItem(
            title: parsed.title,
            fileURL: hit.streamURL,
            mediaType: parsed.isTV ? .tvEpisode : .movie,
            fileSize: hit.size
        )
        item.year = parsed.year
        item.seasonNumber = parsed.season
        item.episodeNumber = parsed.episode
        item.showTitle = parsed.isTV ? parsed.title : nil
        item.serverId = hit.path
        item.sourceConnectionId = connectionId
        item.originalFileName = hit.name
        let ext = (hit.name as NSString).pathExtension
        item.container = ext.isEmpty ? nil : ext.lowercased()
        return item
    }

    private func deduplicatedResultItems(_ items: [SearchResultItem]) -> [SearchResultItem] {
        var seenStableKeys: Set<String> = []
        var seenMetadataKeys: Set<String> = []
        return items.filter { result in
            let item = result.item
            let stableKey = item.serverId.map { "server:\($0)" } ?? "url:\(item.fileURL.absoluteString)"
            let metadataKey = [
                item.displayTitle.lowercased(),
                item.year.map(String.init) ?? "",
                item.duration > 0 ? String(Int(item.duration)) : "",
            ].joined(separator: "|")
            guard seenStableKeys.insert(stableKey).inserted else { return false }
            guard seenMetadataKeys.insert(metadataKey).inserted else { return false }
            return true
        }
    }
}

private struct SearchConnectionSnapshot: Sendable {
    let id: UUID
    let name: String
    let type: ConnectionType
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let path: String?
    let bookmarkData: Data?

    var config: ConnectionConfig {
        ConnectionConfig(
            connectionId: id,
            type: type,
            host: host,
            port: port,
            username: username,
            password: password,
            path: path,
            bookmarkData: bookmarkData
        )
    }

    var isFileSearchable: Bool {
        switch type {
        case .localFolder, .smb, .webdav, .alist, .fnos:
            return true
        default:
            return false
        }
    }

    var isSearchEligible: Bool {
        type.isMediaServer || isFileSearchable
    }

    init(connection: SavedConnection, password: String?) {
        self.id = connection.id
        self.name = connection.name
        self.type = connection.type
        self.host = connection.host
        self.port = connection.port
        self.username = connection.username
        self.password = password
        self.path = connection.path
        self.bookmarkData = connection.bookmarkData
    }
}

private struct RemoteSearchPayload: Sendable {
    let connectionId: UUID
    let sourceName: String
    let sourceSubtitle: String
    let serverItems: [ServerMediaItem]
    let files: [RemoteFileHit]
}

private struct RemoteFileHit: Sendable {
    let name: String
    let path: String
    let size: Int64
    let streamURL: URL
}
