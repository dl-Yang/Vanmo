import Foundation

/// 会话级临时缓存目录管理与启动时孤儿清理。
enum PrefetchTemporaryStore {
    static var rootDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(PrefetchConfig.prefetchDirectoryName, isDirectory: true)
    }

    /// App 启动时删除 `tmp/prefetch` 下残留（崩溃或未正常 unregister）。
    static func cleanupOrphans() {
        let fm = FileManager.default
        let root = rootDirectory
        guard fm.fileExists(atPath: root.path) else { return }
        do {
            let names = try fm.contentsOfDirectory(atPath: root.path)
            for name in names {
                let url = root.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    try fm.removeItem(at: url)
                }
            }
            VanmoLogger.prefetch.info("[Prefetch] cleaned orphan session dirs under prefetch tmp")
        } catch {
            VanmoLogger.prefetch.error("[Prefetch] orphan cleanup failed: \(error.localizedDescription)")
        }
    }

    static func sessionDirectory(sessionId: String) -> URL {
        rootDirectory.appendingPathComponent(sessionId, isDirectory: true)
    }
}
