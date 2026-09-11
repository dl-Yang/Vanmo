import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ThumbnailOfficialPoster: Sendable {
    case jpeg(Data)
    case skipKeyframe
    case useKeyframe
}

public typealias ThumbnailOfficialPosterResolver = @Sendable (UUID, String) async -> ThumbnailOfficialPoster

public enum VideoThumbnailError: Error, Sendable, Equatable {
    case cancelled
    case timedOut
    case generationFailed
    case encodingFailed
    case unsupportedURL

    public var debugName: String {
        switch self {
        case .cancelled: return "cancelled"
        case .timedOut: return "timedOut"
        case .generationFailed: return "generationFailed"
        case .encodingFailed: return "encodingFailed"
        case .unsupportedURL: return "unsupportedURL"
        }
    }
}

public enum VideoThumbnailCacheKey {
    public static func make(
        connectionId: UUID,
        path: String,
        fileSize: Int64,
        modifiedAt: Date?
    ) -> String {
        let modified = modifiedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let raw = "\(connectionId.uuidString.lowercased())|\(path)|\(fileSize)|\(modified)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct VideoThumbnailRequest: Sendable, Hashable {
    public let connectionId: UUID
    public let path: String
    public let fileSize: Int64
    public let modifiedAt: Date?
    public let sourceURL: URL

    public init(
        connectionId: UUID,
        path: String,
        fileSize: Int64,
        modifiedAt: Date?,
        sourceURL: URL
    ) {
        self.connectionId = connectionId
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.sourceURL = sourceURL
    }

    public var cacheKey: String {
        VideoThumbnailCacheKey.make(
            connectionId: connectionId,
            path: path,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    public static func from(item: MediaItem, sourceURL: URL) -> VideoThumbnailRequest? {
        guard let connectionId = item.sourceConnectionId,
              let path = item.serverId, !path.isEmpty else {
            return nil
        }
        return VideoThumbnailRequest(
            connectionId: connectionId,
            path: path,
            fileSize: item.fileSize,
            modifiedAt: item.remoteModifiedAt,
            sourceURL: sourceURL
        )
    }
}

public protocol VideoThumbnailExtracting: Sendable {
    func extractJPEG(from url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data
}

public enum VideoThumbnailContentType {
    public static func identifier(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mov":
            return UTType.quickTimeMovie.identifier
        case "m4v", "mp4":
            return UTType.mpeg4Movie.identifier
        default:
            return UTType.mpeg4Movie.identifier
        }
    }

    public static func pathExtension(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "mp4" : ext
    }
}

public enum VideoThumbnailJPEG {
    public static func encode(_ image: CGImage, maxPixelSize: Int, quality: Double = 1.0) throws -> Data {
        let scaled = scale(image, maxPixelSize: maxPixelSize)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw VideoThumbnailError.encodingFailed
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw VideoThumbnailError.encodingFailed
        }
        return data as Data
    }

    public static func scale(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard maxPixelSize > 0, longest > maxPixelSize else { return image }

        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

public struct VideoThumbnailStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("Vanmo/Thumbnails", isDirectory: true)
        }
    }

    public func fileURL(for cacheKey: String) -> URL {
        directory.appendingPathComponent("\(cacheKey).jpg")
    }

    public func existingURL(for cacheKey: String) -> URL? {
        let url = fileURL(for: cacheKey)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func save(_ data: Data, for cacheKey: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: cacheKey)
        try data.write(to: url, options: .atomic)
        return url
    }
}
