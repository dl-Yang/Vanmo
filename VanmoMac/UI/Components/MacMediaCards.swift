import SwiftUI
import VanmoCore

// MARK: - Featured Hero Banner (21:9 + Lounging Black Cat)

struct MacFeaturedHeroBanner: View {
    @Environment(\.macTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: MediaItem
    let sourceLabel: String?
    let onPlay: () -> Void
    let onInspectDetails: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            bannerCard
                .padding(.top, 36)

            Image("MacCatHeroLounging")
                .resizable()
                .scaledToFit()
                .frame(width: 168, height: 72)
                .offset(x: -64, y: -8)
                .offset(y: isHovered && !reduceMotion ? -3 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var bannerCard: some View {
        ZStack(alignment: .leading) {
            MacRemoteImage(url: item.backdropURL ?? item.posterURL)
                .frame(height: MacDesignTokens.Layout.heroBannerHeight)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: MacDesignTokens.catSilhouette.opacity(0.95), location: 0),
                    .init(color: MacDesignTokens.catSilhouette.opacity(0.62), location: 0.48),
                    .init(color: MacDesignTokens.catSilhouette.opacity(0.14), location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 0) {
                featuredTag
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                        .lineLimit(1)

                    if let metaLine {
                        Text(metaLine)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MacDesignTokens.glowAmber)
                            .lineLimit(1)
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(item.mediaType == .tvShow ? L10n.tr("播放") : L10n.tr("播放影片"))
                        }
                    }
                    .buttonStyle(MacCatAmberButtonStyle(height: 38, horizontalPadding: 18))

                    Button(action: onInspectDetails) {
                        Text(L10n.tr("查看详情"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.9)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 27)
            .padding(.vertical, 22)
        }
        .frame(height: MacDesignTokens.Layout.heroBannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.heroBanner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.heroBanner, style: .continuous)
                .strokeBorder(
                    isHovered ? MacDesignTokens.Cinema.strokeAmber : theme.strokeGlass,
                    lineWidth: isHovered ? 1.15 : 1
                )
        }
        .shadow(
            color: isHovered ? MacDesignTokens.glowAmber.opacity(0.16) : Color.black.opacity(theme.isDark ? 0.5 : 0.14),
            radius: 14,
            y: 8
        )
        .contentShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.heroBanner, style: .continuous))
        .onTapGesture(perform: onInspectDetails)
    }

    private var featuredTag: some View {
        let parts = [
            L10n.tr("精选").uppercased(),
            sourceLabel?.uppercased(),
            item.qualityBadgeLabel?.uppercased(),
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        return HStack(spacing: 6) {
            Circle()
                .fill(MacDesignTokens.glowAmber)
                .frame(width: 6, height: 6)

            Text(parts.joined(separator: " · "))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.85)
        }
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let rating = item.rating, rating > 0 {
            let displayScore = rating <= 1.0 ? rating * 10.0 : rating
            parts.append(String(format: "★ %.1f", displayScore))
        }
        if let year = item.year {
            parts.append(String(year))
        }
        if let genre = item.genres.first, !genre.isEmpty {
            parts.append(genre)
        }
        if item.duration > 0 {
            parts.append(MacFormatters.formatDuration(item.duration))
        }
        if let badge = item.qualityBadgeLabel {
            parts.append(badge)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

// MARK: - Continue Watching Card

struct MacContinueWatchingCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String
    let posterURL: URL?
    let progress: Double
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottom) {
                    MacRemoteImage(url: posterURL)
                        .frame(
                            width: MacDesignTokens.Layout.continueWatchingWidth,
                            height: MacDesignTokens.Layout.continueWatchingThumbHeight
                        )
                        .clipped()

                    LinearGradient(
                        colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.91)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 68)

                    MacCatProgressTrack(progress: progress)
                        .padding(.horizontal, 11)
                        .padding(.bottom, 10)
                }
                .frame(
                    width: MacDesignTokens.Layout.continueWatchingWidth,
                    height: MacDesignTokens.Layout.continueWatchingThumbHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching, style: .continuous)
                        .strokeBorder(
                            isHovered ? theme.strokeAmber : theme.strokeGlass,
                            lineWidth: isHovered ? 1.25 : 0.9
                        )
                }
                .shadow(
                    color: isHovered ? MacDesignTokens.glowAmber.opacity(0.18) : Color.black.opacity(theme.isDark ? 0.35 : 0.08),
                    radius: isHovered ? 12 : 6,
                    y: isHovered ? 6 : 3
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(MacDesignTokens.Typography.cardTitle)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(MacDesignTokens.Typography.cardSubtitle)
                        .foregroundStyle(isHovered ? theme.accentAmber : theme.cardSubtitle)
                        .lineLimit(1)
                }
            }
            .frame(width: MacDesignTokens.Layout.continueWatchingWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
    }
}

