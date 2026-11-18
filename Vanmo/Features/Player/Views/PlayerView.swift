import SwiftUI
import AVFoundation
import AVKit
import SwiftData
import VanmoCore

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: PlayerViewModel
    @StateObject private var pictureInPicture = PlayerPictureInPictureController()
    @State private var activePopoverTab: PlayerPopoverTab?
    @State private var debugHoldLoading = false
    @State private var playbackStalled = false
    @State private var lastPlaybackAdvance = Date()
    @State private var dragAxis: DragAxis?
    @State private var lastVerticalTranslation: CGFloat = 0
    @State private var isClosingPlayer = false
    @State private var suppressEntranceAnimation = true
    private let onClose: (() -> Void)?

    private enum DragAxis {
        case horizontal
        case vertical
    }

    init(item: MediaItem, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
        self.onClose = onClose
    }

    var body: some View {
        playerSurface()
    }

    private func playerSurface() -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            if let holdImage = viewModel.qualityHoldImage {
                QualityHoldFrame(image: holdImage, scaleMode: viewModel.config.scaleMode)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if case .error(let message) = viewModel.playbackState {
                errorStateOverlay(message: message)
            }

            SubtitleOverlayView(
                content: viewModel.currentSubtitleContent,
                style: viewModel.subtitleStyle
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            gestureLayer
                .allowsHitTesting(!viewModel.controlsVisible)

            if activePopoverTab != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activePopoverTab = nil
                        }
                    }
            }

            if viewModel.controlsVisible {
                controlsOverlay()
            }

            feedbackOverlays

            if let notice = viewModel.notice {
                PlayerNoticeOverlay(notice: notice) {
                    viewModel.notice = nil
                }
                .zIndex(90)
            }

            if viewModel.isRateBoosting {
                rateBoostIndicator
            }
        }
        .overlay {
            if showsLoadingChrome {
                ScreenEdgeLoadingLight()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let tab = activePopoverTab, viewModel.controlsVisible {
                PlayerTracksPopover(
                    viewModel: viewModel,
                    selectedTab: Binding(
                        get: { tab },
                        set: { activePopoverTab = $0 }
                    ),
                    onClosePopover: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activePopoverTab = nil
                        }
                    },
                    onOpenSubtitleTools: { viewModel.showSubtitleSelector = true },
                    onOpenChapters: { viewModel.showChapterList = true },
                    onOpenEpisodes: { viewModel.showEpisodeSelector = true }
                )
                .padding(.top, 60)
                .padding(.trailing, 28)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
        .statusBarHidden(true)
        .transaction { transaction in
            if suppressEntranceAnimation {
                transaction.disablesAnimations = true
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                suppressEntranceAnimation = false
            }
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
        .task { await viewModel.onAppear(modelContext: modelContext) }
#if DEBUG
        .task { await runDebugPlayerScriptIfNeeded() }
#endif
        .onDisappear {
            let keepPlaybackActive = !isClosingPlayer
                && (
                    pictureInPicture.isActive
                    || viewModel.isPictureInPictureActive
                    || scenePhase == .background
                )
#if DEBUG
            let phaseName: String
            switch scenePhase {
            case .active: phaseName = "active"
            case .inactive: phaseName = "inactive"
            case .background: phaseName = "background"
            @unknown default: phaseName = "unknown"
            }
            VanmoLogger.player.info(
                "[Debug][PiP] playerDisappear scenePhase=\(phaseName, privacy: .public) keepPlayback=\(keepPlaybackActive, privacy: .public) closing=\(isClosingPlayer, privacy: .public)"
            )
#endif
            viewModel.onDisappear(keepingPlaybackActive: keepPlaybackActive)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            viewModel.handleScenePhase(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            viewModel.handleMemoryWarning()
        }
        .sheet(isPresented: $viewModel.showAudioSelector) {
            AudioTrackSelectorView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showSubtitleSelector) {
            SubtitleSelectorView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showChapterList) {
            ChapterListView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showEpisodeSelector) {
            EpisodeSelectorView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
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
        .onChange(of: viewModel.controlsVisible) { _, visible in
            if !visible {
                activePopoverTab = nil
            }
        }
    }

    private func errorStateOverlay(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(CatDesign.glowAmber)
            Text(L10n.tr("无法播放"))
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(CatDesign.Cinema.textMuted)
        }
        .foregroundStyle(CatDesign.Cinema.textIvory)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(CatDesign.Cinema.surfaceGlass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 1)
        )
    }

    // MARK: - Video Layer

    @ViewBuilder
    private var videoLayer: some View {
        if let player = viewModel.avPlayer {
            AVPlayerVideoLayer(
                player: player,
                scaleMode: viewModel.config.scaleMode,
                pictureInPicture: pictureInPicture
            )
                .ignoresSafeArea()
        } else if let ksView = viewModel.ksPlayerVideoView {
            KSPlayerVideoLayer(videoView: ksView, scaleMode: viewModel.config.scaleMode)
                .id(ObjectIdentifier(ksView))
                .ignoresSafeArea()
        }
    }

    // MARK: - Gesture Layer

    private var gestureLayer: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    viewModel.togglePlayPause()
                }
                .onTapGesture {
                    viewModel.toggleControls()
                }
                .gesture(panGesture(in: geometry.size))
                .simultaneousGesture(rateBoostGesture)
        }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    dragAxis = horizontal > vertical ? .horizontal : .vertical
                    lastVerticalTranslation = value.translation.height
                }

                switch dragAxis {
                case .horizontal:
                    let seconds = value.translation.width / size.width * 120
                    viewModel.handleSeekGesture(Double(seconds))
                case .vertical:
                    let incremental = value.translation.height - lastVerticalTranslation
                    lastVerticalTranslation = value.translation.height
                    let delta = -Float(incremental / size.height)
                    if value.startLocation.x < size.width / 2 {
                        viewModel.handleBrightnessChange(delta)
                    } else {
                        viewModel.handleVolumeChange(delta)
                    }
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if dragAxis == .horizontal {
                    viewModel.commitSeekGesture()
                }
                dragAxis = nil
                lastVerticalTranslation = 0
            }
    }

    private var rateBoostGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, _) = value {
                    viewModel.handleRateBoost(isActive: true)
                }
            }
            .onEnded { _ in
                viewModel.handleRateBoost(isActive: false)
            }
    }

    // MARK: - Controls Overlay

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

    private func controlsOverlay() -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [CatDesign.catSilhouette.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 74)

                Spacer()

                LinearGradient(
                    colors: [.clear, CatDesign.catSilhouette.opacity(0.80)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 116)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if activePopoverTab != nil {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                activePopoverTab = nil
                            }
                        } else {
                            viewModel.toggleControls()
                        }
                    }

                bottomFloatingDeck
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    // MARK: - Top Floating Bar (`684:714`)

    private var topBar: some View {
        HStack(spacing: 12) {
            topLeftTitlePill

            Spacer(minLength: 8)

            topRightActionGroup
        }
        .frame(height: 42)
    }

    private var topLeftTitlePill: some View {
        HStack(spacing: 10) {
            Button(action: closePlayer) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.Cinema.textIvory)
                    .frame(width: 28, height: 28)
                    .background(CatDesign.Cinema.surfacePill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("关闭"))

            HStack(spacing: 8) {
                Text(viewModel.playerDisplayTitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(CatDesign.Cinema.textIvory)
                    .lineLimit(1)

                if let epBadge = viewModel.playerEpisodeBadge {
                    Text(epBadge)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CatDesign.glowAmber)
                        .lineLimit(1)
                }
            }

            if let techBadge = viewModel.playerTechnicalBadge {
                Text(techBadge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CatDesign.Cinema.textIvory)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CatDesign.Cinema.surfacePill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.75))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(CatDesign.Cinema.surfaceGlass))
        }
        .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.9))
    }

    private var topRightActionGroup: some View {
        HStack(spacing: 8) {
            if pictureInPicture.isSupported && viewModel.canShowPictureInPictureButton {
                Button {
                    if viewModel.avPlayer != nil {
                        pictureInPicture.toggle()
                    } else {
                        viewModel.toggleKSPictureInPicture()
                    }
                } label: {
                    Image(systemName: (pictureInPicture.isActive || viewModel.isPictureInPictureActive) ? "pip.exit" : "pip.enter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CatDesign.Cinema.textIvory)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().fill(CatDesign.Cinema.surfaceGlass))
                        }
                        .overlay(Circle().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel((pictureInPicture.isActive || viewModel.isPictureInPictureActive) ? L10n.tr("退出画中画") : L10n.tr("进入画中画"))
            }

            AirPlayRouteButton()
                .frame(width: 22, height: 22)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(CatDesign.Cinema.surfaceGlass))
                }
                .overlay(Circle().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.9))
                .accessibilityLabel(L10n.tr("投屏"))

            let isTracksActive = activePopoverTab != nil
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    activePopoverTab = isTracksActive ? nil : .subtitles
                }
            } label: {
                HStack(spacing: 6) {
                    Image("CatTrackSliders")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(isTracksActive ? CatDesign.glowAmber : CatDesign.Cinema.textIvory)

                    Text(L10n.tr("轨道"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isTracksActive ? CatDesign.glowAmber : CatDesign.Cinema.textIvory)
                }
                .padding(.leading, 12)
                .padding(.trailing, 13)
                .frame(height: 38)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule().fill(isTracksActive ? CatDesign.Cinema.surfaceGlassElevated : CatDesign.Cinema.surfaceGlass)
                        )
                }
                .overlay(
                    Capsule().strokeBorder(
                        isTracksActive ? CatDesign.Cinema.strokeAmber : CatDesign.Cinema.strokeGlass,
                        lineWidth: 0.9
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("轨道设置"))
        }
    }

