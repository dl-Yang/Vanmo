import SwiftUI
import Kingfisher

struct MediaListRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            poster
            info
            Spacer()
            meta
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.vanmoBackground)
    }

    private var poster: some View {
        KFImage(item.posterURL)
            .placeholder {
                Rectangle()
                    .fill(Color.vanmoSurface)
                    .overlay {
                        Image(systemName: item.mediaType.icon)
                            .foregroundStyle(.tertiary)
                    }
            }
            .fade(duration: 0.25)
            .resizable()
            .aspectRatio(contentMode: .fill)
        .frame(width: 60, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let year = item.year {
                    Text("\(year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.mediaType.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.vanmoSurface)
                    .clipShape(Capsule())
            }

            if item.duration > 0 {
                Text(item.duration.shortDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.playbackProgress > 0 {
                ProgressView(value: item.playbackProgress)
                    .tint(.vanmoPrimary)
                    .scaleEffect(y: 0.6)
            }
        }
    }

    private var meta: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let rating = item.rating {
                RatingBadge(rating)
            }

            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(item.fileSize.formattedFileSize)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    MediaListRow(item: MediaItem(
        title: "Inception",
        fileURL: URL(fileURLWithPath: "/test.mkv"),
        mediaType: .movie,
        fileSize: 4_500_000_000,
        duration: 8880
    ))
    .preferredColorScheme(.dark)
}
