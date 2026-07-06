import SwiftUI
import VanmoCore

struct MacMediaDetailView: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    let item: MediaItem

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    contentSection
                }
            }

            backButton
        }
        .background(theme.appBackground)
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            MacRemoteImage(url: item.backdropURL ?? item.posterURL)
                .frame(height: MacDesignTokens.Layout.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    theme.appBackground.opacity(0),
                    theme.appBackground.opacity(0.6),
                    theme.appBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: MacDesignTokens.Layout.heroHeight)

            VStack(alignment: .leading, spacing: 16) {
                Text(displayTitle)
                    .font(MacDesignTokens.Typography.detailHeroTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                metadataRow
                actionButtons
            }
            .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
            .padding(.bottom, 24)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let rating = item.rating, rating > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(MacDesignTokens.ratingRed)
                        .font(.system(size: 14))
                    Text("\(Int(rating * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MacDesignTokens.ratingRed)
                }
            }

            if let year = item.year {
                metadataDot
                Text(String(year))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if item.mediaType == .tvShow {
                metadataDot
                metadataChip("TV-MA")
                metadataDot
                Text(episodeCountText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if !genres.isEmpty {
                metadataDot
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        metadataChip(genre)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                appState.play(item, from: item.lastPlaybackPosition)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(MacDesignTokens.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.playButton))
            }
            .buttonStyle(.plain)

            secondaryActionButton(systemImage: "heart")
            secondaryActionButton(systemImage: "checkmark")
            secondaryActionButton(systemImage: "ellipsis")
        }
        .padding(.top, 8)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 48) {
            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryText)
                    .lineSpacing(6)
                    .frame(maxWidth: 896, alignment: .leading)
            }

            castSection
        }
        .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }

    private var castSection: some View {
        Group {
            if !castMembers.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cast & Crew")
                        .font(MacDesignTokens.Typography.detailSectionTitle)
                        .foregroundStyle(theme.primaryText)
                        .padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(Array(castMembers.enumerated()), id: \.offset) { _, member in
                                VStack(spacing: 12) {
                                    MacRemoteImage(url: member.imageURL)
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())

                                    Text(member.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .multilineTextAlignment(.center)

                                    if !member.role.isEmpty {
                                        Text(member.role)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.cardSubtitle)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 112)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            appState.closeDetail()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 12)
    }

    private func secondaryActionButton(systemImage: String) -> some View {
        Button {
            // 收藏 / 已看 / 更多 功能暂未适配
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 40, height: 40)
                .background(theme.secondaryButtonBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.chipText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.chipBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip)
                    .stroke(theme.chipBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip))
    }

    private var metadataDot: some View {
        Text("•")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.secondaryText)
    }

    private var displayTitle: String {
        item.showTitle ?? item.title
    }

    private var genres: [String] {
        Array(item.genres.prefix(3))
    }

    private var episodeCountText: String {
        "Episodes"
    }

    private var castMembers: [(name: String, role: String, imageURL: URL?)] {
        item.cast.prefix(5).map { name in
            (name, "", nil as URL?)
        }
    }
}

#Preview {
    MacMediaDetailView(item: MacMediaDetailPreviewItem.make())
        .environmentObject(MacAppState())
        .macTheme(.dark)
        .frame(width: 1214, height: 836)
}

private enum MacMediaDetailPreviewItem {
    static func make() -> MediaItem {
        let item = MediaItem(
            title: "Preview Title",
            fileURL: URL(fileURLWithPath: "/tmp/preview.mkv"),
            mediaType: .movie,
            fileSize: 0,
            duration: 7200
        )
        item.overview = "Preview overview for media detail layout."
        item.year = 2024
        item.rating = 0.92
        item.genres = ["Drama", "History"]
        return item
    }
}
