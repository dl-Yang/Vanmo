import SwiftUI
import AVFoundation

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel

    init(item: MediaItem) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            gestureLayer

            if viewModel.controlsVisible {
                controlsOverlay
            }

            feedbackOverlays
        }
        .statusBarHidden(!viewModel.controlsVisible)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $viewModel.showTrackSelector) {
            TrackSelectorView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Video Layer

    private var videoLayer: some View {
        VideoPlayerLayer(player: viewModel.engine.avPlayer)
            .ignoresSafeArea()
    }

    // MARK: - Gesture Layer

    private var gestureLayer: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left side - brightness
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

                // Center - seek
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleControls()
                    }
                    .onTapGesture(count: 2) {
                        viewModel.togglePlayPause()
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

                // Right side - volume
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
                Button {
                    viewModel.showTrackSelector = true
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Menu {
                    ForEach(PlayerConfig.availableRates, id: \.self) { rate in
                        Button {
                            viewModel.setRate(rate)
                        } label: {
                            HStack {
                                Text("\(rate, specifier: "%.1f")x")
                                if viewModel.config.playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
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

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
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
