import AVFoundation
import Foundation

public struct AVFoundationVideoThumbnailExtractor: VideoThumbnailExtracting {
    public init() {}

    public func extractJPEG(from url: URL, maxPixelSize: Int, timeout: TimeInterval) async throws -> Data {
        if PlaybackURLResolver.isPlaceholder(url) {
            throw VideoThumbnailError.unsupportedURL
        }
        if Self.requiresFFmpeg(url) {
            throw VideoThumbnailError.unsupportedURL
        }

        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.generateJPEG(from: url, maxPixelSize: maxPixelSize)
            }
            group.addTask {
                let nanoseconds = UInt64(max(timeout, 0.5) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw VideoThumbnailError.timedOut
            }

            guard let data = try await group.next() else {
                throw VideoThumbnailError.generationFailed
            }
            group.cancelAll()
            return data
        }
    }

    private func generateJPEG(from url: URL, maxPixelSize: Int) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let cgImage = try await generator.image(at: time).image
            return try VideoThumbnailJPEG.encode(cgImage, maxPixelSize: maxPixelSize)
        } catch is CancellationError {
            throw VideoThumbnailError.cancelled
        } catch let error as VideoThumbnailError {
            throw error
        } catch {
            throw VideoThumbnailError.generationFailed
        }
    }

    private static func requiresFFmpeg(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "smb" || scheme == "ftp" || scheme == "sftp" || scheme == "ftps"
    }
}
