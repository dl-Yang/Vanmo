import SwiftUI

struct SecondFloorItemView: View {
    let item: MediaItem
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            posterImage

            VStack(spacing: 4) {
                Text(item.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let year = item.year {
                    Text("\(year)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if item.playbackProgress > 0 {
                progressSection
            }

            playButton
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Poster

    private var posterImage: some View {
        AsyncImage(url: item.posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fit)
            default:
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: item.mediaType.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .frame(maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            ProgressView(value: item.playbackProgress)
                .tint(.white)

            HStack {
                Text(item.lastPlaybackPosition.shortDuration)
                Spacer()
                Text(item.duration.shortDuration)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Play Button

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(item.playbackProgress > 0 ? "继续播放" : "播放")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.2))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.9).ignoresSafeArea()
        SecondFloorItemView(
            item: MediaItem(
                title: "Inception",
                fileURL: URL(fileURLWithPath: "/test.mkv"),
                mediaType: .movie,
                fileSize: 4_500_000_000,
                duration: 8880
            ),
            onPlay: {}
        )
    }
    .preferredColorScheme(.dark)
}
