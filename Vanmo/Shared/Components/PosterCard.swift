import SwiftUI
import Kingfisher

struct PosterCard: View {
    let title: String
    let posterURL: URL?
    let subtitle: String?
    let rating: Double?
    let progress: Double?
    let originCountry: String?
    var showShadow: Bool

    init(
        title: String,
        posterURL: URL? = nil,
        subtitle: String? = nil,
        rating: Double? = nil,
        progress: Double? = nil,
        originCountry: String? = nil,
        showShadow: Bool = true
    ) {
        self.title = title
        self.posterURL = posterURL
        self.subtitle = subtitle
        self.rating = rating
        self.progress = progress
        self.originCountry = originCountry
        self.showShadow = showShadow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterImage

            titleBlock
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius + 6)
                .fill(Color.vanmoCinematicSurface.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius + 6)
                .strokeBorder(Color.vanmoCinematicBorder, lineWidth: 1)
        }
        .shadow(
            color: showShadow ? VanmoCinema.cardShadowColor : .clear,
            radius: showShadow ? VanmoCinema.cardShadowRadius : 0,
            x: 0,
            y: showShadow ? VanmoCinema.cardShadowYOffset : 0
        )
    }

    private var posterImage: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.clear)
                .overlay {
                    KFImage(posterURL)
                        .placeholder {
                            placeholderView
                                .overlay(ProgressView().tint(.white))
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                }
                .overlay(alignment: .topTrailing) {
                    if let rating, rating > 0 {
                        RatingBadge(rating)
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let originCountry, !originCountry.isEmpty {
                        Text(originCountry)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.54), in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                            }
                            .padding(7)
                    }
                }

            LinearGradient.cinematicPosterOverlay
                .allowsHitTesting(false)

            if let progress, progress > 0, progress < 1.0 {
                progressBar(progress)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .clipped()
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.vanmoCinematicSurfaceElevated,
                        Color.vanmoCinematicSurface,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.36))

                    Text("Vanmo")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.vanmoCinematicAccent)
                        .frame(width: geometry.size.width * value, height: 4)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.94))

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 42, alignment: .topLeading)
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
