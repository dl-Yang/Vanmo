import Combine
import Foundation
import SwiftData

/// iOS / macOS「打开 URL 链接」页共享的列表状态：输入校验、最近链接、串流与下载入队。
@MainActor
public final class DirectLinkListModel: ObservableObject {
    @Published public var input = "" {
        didSet { if inputError != nil { inputError = nil } }
    }
    @Published public private(set) var entries: [MediaItem] = []
    @Published public var inputError: String?
    @Published public var alertMessage: String?

    private var modelContext: ModelContext?

    public init() {}

    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        reload()
    }

    public func reload() {
        guard let modelContext else { return }
        entries = DirectLinkLibrary.entries(in: modelContext)
    }

    /// 解析输入框并保存链接；无效时返回 `nil` 并写入 `inputError`。
    public func addInput() -> MediaItem? {
        guard let modelContext else { return nil }
        switch DirectLinkLibrary.parse(input) {
        case .failure(let error):
            inputError = error.localizedDescription
            return nil
        case .success(let url):
            do {
                let item = try DirectLinkLibrary.upsert(url: url, in: modelContext)
                input = ""
                reload()
#if DEBUG
                let host = url.host ?? ""
                let ext = url.pathExtension.lowercased()
                VanmoLogger.network.info("[Debug][DirectLink] added host=\(host, privacy: .public) ext=\(ext, privacy: .public)")
#endif
                return item
            } catch {
                alertMessage = error.localizedDescription
                return nil
            }
        }
    }

    public func downloadInput(using manager: DownloadManager) async {
        guard let item = addInput() else { return }
        await download(item, using: manager)
    }

    public func download(_ item: MediaItem, using manager: DownloadManager) async {
        guard !DirectLinkLibrary.isStreamOnly(item.fileURL) else {
            alertMessage = L10n.tr("该链接仅支持串流播放")
            return
        }
        do {
            let request = try DownloadRequestFactory.make(from: item, connectionType: nil)
            try await manager.enqueue(request)
        } catch {
#if DEBUG
            let nsError = error as NSError
            let domain = nsError.domain
            let code = nsError.code
            VanmoLogger.library.error("[Debug][Downloads] enqueue failed source=directLink domain=\(domain, privacy: .public) code=\(code, privacy: .public)")
#endif
            alertMessage = error.localizedDescription
        }
    }

    public func remove(_ item: MediaItem) {
        guard let modelContext else { return }
        do {
            try DirectLinkLibrary.remove(item, in: modelContext)
            reload()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