#if DEBUG
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
                closePlayer()
                return
            } else if step.hasPrefix("seek:"), let progress = Double(step.dropFirst(5)) {
                viewModel.seek(to: viewModel.duration * min(max(progress, 0), 1))
            } else if step.hasPrefix("wait:"), let seconds = Double(step.dropFirst(5)) {
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }
#endif

    private func closePlayer() {
        guard !isClosingPlayer else { return }
        isClosingPlayer = true
        pictureInPicture.prepareForDismissal()
        viewModel.closePlayback()
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Bottom Floating Control Deck (`684:749`)

    @ViewBuilder
    private var bottomFloatingDeck: some View {
        if viewModel.isLiveStream {
            HStack {
                liveBadge
                Spacer()
            }
        } else {
            VStack(spacing: 10) {
                PlayerProgressBar(
                    progress: viewModel.progress,
                    cacheStart: viewModel.cacheStart,
                    cacheEnd: viewModel.cacheEnd,
                    isSeeking: $viewModel.isSeeking,
                    onScrub: { fraction in
                        viewModel.updateScrubTarget(fraction)
                    },
                    onSeek: { fraction in
                        viewModel.seek(to: fraction * viewModel.duration)
                    }
                )

                controlsRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(CatDesign.Cinema.surfaceGlass)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.9)
            )
            .overlay(alignment: .topLeading) {
                if viewModel.seekPreviewActive {
                    anchoredScrubPreview
                }
            }
        }
    }

    private var anchoredScrubPreview: some View {
        GeometryReader { proxy in
            let deckWidth = max(proxy.size.width, 138)
            let fraction = viewModel.duration > 0 ? min(max(viewModel.seekTime / viewModel.duration, 0), 1) : 0
            let rawX = fraction * deckWidth
            let clampedX = min(max(rawX, 69), max(deckWidth - 69, 69))

            scrubPreviewCard
                .position(x: clampedX, y: -56)
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 16) {
                Text("\(viewModel.displayTime.formattedDuration) / \(viewModel.duration.formattedDuration)")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(CatDesign.Cinema.textMuted)
                    .lineLimit(1)

                transportButtons
            }

            Spacer(minLength: 8)

            quickActionPills
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 14) {
            Button { viewModel.skipBackward() } label: {
                Image("CatSkipBack15")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("快退"))

            Button { viewModel.togglePlayPause() } label: {
                Group {
                    if showsLoadingChrome {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CatDesign.glowAmber)
                    } else if viewModel.playbackState == .playing {
                        Image("CatPlayerPause")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CatDesign.Cinema.textIvory)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsLoadingChrome
                    ? L10n.tr("正在加载")
                    : (viewModel.playbackState == .playing ? L10n.tr("暂停") : L10n.tr("播放"))
            )

            Button { viewModel.skipForward() } label: {
                Image("CatSkipForward15")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("快进"))

            Button {
                if viewModel.nextPlayableEpisode != nil {
                    Task { await viewModel.playNextEpisode() }
                } else if viewModel.canSelectEpisode {
                    viewModel.showEpisodeSelector = true
                }
            } label: {
                Image("CatNextEpisode")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .opacity(viewModel.canSelectEpisode ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSelectEpisode)
            .accessibilityLabel(L10n.tr("下一集"))
        }
    }

    private var quickActionPills: some View {
        HStack(spacing: 8) {
            if viewModel.canSkipIntro {
                Button {
                    viewModel.skipIntro()
                } label: {
                    HStack(spacing: 6) {
                        Image("CatLeapingEar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 14)

                        Text(L10n.tr("跳过片头"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CatDesign.glowAmber)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 11)
                    .frame(height: 28)
                    .background(CatDesign.glowAmber.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("跳过片头"))
            }

            quickPill(String(format: "%.2gx", viewModel.config.playbackRate), isActive: activePopoverTab == .speed) {
                togglePopoverTab(.speed)
            }

            quickPill(L10n.tr("音轨"), isActive: activePopoverTab == .audio) {
                togglePopoverTab(.audio)
            }

            quickPill(L10n.tr("字幕"), isActive: activePopoverTab == .subtitles) {
                togglePopoverTab(.subtitles)
            }
        }
    }

    private func togglePopoverTab(_ tab: PlayerPopoverTab) {
        withAnimation(.easeInOut(duration: 0.18)) {
            activePopoverTab = activePopoverTab == tab ? nil : tab
        }
    }

    private func quickPill(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? CatDesign.glowAmber : CatDesign.Cinema.textIvory)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    isActive ? CatDesign.glowAmber.opacity(0.14) : CatDesign.Cinema.surfacePill,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isActive ? CatDesign.Cinema.strokeAmber : CatDesign.Cinema.strokeGlass,
                        lineWidth: 0.75
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.red.opacity(0.25), in: Capsule())
    }

    // MARK: - Feedback Overlays

    private var feedbackOverlays: some View {
        ZStack {
            if let brightness = viewModel.brightnessOverlay {
                GaugeOverlay(
                    icon: "sun.max.fill",
                    value: Double(brightness),
                    label: "\(Int(brightness * 100))%"
                )
            }

            if let volume = viewModel.volumeOverlay {
                GaugeOverlay(
                    icon: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    value: Double(volume),
                    label: "\(Int(volume * 100))%"
                )
            }

            if let seekDelta = viewModel.seekOverlay {
                let isForward = seekDelta >= 0
                VStack(spacing: 4) {
                    Image(systemName: isForward ? "goforward" : "gobackward")
                        .font(.title2)
                        .foregroundStyle(CatDesign.glowAmber)
                    Text("\(isForward ? "+" : "")\(Int(seekDelta))s")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CatDesign.Cinema.textIvory)
                }
                .padding(16)
                .background(CatDesign.Cinema.surfaceGlassElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.8))
                .transition(.scale.combined(with: .opacity))
            }

            if viewModel.seekPreviewActive && !viewModel.controlsVisible {
                scrubPreviewCard
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.brightnessOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.volumeOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.seekOverlay)
        .animation(.easeInOut(duration: 0.15), value: viewModel.seekPreviewActive)
    }

    private var scrubPreviewCard: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image = viewModel.seekPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        CatDesign.mediaPlaceholder
                        Image(systemName: viewModel.seekPreviewForward ? "forward.fill" : "backward.fill")
                            .font(.title3)
                            .foregroundStyle(CatDesign.glowAmber)
                    }
                }
            }
            .frame(width: 138, height: 78)
            .clipped()

            LinearGradient(
                colors: [.clear, CatDesign.catSilhouette.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)

            Text(viewModel.seekTime.formattedDuration)
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(CatDesign.glowAmber)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
                .padding(.bottom, 6)
        }
        .frame(width: 138, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 1.1)
        )
        .shadow(color: .black.opacity(0.75), radius: 14, y: 8)
        .overlay(alignment: .top) {
            Image("CatLeaningPreview")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 30)
                .offset(x: 6, y: -25)
                .allowsHitTesting(false)
        }
    }

    private var rateBoostIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "forward.fill")
                .font(.subheadline)
                .foregroundStyle(CatDesign.glowAmber)
            Text(L10n.tr("%@x 倍速播放中", String(format: "%.1f", PlayerConfig.maximumRate)))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(CatDesign.Cinema.textIvory)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(CatDesign.Cinema.surfaceGlassElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRateBoosting)
    }
}

