import SwiftUI
import VanmoCore

struct MacEpisodeSelectorView: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.episodeGroups.count > 1 {
                    seasonPicker
                }

                List {
                    ForEach(viewModel.selectedSeasonEpisodes) { episode in
                        Button {
                            Task {
                                await viewModel.playEpisode(episode)
                                dismiss()
                            }
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }
            .padding(.top, 12)
            .navigationTitle("选集")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.episodeGroups) { group in
                    Button {
                        viewModel.selectedEpisodeSeason = group.seasonNumber
                    } label: {
                        Text("第 \(group.seasonNumber) 季")
                            .font(.subheadline)
                            .fontWeight(isSelectedSeason(group.seasonNumber) ? .semibold : .regular)
                            .foregroundStyle(isSelectedSeason(group.seasonNumber) ? MacDesignTokens.accentBlue : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelectedSeason(group.seasonNumber)
                                    ? MacDesignTokens.accentBlue.opacity(0.16)
                                    : Color.primary.opacity(0.06),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func episodeRow(_ episode: MacPlayerEpisode) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("E\(String(format: "%02d", episode.episodeNumber))")
                    .font(.caption)
                    .fontWeight(.bold)
                Text("S\(String(format: "%02d", episode.seasonNumber))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isCurrentEpisode(episode) ? MacDesignTokens.accentBlue : .primary)
            .frame(width: 48, height: 48)
            .background(
                (isCurrentEpisode(episode) ? MacDesignTokens.accentBlue.opacity(0.14) : Color.primary.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(episode.episodeCode)
                    if episode.duration > 0 {
                        Text(MacFormatters.formatDuration(episode.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isCurrentEpisode(episode) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(MacDesignTokens.accentBlue)
            }
        }
        .contentShape(Rectangle())
    }

    private func isSelectedSeason(_ season: Int) -> Bool {
        (viewModel.selectedEpisodeSeason ?? viewModel.episodeGroups.first?.seasonNumber) == season
    }

    private func isCurrentEpisode(_ episode: MacPlayerEpisode) -> Bool {
        viewModel.currentEpisodeID == episode.id
    }
}
