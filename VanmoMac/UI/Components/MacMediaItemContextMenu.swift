import SwiftUI
import VanmoCore

struct MacMediaItemContextMenu: View {
    @EnvironmentObject private var appState: MacAppState

    let item: MediaItem

    var body: some View {
        Button {
            appState.play(item, from: item.lastPlaybackPosition)
        } label: {
            Label(L10n.tr("播放"), systemImage: "play.fill")
        }

        Button {
            appState.openDetail(item)
        } label: {
            Label(L10n.tr("查看详情"), systemImage: "info.circle")
        }

        if item.fileURL.isFileURL {
            Button {
                MacQuickLookPresenter.preview(item.fileURL)
            } label: {
                Label(L10n.tr("Quick Look 预览"), systemImage: "eye")
            }
        }
    }
}

extension View {
    func macMediaItemContextMenu(for item: MediaItem) -> some View {
        contextMenu {
            MacMediaItemContextMenu(item: item)
        }
    }
}
