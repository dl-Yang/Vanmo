import SwiftUI
import AVFoundation
import MetalKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    @State private var showSpeedPicker = false
    @State private var showScaleModePicker = false

    init(item: MediaItem) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            gestureLayer
                .allowsHitTesting(!viewModel.controlsVisible)

            if viewModel.controlsVisible {
                controlsOverlay
            }

            feedbackOverlays

            if showSpeedPicker || showScaleModePicker {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSpeedPicker = false
                            showScaleModePicker = false
                        }
                    }
            }

            if showSpeedPicker {
                speedPickerPanel
            }

            if showScaleModePicker {
                scalePickerPanel
            }
        }
        .statusBarHidden(!viewModel.controlsVisible)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $viewModel.showTrackSelector) {
            TrackSelectorView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showChapterList) {
            ChapterListView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: viewModel.controlsVisible) { _, visible in
            if !visible {
                showSpeedPicker = false
                showScaleModePicker = false
            }
        }
    }

    // MARK: - Video Layer

    @ViewBuilder
    private var videoLayer: some View {
        if let player = viewModel.avPlayer {
            AVPlayerVideoLayer(player: player, scaleMode: viewModel.config.scaleMode)
                .ignoresSafeArea()
        } else if let renderer = viewModel.ffmpegRenderView {
            MetalVideoLayer(renderer: renderer, scaleMode: viewModel.config.scaleMode)
                .ignoresSafeArea()
        }
    }

    // MARK: - Gesture Layer

    private var gestureLayer: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let delta = -Float(value.translation.height / geometry.size.height)
                                viewModel.handleBrightnessChange(delta * 0.01)
                            }
                    )

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.togglePlayPause()
                    }
                    .onTapGesture {
                        viewModel.toggleControls()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                let delta = value.translation.width / geometry.size.width * 120
                                viewModel.handleSeekGesture(Double(delta))
                            }
                            .onEnded { _ in
                                viewModel.commitSeekGesture()
                            }
                    )
                    .gesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onChanged { isPressing in
                                viewModel.handleLongPress(isActive: isPressing)
                            }
                    )

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let delta = -Float(value.translation.height / geometry.size.height)
                                viewModel.handleVolumeChange(delta * 0.01)
                            }
                    )
            }
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.toggleControls()
                }

            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding()
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(8)
            }

            Spacer()

            Text(viewModel.engine.state.isActive ? "" : "")
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 16) {
                if !viewModel.chapters.isEmpty {
                    Button {
                        viewModel.showChapterList = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }

                Button {
                    viewModel.showTrackSelector = true
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSpeedPicker.toggle()
                        showScaleModePicker = false
                    }
                } label: {
                    Text("\(viewModel.config.playbackRate, specifier: "%.1f")x")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScaleModePicker.toggle()
                        showSpeedPicker = false
                    }
                } label: {
                    Image(systemName: viewModel.config.scaleMode.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            Button { viewModel.skipBackward() } label: {
                Image(systemName: "gobackward.10")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            Button { viewModel.togglePlayPause() } label: {
                Group {
                    switch viewModel.playbackState {
                    case .loading, .buffering:
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    case .playing:
                        Image(systemName: "pause.fill")
                            .font(.system(size: 44))
                    default:
                        Image(systemName: "play.fill")
                            .font(.system(size: 44))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
            }

            Button { viewModel.skipForward() } label: {
                Image(systemName: "goforward.10")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            PlayerProgressBar(
                progress: viewModel.progress,
                bufferProgress: viewModel.bufferProgress,
                isSeeking: $viewModel.isSeeking,
                onSeek: { fraction in
                    viewModel.seek(to: fraction * viewModel.duration)
                }
            )

            HStack {
                Text(viewModel.currentTime.formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text("-\((viewModel.duration - viewModel.currentTime).formattedDuration)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
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
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.brightnessOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.volumeOverlay)
        .animation(.easeInOut(duration: 0.2), value: viewModel.seekOverlay)
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
        .padding(.trailing, 16)
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
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
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

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = scaleMode.avLayerVideoGravity
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

// MARK: - Metal Video Layer (FFmpeg Engine)

struct MetalVideoLayer: UIViewRepresentable {
    let renderer: VideoRenderer
    let scaleMode: VideoScaleMode

    func makeUIView(context: Context) -> MTKView {
        renderer.setScaleMode(scaleMode)
        return renderer.metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        renderer.setScaleMode(scaleMode)
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

// MARK: - Chapter List View

struct ChapterListView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle("章节")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func isCurrentChapter(_ chapter: Chapter) -> Bool {
        let current = viewModel.currentTime
        return current >= chapter.startTime.seconds && current < chapter.endTime.seconds
    }
}