private struct PlayerNoticeOverlay: View {
    let notice: PlayerNotice
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(notice.title)
                    .font(.headline)

                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(L10n.tr("知道了"), action: dismiss)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Supporting Views

struct GaugeOverlay: View {
    let icon: String
    let value: Double
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(CatDesign.glowAmber)
            ProgressView(value: value)
                .frame(width: 100)
                .tint(CatDesign.glowAmber)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(CatDesign.Cinema.textIvory)
        }
        .padding(16)
        .background(CatDesign.Cinema.surfaceGlassElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.9)
        )
    }
}

// MARK: - AVPlayer Video Layer (AVFoundation Engine)

struct AVPlayerVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    let scaleMode: VideoScaleMode
    @ObservedObject var pictureInPicture: PlayerPictureInPictureController

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = scaleMode.avLayerVideoGravity
        pictureInPicture.configure(with: uiView.playerLayer)
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PlayerPictureInPictureController: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isPossible = false

    private var controller: AVPictureInPictureController?
    private var observedLayer: AVPlayerLayer?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func configure(with playerLayer: AVPlayerLayer) {
        guard isSupported else { return }
        guard observedLayer !== playerLayer else {
            refreshPossibleState()
            return
        }

        observedLayer = playerLayer
        controller = AVPictureInPictureController(
            contentSource: AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
        )
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        refreshPossibleState()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
        refreshPossibleState()
    }

    func prepareForDismissal() {
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        isActive = false
    }

    /// `configure` 在 `updateUIView` 里调用。值没变也赋值会在视图更新中发布变化，引发反复重绘。
    private func refreshPossibleState() {
        let possible = controller?.isPictureInPicturePossible == true
        let active = controller?.isPictureInPictureActive == true
        if isPossible != possible {
            isPossible = possible
        }
        if isActive != active {
            isActive = active
        }
    }
}

