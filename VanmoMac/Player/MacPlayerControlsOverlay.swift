import AppKit
import SwiftUI
import VanmoCore

struct MacPlayerControlsOverlay: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    let item: MediaItem?
    let title: String
    let showsLoadingChrome: Bool
    @Binding var activeDrawerTab: MacPlayerDrawerTab?

    @State private var isHoveringTimeline = false
    @State private var isDraggingTimeline = false

    var body: some View {
        ZStack {
            if activeDrawerTab != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activeDrawerTab = nil
                        }
                    }
            }

            VStack(spacing: 0) {
                topFloatingHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                Spacer()

                bottomCinemaDeckContainer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }

            if activeDrawerTab != nil {
                VStack(alignment: .trailing, spacing: 0) {
                    MacPlayerTrackDrawer(viewModel: viewModel, activeTab: $activeDrawerTab)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .padding(.top, 68)
                        .padding(.trailing, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    // MARK: - Top Floating Glass Header

    private var topFloatingHeader: some View {
        HStack(spacing: 12) {
            // 左侧为交通灯留白
            Color.clear
                .frame(width: 60, height: 12)

            titleAndSpecPill

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if viewModel.canSelectEpisode {
                    headerDrawerPill(
                        title: L10n.tr("选集"),
                        isActive: activeDrawerTab == .episodes
                    ) {
                        toggleDrawer(.episodes)
                    }
                }

                headerDrawerPill(
                    title: L10n.tr("音频 / 字幕"),
                    isActive: activeDrawerTab == .audio || activeDrawerTab == .subtitles
                ) {
                    toggleDrawer(.subtitles)
                }
            }
        }
    }

    private var titleAndSpecPill: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(MacDesignTokens.Typography.playerTitle)
                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                .lineLimit(1)

            if let episodeTag = currentEpisodeSubtitle {
                Text(episodeTag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacDesignTokens.Cinema.amber)
                    .lineLimit(1)
            }

            if let spec = qualitySpecLabel {
                Text(spec)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(MacDesignTokens.Cinema.surfacePill, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.75)
                    }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.9)
        }
    }

    private func headerDrawerPill(
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    MacPawDotIndicator(size: 10, useCinemaGlow: true)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? MacDesignTokens.Cinema.amber : MacDesignTokens.Cinema.textIvory)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                isActive ? MacDesignTokens.Cinema.amberTint : MacDesignTokens.Cinema.panelGlass,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(isActive ? MacDesignTokens.Cinema.strokeAmber : MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.9)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleDrawer(_ tab: MacPlayerDrawerTab) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if activeDrawerTab == tab || (tab == .subtitles && (activeDrawerTab == .audio || activeDrawerTab == .subtitles)) {
                activeDrawerTab = nil
            } else {
                activeDrawerTab = tab
            }
        }
    }

    // MARK: - Bottom Liquid Glass Control Deck

    private var bottomCinemaDeckContainer: some View {
        VStack(spacing: 12) {
            scrubberTimeline

            HStack {
                leftTimeCluster
                Spacer(minLength: 12)
                centerTransportCluster
                Spacer(minLength: 12)
                rightUtilityCluster
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: MacDesignTokens.Layout.playerControlPanelWidth)
        .frame(height: MacDesignTokens.Layout.playerControlPanelHeight)
        .background(
            MacDesignTokens.Cinema.panelGlass,
            in: RoundedRectangle(cornerRadius: MacDesignTokens.Layout.playerControlPanelRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Layout.playerControlPanelRadius, style: .continuous)
                .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.7), radius: 22, y: 10)
    }

    private var scrubberTimeline: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let playedFraction: Double = {
                if let previewTime = viewModel.scrubPreviewTime, viewModel.duration > 0 {
                    return min(max(previewTime / viewModel.duration, 0), 1)
                }
                return min(max(viewModel.progress, 0), 1)
            }()
            let thumbX = width * playedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MacDesignTokens.Cinema.track)
                    .frame(height: 3.5)

                Capsule()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: max(0, width * max(0, viewModel.cacheEnd - viewModel.cacheStart)), height: 3.5)
                    .offset(x: width * viewModel.cacheStart)

                Capsule()
                    .fill(MacDesignTokens.Cinema.amber)
                    .frame(width: max(0, thumbX), height: 3.5)

                MacPawDotIndicator(size: 10, useCinemaGlow: true)
                    .offset(x: min(max(thumbX - 5, 0), max(0, width - 10)))
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard viewModel.duration > 0 else { return }
                switch phase {
                case .active(let location):
                    isHoveringTimeline = true
                    if !isDraggingTimeline {
                        viewModel.updateScrub(to: location.x / width)
                    }
                case .ended:
                    isHoveringTimeline = false
                    if !isDraggingTimeline {
                        viewModel.clearScrubPreview()
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingTimeline = true
                        viewModel.updateScrub(to: value.location.x / width)
                    }
                    .onEnded { value in
                        isDraggingTimeline = false
                        viewModel.commitScrub(to: value.location.x / width)
                    }
            )
            .macBlocksWindowDrag()
            .overlay(alignment: .topLeading) {
                if let previewTime = viewModel.scrubPreviewTime, (isHoveringTimeline || isDraggingTimeline) {
                    let cardWidth: CGFloat = 164
                    let clampedX = min(max(thumbX - cardWidth / 2, 0), max(0, width - cardWidth))
                    scrubPreviewCard(time: previewTime)
                        .offset(x: clampedX, y: -124)
                }
            }
        }
        .frame(height: 14)
    }

    private func scrubPreviewCard(time: TimeInterval) -> some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacDesignTokens.Cinema.panelGlass)

                if let image = viewModel.scrubPreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }

                LinearGradient(
                    colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 42)

                Text(MacFormatters.playerTimestamp(time))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(MacDesignTokens.Cinema.amber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2.5)
                    .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
                    .padding(.bottom, 8)
            }
            .frame(width: 164, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 1.15)
            }
            .shadow(color: .black.opacity(0.75), radius: 18, y: 8)
            .padding(.top, 22)

            Image("MacScrubPreviewCat")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 30)
                .offset(y: -4)
        }
        .allowsHitTesting(false)
    }

    private var leftTimeCluster: some View {
        Text("\(MacFormatters.playerTimestamp(viewModel.currentTime))  /  \(MacFormatters.playerTimestamp(viewModel.duration))")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(MacDesignTokens.Cinema.textMuted)
    }

    private var centerTransportCluster: some View {
        HStack(spacing: 20) {
            Button {
                viewModel.skip(by: -15)
            } label: {
                Image("MacPlayerSkipBack15")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("后退 15 秒"))

            Button(action: viewModel.togglePlayPause) {
                Group {
                    if showsLoadingChrome {
                        MacPlayerLoadingArc()
                    } else if viewModel.playbackState == .playing {
                        Image("MacPlayerPause")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                    }
                }
                .frame(width: 38, height: 38)
                .background(MacDesignTokens.Cinema.surfacePill, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsLoadingChrome
                    ? L10n.tr("正在加载")
                    : (viewModel.playbackState == .playing ? L10n.tr("暂停") : L10n.tr("播放"))
            )

            Button {
                viewModel.skip(by: 15)
            } label: {
                Image("MacPlayerSkipFwd15")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("前进 15 秒"))
        }
    }

    private var rightUtilityCluster: some View {
        HStack(spacing: 14) {
            rateAndScaleMenu

            volumeSliderGroup

            Button(action: viewModel.toggleFullScreen) {
                Image("MacPlayerFullscreen")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("切换全屏"))
        }
    }

    private var rateAndScaleMenu: some View {
        Menu {
            Section(L10n.tr("倍速")) {
                ForEach(PlayerConfig.availableRates, id: \.self) { rate in
                    Button {
                        viewModel.setRate(rate)
                    } label: {
                        HStack {
                            Text(MacFormatters.playbackRate(rate))
                            if viewModel.config.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section(L10n.tr("画面比例")) {
                ForEach(VideoScaleMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.setScaleMode(mode)
                    } label: {
                        HStack {
                            Label(mode.displayName, systemImage: mode.icon)
                            if viewModel.config.scaleMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Text(MacFormatters.playbackRate(viewModel.config.playbackRate))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(MacDesignTokens.Cinema.surfacePill, in: Capsule())
        .fixedSize()
    }

    private var volumeSliderGroup: some View {
        HStack(spacing: 7) {
            Button {
                viewModel.setVolume(viewModel.volume > 0.01 ? 0 : 0.7)
            } label: {
                Group {
                    if viewModel.volume > 0.01 {
                        Image("MacPlayerVolume")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let fillWidth = max(0, width * min(max(viewModel.volume, 0), 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MacDesignTokens.Cinema.track)
                        .frame(height: 3)

                    Capsule()
                        .fill(MacDesignTokens.Cinema.amber)
                        .frame(width: fillWidth, height: 3)

                    Circle()
                        .fill(MacDesignTokens.Cinema.textIvory)
                        .frame(width: 8, height: 8)
                        .offset(x: min(max(fillWidth - 4, 0), max(0, width - 8)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.setVolume(value.location.x / width)
                        }
                )
                .macBlocksWindowDrag()
            }
            .frame(width: 72, height: 18)
        }
    }

    // MARK: - Metadata Helpers

    private var currentEpisodeSubtitle: String? {
        if let episodeId = viewModel.currentEpisodeID {
            for group in viewModel.episodeGroups {
                if let ep = group.episodes.first(where: { $0.id == episodeId }) {
                    return "\(ep.episodeCode) · \(ep.displayTitle)"
                }
            }
        }
        if let season = item?.seasonNumber, let ep = item?.episodeNumber {
            let code = String(format: "S%02d E%02d", season, ep)
            if let epTitle = item?.episodeTitle, !epTitle.isEmpty {
                return "\(code) · \(epTitle)"
            }
            return code
        }
        return nil
    }

    private var qualitySpecLabel: String? {
        if let dr = item?.dynamicRange?.uppercased(), !dr.isEmpty {
            if let h = item?.videoHeight, h >= 2000 {
                return "4K \(dr)"
            }
            return dr
        }
        if let h = item?.videoHeight {
            if h >= 2000 { return "4K" }
            if h >= 1000 { return "1080p" }
        }
        return nil
    }
}

private extension View {
    func macBlocksWindowDrag() -> some View {
        modifier(MacWindowDragBlocker())
    }
}

private struct MacWindowDragBlocker: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(MacWindowDragBlockerView(blocksDrag: isHovering))
            .onHover { isHovering = $0 }
    }
}

private struct MacWindowDragBlockerView: NSViewRepresentable {
    let blocksDrag: Bool

    func makeNSView(context: Context) -> BlockerView {
        let view = BlockerView()
        view.blocksDrag = blocksDrag
        return view
    }

    func updateNSView(_ view: BlockerView, context: Context) {
        view.blocksDrag = blocksDrag
    }

    static func dismantleNSView(_ view: BlockerView, coordinator: ()) {
        view.blocksDrag = false
    }

    final class BlockerView: NSView {
        var blocksDrag = false {
            didSet {
                guard oldValue != blocksDrag else { return }
                window?.isMovableByWindowBackground = !blocksDrag
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if blocksDrag, newWindow !== window {
                window?.isMovableByWindowBackground = true
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if blocksDrag {
                window?.isMovableByWindowBackground = false
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct MacPlayerLoadingArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0.08, to: 0.38)
                .stroke(MacDesignTokens.Cinema.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(reduceMotion ? -90 : turns * 360 - 90))
        }
        .accessibilityLabel(L10n.tr("正在加载"))
    }
}
