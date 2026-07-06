import SwiftUI
import VanmoCore

struct TrackSelectorView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                audioSection
                subtitleSection
            }
            .navigationTitle("音轨与字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var audioSection: some View {
        Section("音轨") {
            if viewModel.audioTracks.isEmpty {
                Text("无可用音轨")
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
                                    .foregroundStyle(Color.vanmoPrimary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private var subtitleSection: some View {
        Section("字幕") {
            Button {
                viewModel.selectSubtitleTrack(nil)
            } label: {
                HStack {
                    Text("关闭字幕")
                        .font(.subheadline)
                    Spacer()
                    if viewModel.config.selectedSubtitleTrack == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.vanmoPrimary)
                    }
                }
            }
            .tint(.primary)

            Button {
                viewModel.searchOnlineSubtitles()
            } label: {
                HStack {
                    Label("搜索在线字幕", systemImage: "magnifyingglass")
                    Spacer()
                    if viewModel.isSearchingOnlineSubtitles {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isSearchingOnlineSubtitles)

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
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(Color.vanmoPrimary)
                        }
                    }
                }
                .disabled(viewModel.downloadingOnlineSubtitleID == result.id)
            }

            ForEach(viewModel.subtitleTracks) { track in
                Button {
                    viewModel.selectSubtitleTrack(track.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .font(.subheadline)
                            Text(track.isEmbedded ? "内嵌字幕" : "外挂字幕")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.config.selectedSubtitleTrack == track.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.vanmoPrimary)
                        }
                    }
                }
                .tint(.primary)
            }
        }
    }

    private func onlineSubtitleMetadata(for result: OnlineSubtitleResult) -> String {
        var parts = [
            result.provider,
            result.language,
            result.format.fileExtension.uppercased()
        ].compactMap { $0 }
        if let downloadCount = result.downloadCount {
            parts.append("\(downloadCount) 次下载")
        }
        if result.isTrusted == true {
            parts.append("可信")
        }
        if result.isMachineTranslated == true {
            parts.append("机器翻译")
        }
        return parts
        .joined(separator: " · ")
    }
}