extension PlayerPictureInPictureController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        refreshPossibleState()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        VanmoLogger.player.error("[PiP] Failed to start: \(error.localizedDescription)")
        refreshPossibleState()
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        refreshPossibleState()
    }
}

// MARK: - Quality Hold Frame

/// Lays out like the video layers: full-screen bounds, centered, same gravity.
private struct QualityHoldFrame: View {
    let image: UIImage
    let scaleMode: VideoScaleMode

    var body: some View {
        GeometryReader { proxy in
            frameImage
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }

    @ViewBuilder
    private var frameImage: some View {
        switch scaleMode {
        case .fit:
            Image(uiImage: image).resizable().scaledToFit()
        case .fill:
            Image(uiImage: image).resizable().scaledToFill()
        case .stretch:
            Image(uiImage: image).resizable()
        }
    }
}

// MARK: - KSPlayer Video Layer

struct KSPlayerVideoLayer: UIViewRepresentable {
    let videoView: UIView
    let scaleMode: VideoScaleMode

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: container.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        videoView.contentMode = scaleMode.uiViewContentMode
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if videoView.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            videoView.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(videoView)
            NSLayoutConstraint.activate([
                videoView.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                videoView.topAnchor.constraint(equalTo: uiView.topAnchor),
                videoView.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
            ])
        }
        videoView.contentMode = scaleMode.uiViewContentMode
    }
}

