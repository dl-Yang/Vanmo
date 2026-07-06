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
