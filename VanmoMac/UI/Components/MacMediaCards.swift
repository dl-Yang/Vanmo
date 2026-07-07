import SwiftUI
import VanmoCore

struct MacContinueWatchingCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String
    let posterURL: URL?
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    MacRemoteImage(url: posterURL)
                        .frame(
                            width: MacDesignTokens.Layout.continueWatchingWidth,
                            height: MacDesignTokens.Layout.continueWatchingThumbHeight
                        )
                        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.progressTrack)
                            Rectangle()
                                .fill(MacDesignTokens.accentBlue)
                                .frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 4)
                }

                Text(title)
                    .font(MacDesignTokens.Typography.cardTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .padding(.top, 12)

                Text(subtitle)
                    .font(MacDesignTokens.Typography.cardSubtitle)
                    .foregroundStyle(theme.cardSubtitle)
                    .padding(.top, 2)
            }
            .frame(width: MacDesignTokens.Layout.continueWatchingWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct MacPosterCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String
    let posterURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                MacRemoteImage(url: posterURL)
                    .frame(width: MacDesignTokens.Layout.posterWidth, height: MacDesignTokens.Layout.posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)

                Text(subtitle)
                    .font(MacDesignTokens.Typography.cardSubtitle)
                    .foregroundStyle(theme.cardSubtitle)
                    .padding(.top, 4)
            }
            .frame(width: MacDesignTokens.Layout.posterWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct MacLibrarySectionHeader: View {
    @Environment(\.macTheme) private var theme

    let title: String

    var body: some View {
        Text(title)
            .font(MacDesignTokens.Typography.sectionTitle)
            .foregroundStyle(theme.primaryText)
            .padding(.top, 40)
            .padding(.bottom, 12)
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

struct MacFavoritesStackedCard: View {
    @Environment(\.macTheme) private var theme

    let posterURLs: [URL?]
    let totalCount: Int
    let movieCount: Int
    let tvShowCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                HStack(spacing: -24) {
                    ForEach(Array(posterURLs.prefix(3).enumerated()), id: \.offset) { index, url in
                        MacRemoteImage(url: url)
                            .frame(width: 72, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.appBackground, lineWidth: 2)
                            }
                            .zIndex(Double(3 - index))
                    }
                }
                .frame(width: 160, height: 108, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("我的收藏")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(totalCount)")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("部作品")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }

                    HStack(spacing: 8) {
                        badge("\(movieCount) 电影", icon: "film")
                        badge("\(tvShowCount) 剧集", icon: "tv")
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(20)
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.chipBackground)
        .clipShape(Capsule())
    }
}

struct MacFolderBookmarkCard: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let connectionName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MacDesignTokens.accentBlue)
                    .frame(width: 36, height: 36)
                    .background(MacDesignTokens.accentBlue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(connectionName)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 180, alignment: .leading)
            .padding(16)
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct MacLibrarySectionHeaderRow: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MacDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct MacFolderPreviewSkeletonRow: View {
    @Environment(\.macTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.poster)
                    .fill(theme.chipBackground)
                    .frame(width: 120, height: 180)
            }
        }
    }
}