private extension VideoScaleMode {
    var avLayerVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fit:
            return .resizeAspect
        case .fill:
            return .resizeAspectFill
        case .stretch:
            return .resize
        }
    }
}

// MARK: - Episode Selector View

struct EpisodeSelectorView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.episodeGroups.count > 1 {
                    seasonPicker
                }

                List {
                    ForEach(viewModel.selectedSeasonEpisodes) { episode in
                        Button {
                            Task {
                                await viewModel.playEpisode(episode)
                                dismiss()
                            }
                        } label: {
                            episodeRow(episode)
                        }
                        .tint(.primary)
                    }
                }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
        }
        .padding(.top, 12)
        .background(CatDesign.bgObsidian)
        .navigationTitle(L10n.tr("选集"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.tr("完成")) { dismiss() }
                    .foregroundStyle(CatDesign.accentAmber)
            }
        }
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.episodeGroups) { group in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectedEpisodeSeason = group.seasonNumber
                        }
                    } label: {
                        Text(LocalizedFormat.seasonLabel(group.seasonNumber))
                            .font(.subheadline)
                            .fontWeight(isSelectedSeason(group.seasonNumber) ? .semibold : .regular)
                            .foregroundStyle(isSelectedSeason(group.seasonNumber) ? Color.vanmoPrimary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelectedSeason(group.seasonNumber)
                                    ? Color.vanmoPrimary.opacity(0.16)
                                    : Color.vanmoSurface,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
    }

    private func episodeRow(_ episode: PlayerEpisode) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(LocalizedFormat.compactEpisodeCode(episode.episodeNumber))
                    .font(.caption)
                    .fontWeight(.bold)
                Text(LocalizedFormat.compactSeasonCode(episode.seasonNumber))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isCurrentEpisode(episode) ? Color.vanmoPrimary : .primary)
            .frame(width: 48, height: 48)
            .background(
                (isCurrentEpisode(episode) ? Color.vanmoPrimary.opacity(0.14) : Color.vanmoSurface),
                in: RoundedRectangle(cornerRadius: 12)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(episode.episodeCode)
                    if episode.duration > 0 {
                        Text(episode.duration.shortDuration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isCurrentEpisode(episode) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(Color.vanmoPrimary)
            }
        }
        .contentShape(Rectangle())
    }

    private func isSelectedSeason(_ season: Int) -> Bool {
        (viewModel.selectedEpisodeSeason ?? viewModel.episodeGroups.first?.seasonNumber) == season
    }

    private func isCurrentEpisode(_ episode: PlayerEpisode) -> Bool {
        viewModel.currentEpisodeID == episode.id
    }
}

