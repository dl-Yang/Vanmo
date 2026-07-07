import SwiftUI
import VanmoCore

struct MacLibraryItemDestination: View {
    @EnvironmentObject private var appState: MacAppState

    let item: MediaItem

    var body: some View {
        switch item.mediaType {
        case .folder, .collectionFolder, .season, .boxSet:
            if item.serverId != nil {
                MacEmbyFolderBrowseView(container: item)
            } else {
                MacMediaDetailView(item: item)
            }
        default:
            MacMediaDetailView(item: item)
        }
    }
}
