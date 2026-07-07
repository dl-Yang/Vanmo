import SwiftUI
import VanmoCore

struct MacMediaListRow: View {
    @Environment(\.macTheme) private var theme

    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            MacRemoteImage(url: item.posterURL)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let year = item.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Text(item.mediaType.displayName)
                        .font(.caption2)
                        .foregroundStyle(MacDesignTokens.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MacDesignTokens.accentBlue.opacity(0.12))
                        .clipShape(Capsule())
                }

                if item.duration > 0 {
                    Text(MacFormatters.formatDuration(item.duration))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                if item.playbackProgress > 0 {
                    ProgressView(value: item.playbackProgress)
                        .tint(MacDesignTokens.accentBlue)
                        .scaleEffect(y: 0.6)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let rating = item.rating, rating > 0 {
                    Text("\(Int(rating * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(MacDesignTokens.ratingRed)
                }

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 8)
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
        LazyVStack(spacing: 0) {
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
