import SwiftUI
import VanmoCore

struct MacEpisodeSelectorDrawerContent: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    let onDidSelectEpisode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.episodeGroups.count > 1 {
                seasonPicker
            }

            if viewModel.selectedSeasonEpisodes.isEmpty {
                Text(L10n.tr("暂无剧集"))
                    .font(.system(size: 12))
                    .foregroundStyle(MacDesignTokens.Cinema.textDim)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.selectedSeasonEpisodes) { episode in
                            episodeRow(episode)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.episodeGroups) { group in
                    let selected = isSelectedSeason(group.seasonNumber)
                    Button {
                        viewModel.selectedEpisodeSeason = group.seasonNumber
                    } label: {
                        Text(LocalizedFormat.seasonLabel(group.seasonNumber))
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? MacDesignTokens.Cinema.amber : MacDesignTokens.Cinema.textMuted)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                selected ? MacDesignTokens.Cinema.amberTint : MacDesignTokens.Cinema.surfacePill,
                                in: Capsule()
                            )
                            .overlay {
                                if selected {
                                    Capsule()
                                        .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 0.75)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func episodeRow(_ episode: MacPlayerEpisode) -> some View {
        let isCurrent = isCurrentEpisode(episode)
        return Button {
            Task {
                await viewModel.playEpisode(episode)
                onDidSelectEpisode()
            }
        } label: {
            HStack(spacing: 10) {
                if isCurrent {
                    MacPawDotIndicator(size: 10, useCinemaGlow: true)
                } else {
                    Color.clear.frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.displayTitle)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? MacDesignTokens.Cinema.textIvory : MacDesignTokens.Cinema.textMuted)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(episode.episodeCode)
                        if episode.duration > 0 {
                            Text("·")
                            Text(MacFormatters.formatDuration(episode.duration))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(isCurrent ? MacDesignTokens.Cinema.amber : MacDesignTokens.Cinema.textDim)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(
                isCurrent ? MacDesignTokens.Cinema.amberTint : MacDesignTokens.Cinema.surfaceRow,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 0.85)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelectedSeason(_ season: Int) -> Bool {
        (viewModel.selectedEpisodeSeason ?? viewModel.episodeGroups.first?.seasonNumber) == season
    }

    private func isCurrentEpisode(_ episode: MacPlayerEpisode) -> Bool {
        viewModel.currentEpisodeID == episode.id
    }
}

struct MacEpisodeSelectorView: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MacEpisodeSelectorDrawerContent(viewModel: viewModel) {
            dismiss()
        }
        .padding(16)
        .background(MacDesignTokens.Cinema.drawerGlass)
        .frame(width: 300)
    }
}
