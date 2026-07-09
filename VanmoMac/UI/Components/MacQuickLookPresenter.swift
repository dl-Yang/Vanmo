import AppKit
import Foundation
import QuickLookUI

enum MacQuickLookPresenter {
    private static let dataSource = PreviewDataSource()

    static func preview(_ url: URL) {
        guard url.isFileURL else { return }

        dataSource.previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = dataSource
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class PreviewDataSource: NSObject, QLPreviewPanelDataSource {
    var previewURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