/// 「查看更多」入口卡片：与继续观看卡片等宽等高，放在首页继续观看列表末尾。
struct MacContinueWatchingMoreCard: View {
    @Environment(\.macTheme) private var theme

    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching, style: .continuous)
                        .fill(isHovered ? theme.amberTintFill : theme.surfaceGlass)
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching, style: .continuous)
                                .strokeBorder(isHovered ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.9)
                        }

                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                        Text(L10n.tr("查看更多"))
                            .font(MacDesignTokens.Typography.cardAction)
                    }
                    .foregroundStyle(isHovered ? theme.accentAmber : theme.secondaryText)
                }
                .frame(
                    width: MacDesignTokens.Layout.continueWatchingWidth,
                    height: MacDesignTokens.Layout.continueWatchingThumbHeight
                )

                Text(L10n.tr("全部历史记录"))
                    .font(MacDesignTokens.Typography.cardTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            }
            .frame(width: MacDesignTokens.Layout.continueWatchingWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .help(L10n.tr("查看全部历史记录"))
    }
}

// MARK: - 2:3 Poster Card

struct MacPosterCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String
    let posterURL: URL?
    var width: CGFloat = MacDesignTokens.Layout.posterWidth
    var height: CGFloat = MacDesignTokens.Layout.posterHeight
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottom) {
                    MacRemoteImage(url: posterURL)
                        .frame(width: width, height: height)
                        .clipped()

                    LinearGradient(
                        colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster, style: .continuous)
                        .strokeBorder(
                            isHovered ? theme.strokeAmber : theme.strokeGlass,
                            lineWidth: isHovered ? 1.2 : 0.9
                        )
                }
                .shadow(
                    color: isHovered ? MacDesignTokens.glowAmber.opacity(0.16) : Color.black.opacity(theme.isDark ? 0.35 : 0.08),
                    radius: isHovered ? 10 : 5,
                    y: 4
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(isHovered ? theme.accentAmber : theme.cardSubtitle)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
    }
}

struct MacLibrarySectionHeader: View {
    @Environment(\.macTheme) private var theme

    let title: String

    var body: some View {
        MacCatSectionHeaderRow(title: title, showsStretchingCat: true)
    }
}

struct MacLibraryDisplayItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let posterURL: URL?
    let progress: Double
    let mediaItem: MediaItem?
}

struct MacFolderBookmarkCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let connectionName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accentAmber)
                    .frame(width: 34, height: 34)
                    .background(theme.amberTintFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                    }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(connectionName)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 180, alignment: .leading)
            .padding(14)
            .macCatGlassCard(theme: theme, cornerRadius: 14, isHighlighted: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
    }
}

struct MacLibrarySectionHeaderRow: View {
    let title: String
    let subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        MacCatSectionHeaderRow(
            title: title,
            badgeText: subtitle,
            actionTitle: actionTitle,
            action: action
        )
    }
}

struct MacFolderPreviewSkeletonRow: View {
    @Environment(\.macTheme) private var theme

    var body: some View {
        HStack(spacing: MacDesignTokens.Layout.posterSpacing) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster, style: .continuous)
                    .fill(theme.surfaceGlass)
                    .overlay {
                        RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster, style: .continuous)
                            .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                    }
                    .frame(width: MacDesignTokens.Layout.posterWidth, height: MacDesignTokens.Layout.posterHeight)
            }
        }
    }
}

private extension MediaItem {
    var qualityBadgeLabel: String? {
        if let dr = dynamicRange?.uppercased(), !dr.isEmpty {
            if let h = videoHeight, h >= 2000 {
                return "4K \(dr)"
            }
            return dr
        }
        if let h = videoHeight {
            if h >= 2000 { return "4K" }
            if h >= 1000 { return "1080p" }
        }
        return nil
    }
}
