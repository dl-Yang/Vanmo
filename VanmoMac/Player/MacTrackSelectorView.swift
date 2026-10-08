import SwiftUI
import VanmoCore

struct MacAudioTrackSelectorView: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle(L10n.tr("音轨"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

struct MacSubtitleSelectorView: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                subtitleSection
                styleSections
            }
            .navigationTitle(L10n.tr("字幕"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
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

    private var styleSections: some View {
        Group {
            Section(L10n.tr("字体")) {
                HStack {
                    Text(L10n.tr("大小"))
                    Spacer()
                    Stepper(
                        "\(Int(viewModel.subtitleStyle.fontSize))pt",
                        value: $viewModel.subtitleStyle.fontSize,
                        in: 12...36,
                        step: 2
                    )
                }
                ColorPicker(L10n.tr("文字颜色"), selection: $viewModel.subtitleStyle.textColor)
            }

            Section(L10n.tr("背景")) {
                ColorPicker(L10n.tr("背景颜色"), selection: $viewModel.subtitleStyle.backgroundColor)
            }

            Section(L10n.tr("时间偏移")) {
                HStack {
                    Text(String(format: "%+.1fs", viewModel.config.subtitleDelay))
                        .monospacedDigit()
                        .frame(width: 60)
                    Slider(
                        value: Binding(
                            get: { viewModel.config.subtitleDelay },
                            set: { viewModel.setSubtitleDelay($0) }
                        ),
                        in: -10...10,
                        step: 0.1
                    )
                }
                HStack {
                    Button("-0.5s") { viewModel.setSubtitleDelay(viewModel.config.subtitleDelay - 0.5) }
                    Spacer()
                    Button(L10n.tr("重置")) { viewModel.setSubtitleDelay(0) }
                    Spacer()
                    Button("+0.5s") { viewModel.setSubtitleDelay(viewModel.config.subtitleDelay + 0.5) }
                }
            }

            Section(L10n.tr("位置")) {
                Picker(L10n.tr("位置"), selection: $viewModel.subtitleStyle.position) {
                    Text(L10n.tr("顶部")).tag(MacSubtitleStyle.MacSubtitlePosition.top)
                    Text(L10n.tr("底部")).tag(MacSubtitleStyle.MacSubtitlePosition.bottom)
                }
                .pickerStyle(.segmented)
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
