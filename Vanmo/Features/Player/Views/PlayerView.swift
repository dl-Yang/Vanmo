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
    @State private var showSpeedPicker = false
    @State private var showScaleModePicker = false
    @State private var showQualityPicker = false
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

    private var iPhoneLandscapeHorizontalSafeArea: CGFloat {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return max(insets.left, insets.right)
    }

    private func playerSurface() -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            if let holdImage = viewModel.qualityHoldImage {
                Image(uiImage: holdImage)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if case .error(let message) = viewModel.playbackState {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .medium))
                    Text(L10n.tr("无法播放"))
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            }

            SubtitleOverlayView(
                content: viewModel.currentSubtitleContent,
                style: viewModel.subtitleStyle
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            gestureLayer
                .allowsHitTesting(!viewModel.controlsVisible)

            if showSpeedPicker || showScaleModePicker || showQualityPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSpeedPicker = false
                            showScaleModePicker = false
                            showQualityPicker = false
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

            if showSpeedPicker {
                speedPickerPanel
            }

            if showScaleModePicker {
                scalePickerPanel
            }

        }
        .overlay {
            if showsLoadingChrome {
                ScreenEdgeLoadingLight()
                    .allowsHitTesting(false)
            }
        }
        .overlayPreferenceValue(QualityButtonAnchorKey.self) { anchor in
            if showQualityPicker, let anchor {
                GeometryReader { proxy in
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .allowsHitTesting(false)
                        qualityPickerCard
                            .fixedSize()
                            .offset(x: rect.minX, y: rect.maxY + 8)
                    }
                }
                .ignoresSafeArea()
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
            case .active:
                phaseName = "active"
            case .inactive:
                phaseName = "inactive"
            case .background:
                phaseName = "background"
            @unknown default:
                phaseName = "unknown"
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
                showSpeedPicker = false
                showScaleModePicker = false
                showQualityPicker = false
            }
        }
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

            ZStack {
                VStack(spacing: 0) {
                    topBar
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if showQualityPicker || showSpeedPicker || showScaleModePicker {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showQualityPicker = false
                                    showSpeedPicker = false
                                    showScaleModePicker = false
                                }
                            } else {
                                viewModel.toggleControls()
                            }
                        }
                    bottomBar
                }
                centerControls
            }
            .safeAreaPadding(.horizontal, 16)
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var topBar: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 480
            topBarContent(
                diameter: compact ? 44 : 48,
                spacing: compact ? 8 : 20,
                volumeWidth: compact ? 112 : 192,
                sliderWidth: compact ? 48 : 114
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 48)
    }

    private func topBarContent(
        diameter: CGFloat,
        spacing: CGFloat,
        volumeWidth: CGFloat,
        sliderWidth: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            HStack(spacing: spacing) {
                Button(action: closePlayer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: diameter, height: diameter)
                        .playerGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("关闭"))

                pictureInPictureButton(diameter: diameter)
                AirPlayRouteButton()
                    .frame(width: 24, height: 24)
                    .frame(width: diameter, height: diameter)
                    .playerGlassCircle()
                    .accessibilityLabel(L10n.tr("投屏"))
                qualityButton(diameter: diameter)
            }
            .contextMenu {
                extraPlayerActions
            }

            Spacer(minLength: 8)

            volumePill(width: volumeWidth, sliderWidth: sliderWidth, height: diameter)
        }
    }

    private func qualityButton(diameter: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showQualityPicker.toggle()
                showSpeedPicker = false
                showScaleModePicker = false
            }
        } label: {
            Text(qualityShortLabel)
                .font(.system(size: diameter < 48 ? 11 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(width: diameter, height: diameter)
                .playerGlassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("画质"))
        .anchorPreference(key: QualityButtonAnchorKey.self, value: .bounds) { $0 }
    }

    private var qualityShortLabel: String {
        switch viewModel.videoQuality {
        case .p360: return "360"
        case .p480: return "480"
        case .p720: return "720"
        case .p1080: return "HD"
        case .original: return L10n.tr("原画")
        }
    }

    private func pictureInPictureButton(diameter: CGFloat) -> some View {
        Button {
            if viewModel.avPlayer != nil {
                pictureInPicture.toggle()
            } else {
                viewModel.toggleKSPictureInPicture()
            }
        } label: {
            Image(systemName: (pictureInPicture.isActive || viewModel.isPictureInPictureActive) ? "pip.exit" : "pip.enter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .playerGlassCircle()
        }
        .buttonStyle(.plain)
        .disabled(!(pictureInPicture.isSupported && viewModel.canShowPictureInPictureButton))
        .accessibilityLabel((pictureInPicture.isActive || viewModel.isPictureInPictureActive) ? L10n.tr("退出画中画") : L10n.tr("进入画中画"))
    }

    private func volumePill(width: CGFloat, sliderWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, proxy.size.width * CGFloat(viewModel.config.volume)))
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = value.location.x / max(proxy.size.width, 1)
                            viewModel.setVolume(Float(fraction))
                        }
                )
            }
            .frame(width: sliderWidth, height: height)

            Image(systemName: viewModel.config.volume > 0.01 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: height)
        .playerGlassCapsule()
    }

    @ViewBuilder
    private var extraPlayerActions: some View {
        if viewModel.canSelectEpisode {
            Button(L10n.tr("选集")) { viewModel.showEpisodeSelector = true }
        }
        Button(L10n.tr("章节与片头")) { viewModel.showChapterList = true }
        Button(L10n.tr("画质")) {
            showQualityPicker = true
            showSpeedPicker = false
            showScaleModePicker = false
        }
        Button(L10n.tr("倍速")) {
            showSpeedPicker = true
            showQualityPicker = false
            showScaleModePicker = false
        }
    }

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

    private var centerControls: some View {
        ViewThatFits(in: .horizontal) {
            centerControlsContent(play: 96, skip: 64, spacing: 64, playIcon: 34, skipIcon: 22)
            centerControlsContent(play: 72, skip: 48, spacing: 20, playIcon: 28, skipIcon: 18)
        }
    }

    private func centerControlsContent(
        play: CGFloat,
        skip: CGFloat,
        spacing: CGFloat,
        playIcon: CGFloat,
        skipIcon: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            skipGlassButton(forward: false, diameter: skip, icon: skipIcon)
            Button { viewModel.togglePlayPause() } label: {
                Group {
                    if showsLoadingChrome {
                        PlayerLoadingArc()
                    } else {
                        Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: playIcon, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: play, height: play)
                .playerGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsLoadingChrome
                    ? L10n.tr("正在加载")
                    : (viewModel.playbackState == .playing ? L10n.tr("暂停") : L10n.tr("播放"))
            )
            skipGlassButton(forward: true, diameter: skip, icon: skipIcon)
        }
    }

    private func skipGlassButton(forward: Bool, diameter: CGFloat, icon: CGFloat) -> some View {
        Button {
            if forward {
                viewModel.skipForward()
            } else {
                viewModel.skipBackward()
            }
        } label: {
            Image(systemName: forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: icon, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .playerGlassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? L10n.tr("快进") : L10n.tr("快退"))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.isLiveStream {
            HStack {
                liveBadge
                Spacer()
            }
        } else {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    if viewModel.canSkipIntro {
                        Button {
                            viewModel.skipIntro()
                        } label: {
                            Text(L10n.tr("跳过片头"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .playerGlassCapsule()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("跳过片头"))
                    }
                    Spacer()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) {
                            glassCircleButton("text.bubble", label: L10n.tr("字幕"), diameter: 48) {
                                viewModel.showSubtitleSelector = true
                            }
                            glassCircleButton("waveform", label: L10n.tr("音轨"), diameter: 48) {
                                viewModel.showAudioSelector = true
                            }
                            glassCircleButton("arrow.triangle.2.circlepath", label: L10n.tr("缩放"), diameter: 48) {
                                viewModel.cycleScaleMode()
                            }
                        }
                        HStack(spacing: 8) {
                            glassCircleButton("text.bubble", label: L10n.tr("字幕"), diameter: 44) {
                                viewModel.showSubtitleSelector = true
                            }
                            glassCircleButton("waveform", label: L10n.tr("音轨"), diameter: 44) {
                                viewModel.showAudioSelector = true
                            }
                            glassCircleButton("arrow.triangle.2.circlepath", label: L10n.tr("缩放"), diameter: 44) {
                                viewModel.cycleScaleMode()
                            }
                        }
                    }
                }

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
            }
        }
    }

    private func glassCircleButton(
        _ systemName: String,
        label: String,
        diameter: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .playerGlassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                    Text("\(isForward ? "+" : "")\(Int(seekDelta))s")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.scale.combined(with: .opacity))
            }

            if viewModel.seekPreviewActive {
                seekPreviewOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.brightnessOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.volumeOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.seekOverlay)
        .animation(.easeInOut(duration: 0.15), value: viewModel.seekPreviewActive)
    }

    private var seekPreviewOverlay: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                if let image = viewModel.seekPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: viewModel.seekPreviewForward ? "forward.fill" : "backward.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 4) {
                Text(viewModel.seekTime.formattedDuration)
                    .foregroundStyle(.white)
                Text("/")
                    .foregroundStyle(.white.opacity(0.5))
                Text(viewModel.duration.formattedDuration)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.title3)
            .fontWeight(.semibold)
            .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.scale.combined(with: .opacity))
    }

    private var rateBoostIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "forward.fill")
                .font(.subheadline)
            Text("\(PlayerConfig.maximumRate, specifier: "%.1f")x 倍速播放中")
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 44)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRateBoosting)
    }

    // MARK: - Picker Panels

    private var speedPickerPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(PlayerConfig.availableRates.enumerated()), id: \.element) { index, rate in
                Button {
                    viewModel.setRate(rate)
                    withAnimation(.easeInOut(duration: 0.2)) { showSpeedPicker = false }
                } label: {
                    HStack {
                        Text("\(rate, specifier: "%.1f")x")
                        Spacer()
                        if viewModel.config.playbackRate == rate {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                if index < PlayerConfig.availableRates.count - 1 {
                    Divider().overlay(.white.opacity(0.15))
                }
            }
        }
        .frame(width: 150)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 56)
        .padding(.trailing, 16 + iPhoneLandscapeHorizontalSafeArea)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
    }

    private var scalePickerPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(VideoScaleMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    viewModel.setScaleMode(mode)
                    withAnimation(.easeInOut(duration: 0.2)) { showScaleModePicker = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.icon)
                            .frame(width: 20)
                        Text(mode.displayName)
                        Spacer()
                        if viewModel.config.scaleMode == mode {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                if index < VideoScaleMode.allCases.count - 1 {
                    Divider().overlay(.white.opacity(0.15))
                }
            }
        }
        .frame(width: 160)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 56)
        .padding(.trailing, 16 + iPhoneLandscapeHorizontalSafeArea)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
    }

    private var qualityPickerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.availableVideoQualities.enumerated()), id: \.element) { index, quality in
                Button {
                    viewModel.setVideoQuality(quality)
                    withAnimation(.easeInOut(duration: 0.2)) { showQualityPicker = false }
                } label: {
                    HStack {
                        Text(quality.displayName)
                        Spacer()
                        if viewModel.videoQuality == quality {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < viewModel.availableVideoQualities.count - 1 {
                    Divider().overlay(.white.opacity(0.15))
                }
            }
        }
        .frame(width: 150)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
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
            ProgressView(value: value)
                .frame(width: 100)
                .tint(.white)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
            }
            .padding(.top, 12)
            .navigationTitle(L10n.tr("选集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("完成")) { dismiss() }
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
                }
            }
            .navigationTitle(L10n.tr("章节与片头"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("完成")) { dismiss() }
                }
            }
        }
    }

    private func isCurrentChapter(_ chapter: Chapter) -> Bool {
        let current = viewModel.currentTime
        return current >= chapter.startTime.seconds && current < chapter.endTime.seconds
    }
}

