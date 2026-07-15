import Foundation

public enum DownloadPreferences {
    private static let customPathKey = "download.directory.customPath"
    private static let customBookmarkKey = "download.directory.customBookmark"

    public static var destination: DownloadDestination {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: customPathKey),
              let bookmark = defaults.data(forKey: customBookmarkKey) else {
            return DownloadDestination(rootPath: DownloadDirectoryResolver.defaultDirectory.path)
        }
        return DownloadDestination(rootPath: path, bookmarkData: bookmark)
    }

    public static func setCustomDirectory(_ url: URL) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        let bookmark = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(url.path, forKey: customPathKey)
        UserDefaults.standard.set(bookmark, forKey: customBookmarkKey)
    }

    public static func useDefaultDirectory() {
        UserDefaults.standard.removeObject(forKey: customPathKey)
        UserDefaults.standard.removeObject(forKey: customBookmarkKey)
    }
}

public final class ResolvedDownloadDirectory {
    public let url: URL
    private let isAccessingSecurityScopedResource: Bool

    init(url: URL, isAccessingSecurityScopedResource: Bool) {
        self.url = url
        self.isAccessingSecurityScopedResource = isAccessingSecurityScopedResource
    }

    deinit {
        if isAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

public enum DownloadDirectoryResolver {
    public static var defaultDirectory: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return base.appendingPathComponent("Vanmo", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Downloads", isDirectory: true)
        #endif
    }

    public static func resolve(_ destination: DownloadDestination) throws -> ResolvedDownloadDirectory {
        let url: URL
        var isAccessing = false
        if let bookmarkData = destination.bookmarkData {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else { throw DownloadError.destinationUnavailable }
            isAccessing = url.startAccessingSecurityScopedResource()
            guard isAccessing else { throw DownloadError.destinationUnavailable }
        } else {
            url = URL(fileURLWithPath: destination.rootPath, isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            throw DownloadError.destinationUnavailable
        }
        return ResolvedDownloadDirectory(url: url, isAccessingSecurityScopedResource: isAccessing)
    }
}
