import SwiftUI
import Kingfisher

struct FavoritesStackedCard: View {
    let posterURLs: [URL?]
    let totalCount: Int
    let movieCount: Int
    let tvShowCount: Int

    var body: some View {
        HStack(spacing: 20) {
            posterStack
                .frame(width: 132, height: 154)

            VStack(alignment: .leading, spacing: 8) {
                Text("我的收藏")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text("最近收藏的影片都在这里")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                countBadge("\(movieCount) 部电影", icon: "film")
                countBadge("\(tvShowCount) 部剧集", icon: "tv")
//                HStack(spacing: 8) {
//                    countBadge("\(movieCount) 部电影", icon: "film")
////                    countBadge("\(tvShowCount) 部剧集", icon: "tv")
//                }

                Text("共 \(totalCount) 部")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("我的收藏，共 \(totalCount) 部")
    }

    private var posterStack: some View {
        ZStack(alignment: .center) {
            ForEach(Array(displayPosters.enumerated()).reversed(), id: \.offset) { index, url in
                StackedPoster(url: url)
                    .frame(width: 82, height: 123)
                    .scaleEffect(1 - CGFloat(index) * 0.06)
                    .rotationEffect(.degrees(Double(index) * 3))
                    .offset(x: CGFloat(index) * 24, y: CGFloat(index) * 2)
                    .shadow(
                        color: .black.opacity(0.26 - Double(index) * 0.04),
                        radius: 12,
                        x: 0,
                        y: 8
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var displayPosters: [URL?] {
        let posters = Array(posterURLs.prefix(4))
        return posters.isEmpty ? [nil, nil, nil] : posters
    }

    private func countBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.vanmoBackground)
        .clipShape(Capsule())
    }
}

private struct StackedPoster: View {
    let url: URL?

    var body: some View {
        KFImage(url)
            .placeholder {
                placeholder
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(width: 82, height: 123)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .clipped()
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color.vanmoPrimary.opacity(0.35),
                        Color.vanmoSurface,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}

#Preview {
    FavoritesStackedCard(
        posterURLs: [nil, nil, nil],
        totalCount: 18,
        movieCount: 12,
        tvShowCount: 6
    )
    .padding()
    .background(Color.vanmoBackground)
    .preferredColorScheme(.dark)
}
