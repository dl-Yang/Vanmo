import SwiftUI
import VanmoCore

struct MacPlayerView: View {
    @EnvironmentObject private var appState: MacAppState
    @StateObject private var viewModel: MacPlayerViewModel

    init(item: MediaItem, startPosition: TimeInterval) {
        _viewModel = StateObject(wrappedValue: MacPlayerViewModel(item: item, startPosition: startPosition))
    }

    var body: some View {
        ZStack {
            MacAVPlayerView(player: viewModel.player)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            MacPlayerControlsOverlay(
                viewModel: viewModel,
                title: appState.playerItem?.displayTitle ?? appState.playerItem?.title ?? "Player",
                onClose: {
                    viewModel.cleanup()
                    appState.closePlayer()
                }
            )
        }
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MacPlayerView(item: MacPlayerPreviewItem.make(), startPosition: 0)
        .environmentObject(MacAppState())
        .frame(width: 1470, height: 836)
}

private enum MacPlayerPreviewItem {
    static func make() -> MediaItem {
        MediaItem(
            title: "Preview Title",
            fileURL: URL(fileURLWithPath: "/tmp/preview.mkv"),
            mediaType: .movie,
            fileSize: 0,
            duration: 7200
        )
    }
}
