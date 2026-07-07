import SwiftUI
import VanmoCore

struct MacSettingsView: View {
    @StateObject private var viewModel = MacSettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @Environment(\.macTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(MacDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.primaryText)

                cloudSyncSection
                playbackSection
                subtitleSection
            }
            .padding(MacDesignTokens.Layout.contentPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.appBackground)
        .task {
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
        .onChange(of: cloudSyncCoordinator.statusMessage) { _, message in
            viewModel.cloudSyncStatusMessage = message
        }
        .onChange(of: cloudSyncCoordinator.lastSyncAt) { _, _ in
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
    }

    private var cloudSyncSection: some View {
        settingsSection(title: "iCloud Sync", systemImage: "icloud") {
            Toggle("iCloud 同步", isOn: Binding(
                get: { viewModel.cloudSyncEnabled },
                set: { viewModel.updateCloudSyncEnabled($0, coordinator: cloudSyncCoordinator) }
            ))
            .disabled(!CloudSyncAvailability.isCloudKitEnabled)

            if !CloudSyncAvailability.isCloudKitEnabled {
                Text(CloudSyncAvailability.unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            settingsRow(label: "上次同步", value: viewModel.cloudSyncLastUpdatedText)

            if let message = viewModel.cloudSyncStatusMessage ?? cloudSyncCoordinator.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Text("通过 CloudKit 同步服务器配置、播放进度、收藏和文件夹书签。密码与 OAuth 凭据保存在本机 Keychain。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var playbackSection: some View {
        settingsSection(title: "Playback", systemImage: "play.circle") {
            Toggle("自动播放下一集", isOn: $viewModel.autoPlayNext)
            Toggle("断点续播", isOn: $viewModel.resumePlayback)
            Toggle("硬件解码优先", isOn: $viewModel.hardwareDecoding)

            HStack {
                Text("默认播放速度")
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Picker("", selection: $viewModel.defaultRate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Text("\(rate, specifier: "%.2g")x").tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var subtitleSection: some View {
        settingsSection(title: "Subtitles", systemImage: "captions.bubble") {
            Toggle("自动加载字幕", isOn: $viewModel.subtitleAutoLoad)

            HStack {
                Text("字幕大小")
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Stepper(
                    "\(Int(viewModel.subtitleFontSize))pt",
                    value: $viewModel.subtitleFontSize,
                    in: 12...36,
                    step: 2
                )
            }

            Picker("首选语言", selection: $viewModel.subtitlePreferredLanguage) {
                Text("中文").tag("zh")
                Text("English").tag("en")
                Text("日本語").tag("ja")
            }

            Picker("字幕位置", selection: $viewModel.subtitlePosition) {
                ForEach(MacSubtitlePosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            }

            ColorPicker("文字颜色", selection: Binding(
                get: { viewModel.subtitleTextColor },
                set: { viewModel.subtitleTextColor = $0 }
            ))

            ColorPicker("背景颜色", selection: Binding(
                get: { viewModel.subtitleBackgroundColor },
                set: { viewModel.subtitleBackgroundColor = $0 }
            ))
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.primaryText)
            Spacer()
            Text(value)
                .foregroundStyle(theme.secondaryText)
        }
    }
}

#Preview {
    MacSettingsView()
        .environmentObject(CloudSyncCoordinator.shared)
        .macTheme(.dark)
        .frame(width: 800, height: 600)
}
