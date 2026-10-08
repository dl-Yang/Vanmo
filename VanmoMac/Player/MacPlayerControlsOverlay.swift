import AppKit
import SwiftUI
import VanmoCore

struct MacPlayerControlsOverlay: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    let title: String
    let showsLoadingChrome: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .macPlayerGlassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("关闭"))

                    HStack(spacing: 24) {
                        rateMenu
                        scaleMenu
                        Button(action: viewModel.toggleFullScreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .macPlayerGlassCapsule()
                }

                Spacer(minLength: 12)

                Text(title)
                    .font(MacDesignTokens.Typography.playerTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

                Spacer(minLength: 12)

                volumePill
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            Spacer()

            transportControls

            Spacer()

            HStack {
                if viewModel.canSelectEpisode {
                    Button(L10n.tr("选集")) {
                        viewModel.showEpisodeSelector = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .macPlayerGlassCapsule()
                }
                Spacer()
                HStack(spacing: 24) {
                    controlButton("text.bubble") { viewModel.showSubtitleSelector = true }
                    controlButton("waveform") { viewModel.showAudioSelector = true }
                    controlButton("arrow.triangle.2.circlepath") { viewModel.cycleScaleMode() }
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
                .macPlayerGlassCapsule()
            }
            .padding(.horizontal, 32)

            progressSlider
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
    }

    private var rateMenu: some View {
        Menu {
            ForEach(PlayerConfig.availableRates, id: \.self) { rate in
                Button {
                    viewModel.setRate(rate)
                } label: {
                    HStack {
                        Text("\(rate, specifier: "%.2g")x")
                        if viewModel.config.playbackRate == rate {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(viewModel.config.playbackRate, specifier: "%.2g")x")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 22, minHeight: 22)
        }
        .menuStyle(.borderlessButton)
    }

    private var scaleMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: viewModel.config.scaleMode.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
    }

    private var progressSlider: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let played = viewModel.scrubPreviewTime.map { duration in
                viewModel.duration > 0 ? duration / viewModel.duration : 0
            } ?? viewModel.progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: max(0, width * (viewModel.cacheEnd - viewModel.cacheStart)))
                    .offset(x: width * viewModel.cacheStart)
                Capsule()
                    .fill(.white)
                    .frame(width: width * played)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.updateScrub(to: value.location.x / width)
                    }
                    .onEnded { value in
                        viewModel.commitScrub(to: value.location.x / width)
                    }
            )
            .macBlocksWindowDrag()
            .overlay(alignment: .top) {
                if let previewTime = viewModel.scrubPreviewTime {
                    scrubPreviewCard(time: previewTime)
                        .offset(y: -132)
                }
            }
        }
        .frame(height: 20)
    }

    private func scrubPreviewCard(time: TimeInterval) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                if let image = viewModel.scrubPreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 156, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(MacFormatters.playerTimestamp(time))
                .font(MacDesignTokens.Typography.playerTime)
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    private var volumePill: some View {
        HStack(spacing: 16) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, proxy.size.width * viewModel.volume))
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.setVolume(value.location.x / max(proxy.size.width, 1))
                        }
                )
                .macBlocksWindowDrag()
            }
            .frame(width: 114, height: 48)
            Image(systemName: viewModel.volume > 0.01 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 20)
        .frame(width: 192, height: 48)
        .macPlayerGlassCapsule()
    }

    private var transportControls: some View {
        HStack(spacing: 64) {
            skipButton(seconds: -10)
            Button(action: viewModel.togglePlayPause) {
                Group {
                    if showsLoadingChrome {
                        MacPlayerLoadingArc()
                    } else {
                        Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 96, height: 96)
                .macPlayerGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsLoadingChrome
                    ? L10n.tr("正在加载")
                    : (viewModel.playbackState == .playing ? L10n.tr("暂停") : L10n.tr("播放"))
            )
            skipButton(seconds: 10)
        }
    }

    private func skipButton(seconds: TimeInterval) -> some View {
        Button {
            viewModel.skip(by: seconds)
        } label: {
            Image(systemName: seconds < 0 ? "gobackward.10" : "goforward.10")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .macPlayerGlassCircle()
        }
        .buttonStyle(.plain)
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func macPlayerGlassCircle() -> some View {
        if #available(macOS 26.0, *) {
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
    func macPlayerGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
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

private extension View {
    func macBlocksWindowDrag() -> some View {
        modifier(MacWindowDragBlocker())
    }
}

/// 播放器窗口开启了 `isMovableByWindowBackground`。窗口是否跟着拖动在按下鼠标时决定，
/// 所以指针停在拖动控件上时先关掉它，否则拖进度条会同时拖动窗口。
private struct MacWindowDragBlocker: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(MacWindowDragBlockerView(blocksDrag: isHovering))
            .onHover { isHovering = $0 }
    }
}

/// 只通过 NSView 自己的弱引用 `window` 改窗口，避免 SwiftUI 状态反过来持有窗口。
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

    /// 进度条和音量条各有一个实例，界面刷新会反复写入 `blocksDrag`。只在值变化时改窗口，
    /// 否则没被悬停的那个会把刚关掉的窗口拖动重新打开。
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
                .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(reduceMotion ? -90 : turns * 360 - 90))
        }
        .accessibilityLabel(L10n.tr("正在加载"))
    }
}
