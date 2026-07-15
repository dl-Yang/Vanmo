import Foundation

actor DownloadTaskStore {
    private let rootDirectory: URL
    private let manifestURL: URL
    private let partsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL? = nil) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.rootDirectory = rootDirectory
            ?? applicationSupport.appendingPathComponent("Vanmo/DownloadTasks", isDirectory: true)
        self.manifestURL = self.rootDirectory.appendingPathComponent("manifest.json")
        self.partsDirectory = self.rootDirectory.appendingPathComponent("parts", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> [DownloadTaskSnapshot] {
        try prepareDirectories()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode([DownloadTaskSnapshot].self, from: data)
    }

    func save(_ tasks: [DownloadTaskSnapshot]) throws {
        try prepareDirectories()
        let data = try encoder.encode(tasks)
        try data.write(to: manifestURL, options: .atomic)
    }

    func partURL(for id: UUID) throws -> URL {
        try prepareDirectories()
        return partsDirectory.appendingPathComponent("\(id.uuidString).part")
    }

    func removePart(for id: UUID) throws {
        let url = try partURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partsDirectory, withIntermediateDirectories: true)
    }
}
