import SwiftUI
import VanmoCore

struct MacPlayerControlsOverlay: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 20) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(MacDesignTokens.Typography.playerTitle)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 3)

                Spacer()

                if viewModel.canSelectEpisode {
                    Button(L10n.tr("选集")) {
                        viewModel.showEpisodeSelector = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))
                }

                rateMenu
                scaleMenu
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)

            Spacer()

            controlPanel
                .padding(.bottom, 40)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }

    private var controlPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(MacFormatters.playerTimestamp(viewModel.currentTime))
                    .font(MacDesignTokens.Typography.playerTime)
                    .foregroundStyle(.white.opacity(0.8))

                progressSlider

                Text(MacFormatters.playerRemainingTimestamp(-viewModel.remainingTime))
                    .font(MacDesignTokens.Typography.playerTime)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.top, 20)

            HStack {
                volumeControls
                Spacer()
                transportControls
                Spacer()
                trailingControls
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: MacDesignTokens.Layout.playerControlPanelWidth)
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.playerControlPanelRadius))
        .shadow(color: .black.opacity(0.25), radius: 25, y: 12)
    }

    private var progressSlider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: proxy.size.width * viewModel.bufferProgress)
                Capsule()
                    .fill(MacDesignTokens.accentBlue)
                    .frame(width: proxy.size.width * viewModel.progress)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: max((proxy.size.width * viewModel.progress) - 7, 0))
            }
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = value.location.x / max(proxy.size.width, 1)
                        viewModel.seek(to: progress)
                    }
            )
        }
        .frame(height: 14)
    }

    private var volumeControls: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * viewModel.volume)
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .offset(x: max((proxy.size.width * viewModel.volume) - 5, 0))
                }
                .frame(height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.setVolume(value.location.x / max(proxy.size.width, 1))
                        }
                )
            }
            .frame(width: 80, height: 14)
        }
        .frame(width: 280, alignment: .leading)
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            skipButton(seconds: -15)
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            skipButton(seconds: 15)
        }
        .frame(width: 280)
    }

    private var trailingControls: some View {
        HStack(spacing: 20) {
            controlButton("captions.bubble") {
                viewModel.showTrackSelector = true
            }
            controlButton("mic") {
                viewModel.showTrackSelector = true
            }
            controlButton("arrow.up.left.and.arrow.down.right") {
                viewModel.toggleFullScreen()
            }
        }
        .frame(width: 280, alignment: .trailing)
    }

    private func skipButton(seconds: TimeInterval) -> some View {
        Button {
            viewModel.skip(by: seconds)
        } label: {
            ZStack {
                Image(systemName: seconds < 0 ? "gobackward" : "goforward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("15")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .offset(y: 1)
            }
            .frame(width: 28, height: 28)
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