private extension View {
    @ViewBuilder
    func playerGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.contentShape(Circle())
                .glassEffect(.clear, in: .circle)
        } else {
            self.contentShape(Circle())
                .background {
                    Circle().fill(.ultraThinMaterial).opacity(0.22)
                }
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func playerGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.contentShape(Capsule())
                .glassEffect(.clear, in: .capsule)
        } else {
            self.contentShape(Capsule())
                .background {
                    Capsule().fill(.ultraThinMaterial).opacity(0.22)
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

private struct QualityButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct PlayerLoadingArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0.08, to: 0.38)
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(reduceMotion ? -90 : turns * 360 - 90))
        }
        .accessibilityLabel(L10n.tr("正在加载"))
    }
}

private struct ScreenEdgeLoadingLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0.12 : Self.phase(at: timeline.date)
            EdgeCometStroke(phase: phase, cornerRadius: Self.cornerRadius)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func phase(at date: Date) -> CGFloat {
        let period: TimeInterval = 2
        return CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
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
    private let coreWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let inset = coreWidth / 2 + 3
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            guard rect.width > 4, rect.height > 4 else { return }
            let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
            let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            strokeComet(context: &context, path: path, lineWidth: 7, color: Color.white.opacity(0.55), blur: 1.2)
            strokeComet(context: &context, path: path, lineWidth: coreWidth, color: .white, blur: 0)
        }
        .allowsHitTesting(false)
    }

    private func strokeComet(
        context: inout GraphicsContext,
        path: Path,
        lineWidth: CGFloat,
        color: Color,
        blur: CGFloat
    ) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        context.drawLayer { layer in
            if blur > 0 {
                layer.addFilter(.blur(radius: blur))
            }
            layer.stroke(path.trimmedPath(from: phase, to: min(phase + cometLength, 1)), with: .color(color), style: style)
            if phase + cometLength > 1 {
                layer.stroke(path.trimmedPath(from: 0, to: phase + cometLength - 1), with: .color(color), style: style)
            }
        }
    }
}