// MARK: - Chapter List View

struct ChapterListView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.chapters.isEmpty {
                    Text(L10n.tr("暂无章节"))
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.chapters) { chapter in
                    Button {
                        viewModel.seekToChapter(chapter)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(chapter.displayTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isCurrentChapter(chapter) {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.vanmoPrimary)
                            }
                        }
                    }
                    .tint(.primary)
                }

                Button {
                    viewModel.markIntroEnd()
                    dismiss()
                } label: {
                    Text(L10n.tr("将当前时间设为片头结束"))
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
            .navigationTitle(L10n.tr("章节与片头"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("完成")) { dismiss() }
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
        }
    }

    private func isCurrentChapter(_ chapter: Chapter) -> Bool {
        let current = viewModel.currentTime
        return current >= chapter.startTime.seconds && current < chapter.endTime.seconds
    }
}

private struct ScreenEdgeLoadingLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : Self.phase(since: startDate, at: timeline.date)
            EdgeCometStroke(phase: phase, cornerRadius: Self.cornerRadius)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func phase(since start: Date, at date: Date) -> CGFloat {
        let period: TimeInterval = 2
        return CGFloat(date.timeIntervalSince(start).truncatingRemainder(dividingBy: period) / period)
    }

    private static var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 18 : 55
    }
}

private struct EdgeCometStroke: View {
    var phase: CGFloat
    var cornerRadius: CGFloat

    /// Shorter than the first bezel dash, fully inside the screen.
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
