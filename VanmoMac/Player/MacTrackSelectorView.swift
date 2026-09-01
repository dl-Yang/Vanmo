import SwiftUI
import VanmoCore

struct MacTrackSelectorView: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                audioSection
                subtitleSection
            }
            .navigationTitle(L10n.tr("音轨与字幕"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private var audioSection: some View {
        Section(L10n.tr("音轨")) {
            if viewModel.audioTracks.isEmpty {
                Text(L10n.tr("无可用音轨"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.audioTracks) { track in
                    Button {
                        viewModel.selectAudioTrack(track.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayName)
                                    .font(.subheadline)
                                if let codec = track.codec {
                                    Text(codec)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if viewModel.config.selectedAudioTrack == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(MacDesignTokens.accentBlue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var subtitleSection: some View {
        Section(L10n.tr("字幕")) {
            Button {
                viewModel.selectSubtitleTrack(nil)
            } label: {
                HStack {
                    Text(L10n.tr("关闭字幕"))
                    Spacer()
                    if viewModel.config.selectedSubtitleTrack == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(MacDesignTokens.accentBlue)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                viewModel.searchOnlineSubtitles()
            } label: {
                HStack {
                    Label(L10n.tr("搜索在线字幕"), systemImage: "magnifyingglass")
                    Spacer()
                    if viewModel.isSearchingOnlineSubtitles {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(viewModel.isSearchingOnlineSubtitles)
            .buttonStyle(.plain)

            if let message = viewModel.onlineSubtitleStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.onlineSubtitleResults) { result in
                Button {
                    viewModel.downloadOnlineSubtitle(result)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.subheadline)
                            Text(onlineSubtitleMetadata(for: result))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.downloadingOnlineSubtitleID == result.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(MacDesignTokens.accentBlue)
                        }
                    }
                }
                .disabled(viewModel.downloadingOnlineSubtitleID == result.id)
                .buttonStyle(.plain)
            }

            ForEach(viewModel.subtitleTracks) { track in
                Button {
                    viewModel.selectSubtitleTrack(track.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .font(.subheadline)
                            Text(track.isEmbedded ? L10n.tr("内嵌字幕") : L10n.tr("外挂字幕"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.config.selectedSubtitleTrack == track.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(MacDesignTokens.accentBlue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onlineSubtitleMetadata(for result: OnlineSubtitleResult) -> String {
        var parts = [
            result.provider,
            result.language,
            result.format.fileExtension.uppercased(),
        ].compactMap { $0 }
        if let downloadCount = result.downloadCount {
            parts.append("\(downloadCount) 次下载")
        }
        return parts.joined(separator: " · ")
    }
}
