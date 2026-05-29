import SwiftUI
import Kingfisher

struct FavoritesStackedCard: View {
    struct FavoriteEntry {
        let title: String
        let subtitle: String
        let posterURL: URL?
    }

    let entries: [FavoriteEntry]
    let totalCount: Int
    let movieCount: Int
    let tvShowCount: Int

    var body: some View {
        HStack(spacing: 8) {
            posterStack
                .frame(width: 182, height: 150)

            VStack(alignment: .leading, spacing: 7) {
                Text("我的收藏")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(totalCount)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text("部作品")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    countBadge("\(movieCount) 电影", icon: "film.fill")
                    countBadge("\(tvShowCount) 剧集", icon: "tv.fill")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(22)
        .background {
            cardBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            favoriteBadge
                .padding(14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.22),
                            .white.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("我的收藏，共 \(totalCount) 部")
    }

    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            if let featuredPosterURL {
                KFImage(featuredPosterURL)
                    .placeholder {
                        Color.vanmoSurface
                    }
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 42)
                    .saturation(1.35)
                    .opacity(0.48)
            }

            LinearGradient(
                colors: [
                    Color.vanmoSurface.opacity(0.92),
                    Color.vanmoSurface.opacity(0.76),
                    Color.vanmoBackground.opacity(0.86),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    .black.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var favoriteBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(
                    colors: [
                        Color.pink,
                        Color.red.opacity(0.9),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .shadow(color: .pink.opacity(0.38), radius: 9, x: 0, y: 5)
            .accessibilityHidden(true)
    }

    private var posterStack: some View {
        let visibleEntries = displayEntries
        let count = visibleEntries.count

        return ZStack(alignment: .center) {
            if count >= 2 {
                Ellipse()
                    .fill(.black.opacity(0.16))
                    .frame(width: count == 2 ? 118 : 130, height: 32)
                    .blur(radius: 16)
                    .offset(x: 0, y: 52)
            }

            ForEach(Array(visibleEntries.enumerated()).reversed(), id: \.offset) { index, entry in
                let layout = cardLayout(for: index, count: count)
                ReferenceFavoriteStackCard(url: entry.posterURL, style: stackCardStyle(for: entry, index: index))
                    .frame(width: 124, height: 96)
                    .scaleEffect(layout.scale)
                    .rotation3DEffect(
                        .degrees(layout.tilt),
                        axis: (x: 0.2, y: 1, z: 0.08),
                        perspective: 0.72
                    )
                    .rotationEffect(.degrees(layout.rotation))
                    .offset(layout.offset)
                    .opacity(layout.opacity)
                    .zIndex(Double(count - index))
                    .shadow(
                        color: .black.opacity(layout.shadowOpacity),
                        radius: layout.shadowRadius,
                        x: 0,
                        y: layout.shadowY
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var displayEntries: [FavoriteEntry] {
        let items = Array(entries.prefix(3))
        guard items.isEmpty else { return items }
        return Array(
            repeating: FavoriteEntry(title: "收藏", subtitle: "Favorite", posterURL: nil),
            count: 3
        )
    }

    private var featuredPosterURL: URL? {
        entries.compactMap(\.posterURL).first
    }

    private struct StackCardLayout {
        let scale: CGFloat
        let tilt: Double
        let rotation: Double
        let offset: CGSize
        let opacity: Double
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowY: CGFloat
    }

    private func cardLayout(for index: Int, count: Int) -> StackCardLayout {
        switch count {
        case ...1:
            return StackCardLayout(
                scale: 1.06,
                tilt: -3,
                rotation: -2,
                offset: CGSize(width: 0, height: 4),
                opacity: 1,
                shadowOpacity: 0.24,
                shadowRadius: 24,
                shadowY: 18
            )
        case 2:
            switch index {
            case 0:
                return StackCardLayout(
                    scale: 1,
                    tilt: -6,
                    rotation: -3,
                    offset: CGSize(width: 20, height: 8),
                    opacity: 1,
                    shadowOpacity: 0.26,
                    shadowRadius: 22,
                    shadowY: 20
                )
            default:
                return StackCardLayout(
                    scale: 0.95,
                    tilt: 6,
                    rotation: 4,
                    offset: CGSize(width: -24, height: -6),
                    opacity: 1,
                    shadowOpacity: 0.16,
                    shadowRadius: 18,
                    shadowY: 16
                )
            }
        default:
            switch index {
            case 0:
                return StackCardLayout(
                    scale: 1,
                    tilt: -8,
                    rotation: -4,
                    offset: CGSize(width: 14, height: 10),
                    opacity: 1,
                    shadowOpacity: 0.26,
                    shadowRadius: 22,
                    shadowY: 20
                )
            case 1:
                return StackCardLayout(
                    scale: 0.94,
                    tilt: 5,
                    rotation: 3,
                    offset: CGSize(width: -6, height: -18),
                    opacity: 1,
                    shadowOpacity: 0.18,
                    shadowRadius: 18,
                    shadowY: 16
                )
            default:
                return StackCardLayout(
                    scale: 0.9,
                    tilt: 10,
                    rotation: -7,
                    offset: CGSize(width: -24, height: 14),
                    opacity: 0.82,
                    shadowOpacity: 0.14,
                    shadowRadius: 16,
                    shadowY: 14
                )
            }
        }
    }

    private func stackCardStyle(for entry: FavoriteEntry, index: Int) -> ReferenceFavoriteStackCard.Style {
        .init(
            title: entry.title,
            subtitle: entry.subtitle,
            trailingText: nil,
            showsStars: index == 0
        )
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
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

struct FavoritesCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct ReferenceFavoriteStackCard: View {
    struct Style {
        let title: String
        let subtitle: String
        let trailingText: String?
        let showsStars: Bool
    }

    let url: URL?
    let style: Style

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .frame(height: 54)

            footer
                .frame(height: 42)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            cardBorder
        }
    }

    private var artwork: some View {
        KFImage(url)
            .placeholder {
                placeholder
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(style.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.2))
                    .lineLimit(1)

                Text(style.subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.56, blue: 0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 7) {
                if let trailingText = style.trailingText {
                    Text(trailingText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.86, green: 0.31, blue: 0.34))
                        .lineLimit(1)
                }

                if style.showsStars {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(Color(red: 0.9, green: 0.68, blue: 0.2))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(0.65), lineWidth: 0.8)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.42, blue: 0.28),
                Color(red: 0.98, green: 0.72, blue: 0.34),
                Color(red: 0.22, green: 0.18, blue: 0.14),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

#Preview {
    FavoritesStackedCard(
        entries: [
            .init(title: "盗梦空间", subtitle: "电影", posterURL: nil),
            .init(title: "繁花", subtitle: "电视剧", posterURL: nil),
            .init(title: "奥本海默", subtitle: "电影", posterURL: nil),
        ],
        totalCount: 18,
        movieCount: 12,
        tvShowCount: 6
    )
    .padding()
    .background(Color.vanmoBackground)
    .preferredColorScheme(.dark)
}
