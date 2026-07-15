import AppKit
import SwiftUI
import VanmoCore

struct MacSettingsView: View {
    @StateObject private var viewModel = MacSettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.macTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(MacDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.primaryText)

                cloudSyncSection
                playbackSection
                audioSection
                subtitleSection
                librarySection
                metadataSection
                appearanceSection
                storageSection
                aboutSection
            }
            .padding(MacDesignTokens.Layout.contentPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.appBackground)
        .task {
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
            await viewModel.calculateCacheSize()
            await viewModel.calculateMetadataCacheSize()
            appState.syncAppearance(with: colorScheme)
        }
        .onChange(of: cloudSyncCoordinator.statusMessage) { _, message in
            viewModel.cloudSyncStatusMessage = message
        }
        .onChange(of: cloudSyncCoordinator.lastSyncAt) { _, _ in
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
        .onChange(of: viewModel.appearanceMode) { _, _ in
            appState.appearanceMode = viewModel.appearanceMode
            appState.syncAppearance(with: colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            appState.syncAppearance(with: newScheme)
        }
        .alert("清除缓存", isPresented: $viewModel.showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
        } message: {
            Text("确定要清除所有缓存数据吗？这不会删除已下载的文件。")
        }
        .alert("删除元数据缓存", isPresented: $viewModel.showClearMetadataCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await viewModel.clearMetadataCache() }
            }
        } message: {
            Text("确定要删除所有元数据缓存吗？已保存的媒体信息不会被删除，但 Logo、演职人员头像和单集封面等缓存图片将被移除。")
        }
        .alert("重置设置", isPresented: $viewModel.showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                viewModel.resetAllSettings()
                appState.appearanceMode = .system
                appState.syncAppearance(with: colorScheme)
                Task {
                    await viewModel.calculateCacheSize()
                    await viewModel.calculateMetadataCacheSize()
                }
            }
        } message: {
            Text("确定要重置所有设置为默认值吗？")
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

    private var audioSection: some View {
        settingsSection(title: "Audio", systemImage: "hifispeaker.2") {
            Picker("输出模式", selection: $viewModel.audioOutputMode) {
                ForEach(AudioOutputMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }

            Text("「自动」根据当前输出设备自动选择最佳音频模式。连接支持杜比的耳机或音箱时将启用空间音频。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
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

    private var librarySection: some View {
        settingsSection(title: "Library", systemImage: "film.stack") {
            Toggle("自动扫描新文件", isOn: $viewModel.libraryAutoScan)
        }
    }

    private var metadataSection: some View {
        settingsSection(title: "Metadata", systemImage: "photo.on.rectangle.angled") {
            Toggle("自动从媒体服务器下载元数据", isOn: $viewModel.metadataAutoDownload)

            settingsRow(label: "元数据缓存大小", value: viewModel.metadataCacheSize)

            Button("删除所有元数据缓存") {
                viewModel.showClearMetadataCacheAlert = true
            }
            .foregroundStyle(.red)

            Text("仅 Emby、Jellyfin、Plex 媒体条目支持元数据刷新。关闭自动下载后，仍可在详情页手动更新。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var appearanceSection: some View {
        settingsSection(title: "Appearance", systemImage: "paintbrush") {
            Picker("主题", selection: $viewModel.appearanceMode) {
                ForEach(MacAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("跟随系统时，界面外观随 macOS 系统深浅色自动切换。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var storageSection: some View {
        settingsSection(title: "Storage", systemImage: "internaldrive") {
            settingsRow(label: "下载位置", value: downloadManager.destination.rootPath)

            HStack {
                Button("下载管理") {
                    openWindow(id: "downloads")
                }
                Button("选择下载目录") {
                    chooseDownloadDirectory()
                }
                Button("恢复默认目录") {
                    downloadManager.useDefaultDirectory()
                }
            }

            settingsRow(label: "缓存大小", value: viewModel.cacheSize)

            Button("清除缓存") {
                viewModel.showClearCacheAlert = true
            }
            .foregroundStyle(.red)
        }
    }

    private var aboutSection: some View {
        settingsSection(title: "About", systemImage: "info.circle") {
            settingsRow(label: "版本", value: viewModel.appVersion)

            Button("重置所有设置") {
                viewModel.showResetAlert = true
            }
            .foregroundStyle(.red)
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

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try downloadManager.setCustomDirectory(url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

struct MacDownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme
    @State private var selection: Set<UUID> = []
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("下载")
                    .font(.title2.bold())
                Spacer()
                if !selection.isEmpty {
                    Button("删除所选", role: .destructive) {
                        confirmsDeletion = true
                    }
                }
            }
            .padding()

            if downloadManager.tasks.isEmpty {
                ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloadManager.tasks, selection: $selection) { task in
                    MacDownloadTaskRow(
                        task: task,
                        play: { play(task) },
                        reveal: { reveal(task) },
                        retry: { Task { await downloadManager.retry(task.id) } }
                    )
                    .tag(task.id)
                }
            }
        }
        .background(theme.appBackground)
        .confirmationDialog("删除选中的下载？", isPresented: $confirmsDeletion) {
            Button("删除文件和记录", role: .destructive) {
                Task {
                    await downloadManager.delete(selection)
                    selection.removeAll()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func play(_ task: DownloadTaskSnapshot) {
        guard task.status == .completed,
              let url = try? downloadManager.completedFileURL(for: task.id),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let item = MediaItem(
            title: task.request.displayTitle,
            fileURL: url,
            mediaType: task.request.mediaType,
            fileSize: task.totalBytes
        )
        item.showTitle = task.request.showTitle
        item.seasonNumber = task.request.seasonNumber
        item.episodeNumber = task.request.episodeNumber
        item.episodeTitle = task.request.episodeTitle
        appState.play(item)
    }

    private func reveal(_ task: DownloadTaskSnapshot) {
        guard let url = try? downloadManager.completedFileURL(for: task.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct MacDownloadTaskRow: View {
    let task: DownloadTaskSnapshot
    let play: () -> Void
    let reveal: () -> Void
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(task.status == .failed ? .red : .blue)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.request.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if task.totalBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if task.status == .queued || task.status == .downloading {
                    ProgressView(value: task.totalBytes > 0 ? task.progress : nil)
                }
                if let errorMessage = task.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if task.status == .completed {
                Button("播放", action: play)
                Button {
                    reveal()
                } label: {
                    Image(systemName: "folder")
                }
                .help("在 Finder 中显示")
            } else if task.status == .failed {
                Button("重新下载", action: retry)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if task.status == .completed {
                Button("播放", action: play)
                Button("在 Finder 中显示", action: reveal)
            } else if task.status == .failed {
                Button("重新下载", action: retry)
            }
        }
    }

    private var statusText: String {
        switch task.status {
        case .queued: return "等待中"
        case .downloading: return task.totalBytes > 0 ? "\(Int(task.progress * 100))%" : "下载中"
        case .completed: return "已完成"
        case .failed: return "下载失败"
        }
    }
}

#Preview {
    MacSettingsView()
        .environmentObject(CloudSyncCoordinator.shared)
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 800, height: 900)
}
