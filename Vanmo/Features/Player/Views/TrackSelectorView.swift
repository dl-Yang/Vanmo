import SwiftUI

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
                                    .foregroundStyle(.vanmoPrimary)
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
                            .foregroundStyle(.vanmoPrimary)
                    }
                }
            }
            .tint(.primary)

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
                                .foregroundStyle(.vanmoPrimary)
                        }
                    }
                }
                .tint(.primary)
            }
        }
    }
}
