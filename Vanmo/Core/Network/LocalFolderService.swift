import Foundation

/// 本地文件夹（含沙盒 Documents、iCloud Drive、外部 File Provider）。
///
/// 通过 `UIDocumentPicker` / `fileImporter` 选定的目录是 security-scoped 资源，
/// 必须用 bookmark 持久化，并在运行期内 `startAccessingSecurityScopedResource`
/// 才能读取目录内的子文件。Service 在 `disconnect` 之前持续保持 access。
final class LocalFolderService: RemoteFileService {
    let type: ConnectionType = .localFolder
    private(set) var isConnected = false

    private var rootURL: URL?
    private var isAccessing: Bool = false

    deinit {
        if isAccessing, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
    }

    func connect(config: ConnectionConfig) async throws {
        guard let bookmarkData = config.bookmarkData else {
            throw NetworkError.connectionFailed("缺少文件夹访问凭据 (bookmark)")
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw NetworkError.connectionFailed("无法解析文件夹书签: \(error.localizedDescription)")
        }

        if isStale {
            VanmoLogger.network.warning("LocalFolder bookmark stale: \(url.path)")
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw NetworkError.authenticationFailed
        }

        self.rootURL = url
        self.isAccessing = true
        self.isConnected = true
        VanmoLogger.network.info("LocalFolder connected: \(url.path)")
    }

    func disconnect() async {
        if isAccessing, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
            VanmoLogger.network.info("LocalFolder disconnected: \(rootURL.path)")
        }
        isAccessing = false
        rootURL = nil
        isConnected = false
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard isConnected, let rootURL else { throw NetworkError.notConnected }

        let target = resolveURL(for: path, root: rootURL)
        let fm = FileManager.default

        let resourceKeys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isRegularFileKey,
        ]

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }

        var files: [RemoteFile] = []
        files.reserveCapacity(contents.count)

        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isDir = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate
            let fileType: RemoteFileType = isDir ? .directory : .from(filename: url.lastPathComponent)

            let file = RemoteFile(
                name: url.lastPathComponent,
                path: url.path,
                size: size,
                isDirectory: isDir,
                modifiedDate: modified,
                type: fileType
            )
            files.append(file)
        }

        return files
    }

    func streamURL(for file: RemoteFile) async throws -> URL {
        guard isConnected else { throw NetworkError.notConnected }
        return URL(fileURLWithPath: file.path)
    }

    func download(
        file: RemoteFile,
        to localURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let src = URL(fileURLWithPath: file.path)
        do {
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: src, to: localURL)
            progress(1.0)
        } catch {
            throw NetworkError.transferFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    /// `path` 既可能是 `/`（首次扫描根目录），也可能是子目录的 POSIX 绝对路径
    /// （递归扫描时由 `RemoteFile.path` 透传过来）。
    private func resolveURL(for path: String, root: URL) -> URL {
        if path.isEmpty || path == "/" {
            return root
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return root.appendingPathComponent(path)
    }
}
