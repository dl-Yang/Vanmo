import Foundation

public enum DownloadTaskStatus: String, Codable, Sendable {
    case queued
    case downloading
    case completed
    case failed
}

public enum DownloadError: LocalizedError {
    case unsupportedSource
    case missingConnection
    case sourceUnavailable
    case destinationUnavailable
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "此资源不支持下载"
        case .missingConnection:
            return "找不到资源对应的连接"
        case .sourceUnavailable:
            return "下载源不可用"
        case .destinationUnavailable:
            return "下载目录不可用，请重新选择"
        case .invalidResponse:
            return "服务器响应无效"
        case .httpStatus(let code):
            return "下载失败 (HTTP \(code))"
        }
    }
}

public struct DownloadRequest: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let sourceConnectionId: UUID?
    public let connectionType: ConnectionType?
    public let remotePath: String
    public let sourceFileURL: URL?
    public let fileName: String
    public let displayTitle: String
    public let mediaType: MediaType
    public let totalBytes: Int64
    public let showTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?

    public init(
        id: UUID = UUID(),
        sourceConnectionId: UUID?,
        connectionType: ConnectionType?,
        remotePath: String,
        sourceFileURL: URL? = nil,
        fileName: String,
        displayTitle: String,
        mediaType: MediaType,
        totalBytes: Int64 = 0,
        showTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) {
        self.id = id
        self.sourceConnectionId = sourceConnectionId
        self.connectionType = connectionType
        self.remotePath = remotePath
        self.sourceFileURL = sourceFileURL
        self.fileName = Self.sanitizedFileName(fileName)
        self.displayTitle = displayTitle
        self.mediaType = mediaType
        self.totalBytes = totalBytes
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
    }

    public var sourceKey: String {
        if let sourceConnectionId {
            return "\(sourceConnectionId.uuidString):\(remotePath)"
        }
        return sourceFileURL?.standardizedFileURL.path ?? remotePath
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let components = name.components(separatedBy: invalid)
        let value = components.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? UUID().uuidString : value
    }
}

public struct DownloadDestination: Codable, Hashable, Sendable {
    public let rootPath: String
    public let bookmarkData: Data?

    public init(rootPath: String, bookmarkData: Data? = nil) {
        self.rootPath = rootPath
        self.bookmarkData = bookmarkData
    }
}

public struct DownloadTaskSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let request: DownloadRequest
    public let destination: DownloadDestination
    public var status: DownloadTaskStatus
    public var receivedBytes: Int64
    public var totalBytes: Int64
    public var localFileName: String
    public var errorMessage: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        request: DownloadRequest,
        destination: DownloadDestination,
        status: DownloadTaskStatus = .queued,
        receivedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        localFileName: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.request = request
        self.destination = destination
        self.status = status
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes ?? request.totalBytes
        self.localFileName = localFileName ?? request.fileName
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
    }
}

public enum DownloadEligibility {
    public static func isEligible(file: RemoteFile, connectionType: ConnectionType) -> Bool {
        guard file.isVideo, !file.isDirectory, isSupported(connectionType: connectionType) else {
            return false
        }
        return isEligible(path: file.path, fileName: file.name)
    }

    public static func isEligible(item: MediaItem, connectionType: ConnectionType?) -> Bool {
        guard item.mediaType == .movie || item.mediaType == .tvEpisode else { return false }
        if let connectionType, !isSupported(connectionType: connectionType) { return false }
        return isEligible(path: item.serverId ?? item.fileURL.path, fileName: item.originalFileName ?? item.fileURL.lastPathComponent)
    }

    public static func isSupported(connectionType: ConnectionType) -> Bool {
        switch connectionType {
        case .localFolder, .smb, .webdav, .alist, .baiduNetdisk, .googleDrive,
             .oneDrive, .box, .pCloudDrive, .yandexDisk, .fnos, .plex, .emby, .jellyfin:
            return true
        case .ftp, .sftp, .removedOfficialCloudDrive, .drive115, .quarkDrive,
             .mega, .iptv, .nfs, .dlna:
            return false
        }
    }

    private static func isEligible(path: String, fileName: String) -> Bool {
        let combined = "\(path)/\(fileName)"
        let uppercased = combined.uppercased()
        guard !uppercased.contains("/BDMV/"), !uppercased.hasSuffix("/BDMV") else {
            return false
        }
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return !MediaFormatProbe.playlistExtensions.contains(ext)
            && !MediaFormatProbe.discPlaylistExtensions.contains(ext)
    }
}
