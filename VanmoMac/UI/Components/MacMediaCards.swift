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

/// 「查看更多」入口卡片：与继续观看卡片等宽等高，放在首页历史记录列表末尾。
struct MacContinueWatchingMoreCard: View {
    @Environment(\.macTheme) private var theme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.continueWatching)
                        .fill(theme.secondaryButtonBackground)

                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                        Text("查看更多")
                            .font(MacDesignTokens.Typography.cardAction)
                    }
                    .foregroundStyle(theme.secondaryText)
                }
                .frame(
                    width: MacDesignTokens.Layout.continueWatchingWidth,
                    height: MacDesignTokens.Layout.continueWatchingThumbHeight
                )

                Text("全部历史记录")
                    .font(MacDesignTokens.Typography.cardTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .padding(.top, 12)
            }
            .frame(width: MacDesignTokens.Layout.continueWatchingWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("查看全部历史记录")
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
                    .lineLimit(1)
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
