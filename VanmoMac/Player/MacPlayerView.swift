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
    @State private var debugHoldLoading = false
    @State private var playbackStalled = false
    @State private var lastPlaybackAdvance = Date()

    private var showsLoadingChrome: Bool {
        if debugHoldLoading { return true }
        switch viewModel.playbackState {
        case .playing:
            return playbackStalled
        case .paused:
            return false
        default:
            return true
        }
    }

    init(item: MediaItem, startPosition: TimeInterval) {
        _viewModel = StateObject(wrappedValue: MacPlayerViewModel(item: item, startPosition: startPosition))
    }

    var body: some View {
        configuredSurface
            .onChange(of: viewModel.currentTime) { _, _ in
                lastPlaybackAdvance = Date()
                playbackStalled = false
            }
            .onChange(of: viewModel.playbackState) { _, state in
                lastPlaybackAdvance = Date()
                if state != .playing {
                    playbackStalled = false
                }
            }
            .task(id: viewModel.playbackState) {
                guard viewModel.playbackState == .playing else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard viewModel.playbackState == .playing else { return }
                    if Date().timeIntervalSince(lastPlaybackAdvance) > 1.2 {
                        playbackStalled = true
                    }
                }
            }
    }

    private var configuredSurface: some View {
        playbackSurface
            .background(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear {
                isFocused = true
                appState.registerActivePlayer(viewModel)
#if DEBUG
                if ProcessInfo.processInfo.environment["VANMO_DEBUG_HOLD_LOADING"] == "1" {
                    debugHoldLoading = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        debugHoldLoading = false
                    }
            }
#endif
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
#if DEBUG
            .task {
                await runDebugPlayerScriptIfNeeded()
            }
#endif
            .onDisappear {
                viewModel.cleanup()
                appState.unregisterActivePlayer()
                reloadLibrary()
            }
            .sheet(isPresented: $viewModel.showAudioSelector) {
                MacAudioTrackSelectorView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showSubtitleSelector) {
                MacSubtitleSelectorView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showEpisodeSelector) {
                MacEpisodeSelectorView(viewModel: viewModel)
            }
            .alert(L10n.tr("提示"), isPresented: alertBinding) {
                Button(L10n.tr("确定"), role: .cancel) {
                    viewModel.alertMessage = nil
                }
            } message: {
                if let message = viewModel.alertMessage {
                    Text(message)
                }
            }
    }

    private var playbackSurface: some View {
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
                stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .black.opacity(0), location: 0.45),
                    .init(color: .black.opacity(0.6), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            MacPlayerControlsOverlay(
                viewModel: viewModel,
                title: appState.playerItem?.displayTitle ?? appState.playerItem?.title ?? L10n.tr("播放器"),
                showsLoadingChrome: showsLoadingChrome,
                onClose: closePlayer
            )
        }
        .overlay {
            if showsLoadingChrome {
                ScreenEdgeLoadingLight()
                    .allowsHitTesting(false)
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

#if DEBUG
    /// `VANMO_DEBUG_PLAYER_SCRIPT=seek:0.6,seek:0.2,pause,resume,wait:10,close`：首次进入 playing 后每步间隔 4 秒执行。
    /// `close` 走窗口 `performClose`，与点击红色关闭按钮的收尾路径一致。
    private func runDebugPlayerScriptIfNeeded() async {
        guard let script = ProcessInfo.processInfo.environment["VANMO_DEBUG_PLAYER_SCRIPT"] else { return }
        let steps = script.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        while viewModel.playbackState != .playing || viewModel.duration <= 0 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        for step in steps {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            let time = Int(viewModel.currentTime)
            VanmoLogger.player.info("[Debug][PlayerScript] step=\(step, privacy: .public) timeSec=\(time, privacy: .public)")
            if step == "pause" || step == "resume" {
                viewModel.togglePlayPause()
            } else if step == "close" {
                NSApp.windows.first { $0.windowController is MacPlayerWindowController }?.performClose(nil)
                return
            } else if step.hasPrefix("seek:"), let progress = Double(step.dropFirst(5)) {
                viewModel.seek(to: progress)
            } else if step.hasPrefix("wait:"), let seconds = Double(step.dropFirst(5)) {
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }
#endif

    private func reloadLibrary() {
        libraryViewModel.reload(
            filter: appState.selectedFilter,
            section: appState.selectedSection
        )
    }
}

private struct ScreenEdgeLoadingLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : Self.phase(since: startDate, at: timeline.date)
            EdgeCometStroke(phase: phase, cornerRadius: 16)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func phase(since start: Date, at date: Date) -> CGFloat {
        let period: TimeInterval = 2
        return CGFloat(date.timeIntervalSince(start).truncatingRemainder(dividingBy: period) / period)
    }
}

private struct EdgeCometStroke: View {
    var phase: CGFloat
    var cornerRadius: CGFloat

    private let cometLength: CGFloat = 0.14
    private let coreWidth: CGFloat = 3.5
    /// Outermost first, so each brighter layer draws over the wider bloom beneath it.
    private static let glowLayers: [(lineWidth: CGFloat, opacity: Double, blur: CGFloat)] = [
        (28, 0.3, 12),
        (13, 0.5, 4.5),
        (6.5, 0.85, 1.2)
    ]

    var body: some View {
        Canvas { context, size in
            let inset = coreWidth / 2 + 3
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            guard rect.width > 4, rect.height > 4 else { return }
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            let path = Self.pathStartingAtTopLeft(Path(roundedRect: rect, cornerRadius: radius, style: .continuous))
            var comet = path.trimmedPath(from: phase, to: min(phase + cometLength, 1))
            if phase + cometLength > 1 {
                comet.addPath(path.trimmedPath(from: 0, to: phase + cometLength - 1))
            }
            for glow in Self.glowLayers {
                strokeComet(context: &context, comet: comet, lineWidth: glow.lineWidth, color: Color.white.opacity(glow.opacity), blur: glow.blur)
            }
            strokeComet(context: &context, comet: comet, lineWidth: coreWidth, color: .white, blur: 0)
        }
        .allowsHitTesting(false)
    }

    /// `Path(roundedRect:)` starts at the middle of the right edge; the comet must enter through the top-left corner instead.
    /// Falls back to the original path if the left edge has no straight segment.
    private static func pathStartingAtTopLeft(_ path: Path) -> Path {
        var origin: CGPoint?
        var segments: [Path.Element] = []
        path.forEach { element in
            switch element {
            case .move(let point):
                origin = point
            case .closeSubpath:
                if let origin { segments.append(.line(to: origin)) }
            default:
                segments.append(element)
            }
        }
        let bounds = path.boundingRect
        guard let pivot = segments.firstIndex(where: { element in
            guard case .line(let end) = element else { return false }
            return abs(end.x - bounds.minX) < 0.5 && end.y < bounds.midY
        }), case .line(let cornerStart) = segments[pivot] else { return path }

        var anchored = Path()
        anchored.move(to: cornerStart)
        for element in segments[(pivot + 1)...] + segments[...pivot] {
            switch element {
            case .line(let end):
                anchored.addLine(to: end)
            case .quadCurve(let end, let control):
                anchored.addQuadCurve(to: end, control: control)
            case .curve(let end, let control1, let control2):
                anchored.addCurve(to: end, control1: control1, control2: control2)
            case .move, .closeSubpath:
                break
            }
        }
        anchored.closeSubpath()
        return anchored
    }

    private func strokeComet(
        context: inout GraphicsContext,
        comet: Path,
        lineWidth: CGFloat,
        color: Color,
        blur: CGFloat
    ) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        context.drawLayer { layer in
            if blur > 0 {
                layer.addFilter(.blur(radius: blur))
            }
            layer.stroke(comet, with: .color(color), style: style)
        }
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
