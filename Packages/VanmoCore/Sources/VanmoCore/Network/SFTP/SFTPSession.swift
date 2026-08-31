import Citadel
import Foundation

/// Thin Citadel wrapper: password SSH login, SFTP listing, STAT, offset reads.
actor SFTPSession {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String

    private var ssh: SSHClient?
    private var sftp: SFTPClient?
    private var isReady = false

    init(host: String, port: Int, username: String?, password: String?) {
        self.host = host
        self.port = port > 0 ? port : 22
        self.username = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.password = password ?? ""
    }

    func login() async throws {
        if isReady { return }
        guard !username.isEmpty else { throw NetworkError.authenticationFailed }

        do {
            var settings = SSHClientSettings(
                host: host,
                authenticationMethod: { [username, password] in
                    .passwordBased(username: username, password: password)
                },
                hostKeyValidator: .acceptAnything()
            )
            settings.port = port
            let ssh = try await SSHClient.connect(to: settings)
            let sftp = try await ssh.openSFTP()
            self.ssh = ssh
            self.sftp = sftp
            isReady = true
            let hasPassword = password.isEmpty ? "no" : "yes"
            VanmoLogger.network.info(
                "[SFTP] login ok host=\(self.host) port=\(self.port) user=\(self.username) hasPassword=\(hasPassword)"
            )
        } catch {
            await closeQuietly()
            throw Self.mapped(error)
        }
    }

    func close() async {
        await closeQuietly()
        VanmoLogger.network.info("[SFTP] disconnected")
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        let sftp = try await readyClient()
        let normalized = SFTPPath.normalize(path)
        let names: [SFTPMessage.Name]
        do {
            names = try await sftp.listDirectory(atPath: normalized)
        } catch {
            throw Self.mapped(error)
        }

        var files: [RemoteFile] = []
        for batch in names {
            for component in batch.components {
                guard SFTPPath.isListableName(component.filename) else { continue }
                let isDirectory = SFTPPath.isDirectory(
                    permissions: component.attributes.permissions,
                    longname: component.longname
                )
                let size = Int64(component.attributes.size ?? 0)
                files.append(
                    RemoteFile(
                        name: component.filename,
                        path: SFTPPath.join(normalized, name: component.filename),
                        size: size,
                        isDirectory: isDirectory,
                        modifiedDate: component.attributes.accessModificationTime?.modificationTime,
                        type: isDirectory ? .directory : RemoteFileType.from(filename: component.filename)
                    )
                )
            }
        }
        VanmoLogger.network.info("[SFTP] listed \(files.count) entries under \(normalized)")
        return files
    }

    func fileSize(at path: String) async throws -> Int64 {
        let sftp = try await readyClient()
        let normalized = SFTPPath.normalize(path)
        do {
            let attributes = try await sftp.getAttributes(at: normalized)
            if let size = attributes.size {
                return Int64(size)
            }
        } catch {
            throw Self.mapped(error)
        }
        throw NetworkError.transferFailed("无法读取文件大小")
    }

    func readRange(path: String, offset: UInt64, length: UInt32) async throws -> Data {
        let sftp = try await readyClient()
        let normalized = SFTPPath.normalize(path)
        do {
            return try await sftp.withFile(filePath: normalized, flags: .read) { file in
                let buffer = try await file.read(from: offset, length: length)
                return Data(buffer: buffer)
            }
        } catch {
            throw Self.mapped(error)
        }
    }

    func downloadResuming(
        path: String,
        to localURL: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let sftp = try await readyClient()
        let normalized = SFTPPath.normalize(path)
        if !FileManager.default.fileExists(atPath: localURL.path) {
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        var offset = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let total: Int64
        if expectedSize > 0 {
            total = expectedSize
        } else if let sized = try? await fileSize(at: normalized) {
            total = sized
        } else {
            total = 0
        }
        if total > 0, offset > total {
            let handle = try FileHandle(forWritingTo: localURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
            offset = 0
        }

        let destination = try FileHandle(forWritingTo: localURL)
        defer { try? destination.close() }
        try destination.seekToEnd()

        let file: SFTPFile
        do {
            file = try await sftp.openFile(filePath: normalized, flags: .read)
        } catch {
            throw Self.mapped(error)
        }
        do {
            let chunkSize: UInt32 = 256 * 1024
            while total == 0 || offset < total {
                try Task.checkCancellation()
                let remaining = total > 0 ? UInt64(total - offset) : UInt64(chunkSize)
                let request = UInt32(min(remaining, UInt64(chunkSize)))
                let buffer = try await file.read(from: UInt64(offset), length: request)
                let chunk = Data(buffer: buffer)
                if chunk.isEmpty { break }
                try destination.write(contentsOf: chunk)
                offset += Int64(chunk.count)
                progress(offset, total)
            }
            try await file.close()
        } catch {
            try? await file.close()
            throw Self.mapped(error)
        }
        try destination.synchronize()
        if total > 0, offset < total {
            throw NetworkError.transferFailed("SFTP 下载提前结束")
        }
    }

    private func readyClient() async throws -> SFTPClient {
        if isReady, let sftp, sftp.isActive { return sftp }
        isReady = false
        await closeQuietly()
        try await login()
        guard let sftp else { throw NetworkError.notConnected }
        return sftp
    }

    private func closeQuietly() async {
        if let sftp {
            try? await sftp.close()
        }
        if let ssh {
            try? await ssh.close()
        }
        sftp = nil
        ssh = nil
        isReady = false
    }

    private static func mapped(_ error: Error) -> Error {
        if let network = error as? NetworkError {
            return network
        }
        let text = String(describing: error).lowercased()
        if text.contains("auth") || text.contains("password") || text.contains("permission denied") {
            return NetworkError.authenticationFailed
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return NetworkError.connectionFailed(description)
        }
        return NetworkError.connectionFailed(error.localizedDescription)
    }
}
