import SwiftData
import SwiftUI
import VanmoCore

struct MacPlayerView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MacPlayerViewModel
    @FocusState private var isFocused: Bool

    init(item: MediaItem, startPosition: TimeInterval) {
        _viewModel = StateObject(wrappedValue: MacPlayerViewModel(item: item, startPosition: startPosition))
    }

    var body: some View {
        ZStack {
            if viewModel.usesKSPlayer {
                MacKSPlayerView(
                    videoView: viewModel.ksVideoView,
                    scaleMode: viewModel.config.scaleMode
                )
                .ignoresSafeArea()
            } else {
                MacAVPlayerView(player: viewModel.player, videoGravity: viewModel.videoGravity)
                    .ignoresSafeArea()
            }

            MacSubtitleOverlayView(
                text: viewModel.currentSubtitleText,
                style: viewModel.subtitleStyle
            )
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
                onClose: closePlayer
            )
        }
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            appState.registerActivePlayer(viewModel)
        }
        .onChange(of: viewModel.isPlaying) { _, newValue in
            appState.syncPlayerPlayingState(newValue)
        }
        .onKeyPress(.space) {
            viewModel.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.skip(by: -15)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.skip(by: 15)
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.adjustVolume(by: 0.05)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.adjustVolume(by: -0.05)
            return .handled
        }
        .onKeyPress("f") {
            viewModel.toggleFullScreen()
            return .handled
        }
        .onKeyPress(.escape) {
            closePlayer()
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerTogglePlayPause)) { _ in
            viewModel.togglePlayPause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerSkipBackward)) { _ in
            viewModel.skip(by: -15)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerSkipForward)) { _ in
            viewModel.skip(by: 15)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerVolumeUp)) { _ in
            viewModel.adjustVolume(by: 0.05)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerVolumeDown)) { _ in
            viewModel.adjustVolume(by: -0.05)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerToggleFullScreen)) { _ in
            viewModel.toggleFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPlayerClose)) { _ in
            closePlayer()
        }
        .task {
            await viewModel.onAppear(
                modelContext: modelContext,
                connectionsViewModel: connectionsViewModel
            )
        }
        .onDisappear {
            viewModel.cleanup()
            appState.unregisterActivePlayer()
            reloadLibrary()
        }
        .sheet(isPresented: $viewModel.showTrackSelector) {
            MacTrackSelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showEpisodeSelector) {
            MacEpisodeSelectorView(viewModel: viewModel)
        }
        .alert("提示", isPresented: alertBinding) {
            Button("确定", role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            if let message = viewModel.alertMessage {
                Text(message)
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.alertMessage = nil
                }
            }
        )
    }

    private func closePlayer() {
        viewModel.cleanup()
        reloadLibrary()
        appState.closePlayer()
    }

    private func reloadLibrary() {
        libraryViewModel.reload(
            filter: appState.selectedFilter,
            section: appState.selectedSection
        )
    }
}

#Preview {
    MacPlayerView(item: MacPlayerPreviewItem.make(), startPosition: 0)
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
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
