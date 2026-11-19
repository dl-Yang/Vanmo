import SwiftUI
import VanmoCore

struct MacMediaListRow: View {
    @Environment(\.macTheme) private var theme

    let item: MediaItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            MacRemoteImage(url: item.posterURL)
                .frame(width: 54, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.75)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let year = item.year {
                        Text(String(year))
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.secondaryText)
                    }

                    Text(item.mediaType.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.accentAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.amberTintFill, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }

                    if item.duration > 0 {
                        Text(MacFormatters.formatDuration(item.duration))
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                if item.playbackProgress > 0 {
                    MacCatProgressTrack(
                        progress: item.playbackProgress,
                        trackColor: theme.progressTrack,
                        height: 3,
                        showsPawThumb: true,
                        pawSize: 8
                    )
                    .frame(maxWidth: 260)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if let rating = item.rating, rating > 0 {
                    let score = rating <= 1.0 ? rating * 10.0 : rating
                    Text(String(format: "★ %.1f", score))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(theme.accentAmber)
                }

                if item.isFavorite {
                    Image("MacCatPawStamp")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(theme.accentAmber)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .macCatGlassCard(theme: theme, cornerRadius: 14, isHighlighted: isHovered)
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct MacLibraryMediaLayout<GridContent: View, ListContent: View>: View {
    let viewMode: MacLibraryViewMode
    @ViewBuilder let gridContent: () -> GridContent
    @ViewBuilder let listContent: () -> ListContent

    var body: some View {
        switch viewMode {
        case .grid:
            gridContent()
        case .list:
            listContent()
        }
    }
}

struct MacLibraryPosterGrid: View {
    @EnvironmentObject private var appState: MacAppState

    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: MacDesignTokens.Layout.posterSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: MacDesignTokens.Layout.posterSpacing) {
            ForEach(items) { item in
                MacPosterCard(
                    title: item.displayTitle,
                    subtitle: subtitle(for: item),
                    posterURL: item.posterURL
                ) {
                    onSelect(item)
                }
                .macMediaItemContextMenu(for: item)
            }
        }
    }

    private func subtitle(for item: MediaItem) -> String {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }
}

struct MacLibraryPosterList: View {
    @EnvironmentObject private var appState: MacAppState

    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    var onItemAppear: ((MediaItem) -> Void)?

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    MacMediaListRow(item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .macMediaItemContextMenu(for: item)
                .onAppear {
                    onItemAppear?(item)
                }
            }
        }
    }
}
