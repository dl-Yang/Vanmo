import SwiftUI

struct PosterCard: View {
    let title: String
    let posterURL: URL?
    let subtitle: String?
    let rating: Double?
    let progress: Double?
    let originCountry: String?

    init(
        title: String,
        posterURL: URL? = nil,
        subtitle: String? = nil,
        rating: Double? = nil,
        progress: Double? = nil,
        originCountry: String? = nil
    ) {
        self.title = title
        self.posterURL = posterURL
        self.subtitle = subtitle
        self.rating = rating
        self.progress = progress
        self.originCountry = originCountry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            posterImage
            titleOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private var posterImage: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                case .failure:
                    placeholderView
                case .empty:
                    placeholderView
                        .overlay(ProgressView().tint(.white))
                @unknown default:
                    placeholderView
                }
            }
            .overlay(alignment: .topTrailing) {
                if let rating, rating > 0 {
                    RatingBadge(rating)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let originCountry, !originCountry.isEmpty {
                    Text(originCountry)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }

            if let progress, progress > 0, progress < 1.0 {
                progressBar(progress)
            }
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.vanmoSurface)
            .aspectRatio(2/3, contentMode: .fill)
            .overlay {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 3)
                    Rectangle()
                        .fill(Color.vanmoPrimary)
                        .frame(width: geometry.size.width * value, height: 3)
                }
            }
        }
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    HStack(spacing: 16) {
        PosterCard(
            title: "Inception",
            subtitle: "2010",
            rating: 8.4,
            progress: 0.6,
            originCountry: "美国"
        )
        .frame(width: 130)

        PosterCard(
            title: "The Dark Knight",
            subtitle: "2008",
            rating: 9.0
        )
        .frame(width: 130)
    }
    .padding()
    .preferredColorScheme(.dark)
}
