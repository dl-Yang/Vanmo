import SwiftUI
import AVFoundation
import SwiftData

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: PlayerViewModel
    @AppStorage("subtitle.fontSize") private var subtitleFontSize: Double = 18
    @State private var showSpeedPicker = false
    @State private var showScaleModePicker = false

    init(item: MediaItem) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoLayer

            SubtitleOverlayView(
                content: viewModel.currentSubtitleContent,
                style: SubtitleStyle(fontSize: subtitleFontSize)
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

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
        .onAppear {
            AppOrientation.lockForPlayer()
        }
        .task { await viewModel.onAppear(modelContext: modelContext) }
        .onDisappear {
            viewModel.onDisappear()
            AppOrientation.restoreDefault()
        }
        .sheet(isPresented: $viewModel.showTrackSelector) {
            TrackSelectorView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showChapterList) {
            ChapterListView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showEpisodeSelector) {
            EpisodeSelectorView(viewModel: viewModel)
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
        } else if let ksView = viewModel.ksPlayerVideoView {
            KSPlayerVideoLayer(videoView: ksView, scaleMode: viewModel.config.scaleMode)
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
                if viewModel.canSelectEpisode {
                    Button {
                        viewModel.showEpisodeSelector = true
                    } label: {
                        Image(systemName: "rectangle.stack")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }

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
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
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
                        Text("第 \(group.seasonNumber) 季")
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
                Text("E\(String(format: "%02d", episode.episodeNumber))")
                    .font(.caption)
                    .fontWeight(.bold)
                Text("S\(String(format: "%02d", episode.seasonNumber))")
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
