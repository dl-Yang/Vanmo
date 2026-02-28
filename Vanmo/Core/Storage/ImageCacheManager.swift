import SwiftUI

actor ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500MB

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        return await downloadAndCache(url: url, key: key)
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func downloadAndCache(url: URL, key: String) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(data: data, key: key)

            return image
        } catch {
            return nil
        }
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        let fileURL = diskCacheURL.appendingPathComponent(key)
        try? data.write(to: fileURL)
    }

    private func cacheKey(for url: URL) -> String {
        url.absoluteString
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(64)
            .description
    }
}
