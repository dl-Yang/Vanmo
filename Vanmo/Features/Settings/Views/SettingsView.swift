import SwiftUI
import VanmoCore

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator

    var body: some View {
        Form {
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
        .scrollContentBackground(.hidden)
        .background(Color.vanmoBackground)
        .navigationTitle("设置")
        .task {
            await viewModel.calculateCacheSize()
            await viewModel.calculateMetadataCacheSize()
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
        .onChange(of: cloudSyncCoordinator.statusMessage) { _, message in
            viewModel.cloudSyncStatusMessage = message
        }
        .onChange(of: cloudSyncCoordinator.lastSyncAt) { _, _ in
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
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
            }
        } message: {
            Text("确定要重置所有设置为默认值吗？")
        }
    }

    // MARK: - Sections

    private var cloudSyncSection: some View {
        Section {
            Toggle("iCloud 同步", isOn: Binding(
                get: { viewModel.cloudSyncEnabled },
                set: { viewModel.updateCloudSyncEnabled($0, coordinator: cloudSyncCoordinator) }
            ))
            .disabled(!CloudSyncAvailability.isCloudKitEnabled)

            if !CloudSyncAvailability.isCloudKitEnabled {
                Text(CloudSyncAvailability.unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("上次同步")
                Spacer()
                Text(viewModel.cloudSyncLastUpdatedText)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.cloudSyncStatusMessage ?? cloudSyncCoordinator.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("云同步", systemImage: "icloud")
        } footer: {
            Text("通过 CloudKit 同步服务器配置、非 Emby/Plex 播放进度、收藏和文件夹书签。密码与 OAuth 凭据仍保存在本机 Keychain，不会进入 iCloud。")
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle("自动播放下一集", isOn: $viewModel.autoPlayNext)
            Toggle("断点续播", isOn: $viewModel.resumePlayback)
            Toggle("硬件解码优先", isOn: $viewModel.hardwareDecoding)

            HStack {
                Text("默认播放速度")
                Spacer()
                Picker("", selection: $viewModel.defaultRate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Text("\(rate, specifier: "%.2g")x").tag(rate)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Label("播放", systemImage: "play.circle")
        } footer: {
            Text("硬件解码优先仅影响 KSPlayer 播放路径，并在下一次加载视频时生效；如果硬解初始化失败，播放器会自动尝试软解。")
        }
    }

    private var audioSection: some View {
        Section {
            Picker("输出模式", selection: $viewModel.audioOutputMode) {
                ForEach(AudioOutputMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
        } header: {
            Label("音频", systemImage: "hifispeaker.2")
        } footer: {
            Text("「自动」根据当前输出设备自动选择最佳音频模式。连接支持杜比的耳机或音箱时将启用空间音频。")
        }
    }

    private var subtitleSection: some View {
        Section {
            Toggle("自动加载字幕", isOn: $viewModel.subtitleAutoLoad)

            HStack {
                Text("字幕大小")
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
                Text("한국어").tag("ko")
            }

            ColorPicker("文字颜色", selection: Binding(
                get: { viewModel.subtitleTextColor },
                set: { viewModel.subtitleTextColor = $0 }
            ))

            ColorPicker("背景颜色", selection: Binding(
                get: { viewModel.subtitleBackgroundColor },
                set: { viewModel.subtitleBackgroundColor = $0 }
            ), supportsOpacity: true)

            Picker("字幕位置", selection: $viewModel.subtitlePositionRaw) {
                Text("顶部").tag(SubtitleStyle.SubtitlePosition.top.rawValue)
                Text("底部").tag(SubtitleStyle.SubtitlePosition.bottom.rawValue)
            }

            Toggle("启用 OpenSubtitles", isOn: $viewModel.openSubtitlesEnabled)

            if viewModel.openSubtitlesEnabled {
                TextField("OpenSubtitles API Key", text: $viewModel.openSubtitlesAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("用户名", text: $viewModel.openSubtitlesUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("密码", text: $viewModel.openSubtitlesPassword)

                HStack {
                    Button("保存配置") {
                        viewModel.saveOpenSubtitlesCredentials()
                    }

                    Spacer()

                    Button {
                        Task { await viewModel.testOpenSubtitlesLogin() }
                    } label: {
                        if viewModel.isTestingOpenSubtitles {
                            ProgressView()
                        } else {
                            Text("测试登录")
                        }
                    }
                    .disabled(viewModel.isTestingOpenSubtitles)
                }

                Button("清除 OpenSubtitles 配置", role: .destructive) {
                    viewModel.clearOpenSubtitlesCredentials()
                }

                if let message = viewModel.openSubtitlesStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("字幕", systemImage: "captions.bubble")
        } footer: {
            Text("字幕外观为全局默认值，进入播放器后仍可临时调整。OpenSubtitles 搜索使用官方 REST API；下载需要账户额度，API Key、用户名和密码会保存在 Keychain。")
        }
    }

    private var librarySection: some View {
        Section {
            Toggle("自动扫描新文件", isOn: $viewModel.libraryAutoScan)
            Toggle("显示未观看标记", isOn: $viewModel.showUnwatchedBadge)
        } header: {
            Label("媒体库", systemImage: "film.stack")
        }
    }

    private var metadataSection: some View {
        Section {
            Toggle("自动从媒体服务器下载元数据", isOn: $viewModel.metadataAutoDownload)

            HStack {
                Text("元数据缓存大小")
                Spacer()
                Text(viewModel.metadataCacheSize)
                    .foregroundStyle(.secondary)
            }

            Button("删除所有元数据缓存") {
                viewModel.showClearMetadataCacheAlert = true
            }
            .foregroundStyle(.red)
        } header: {
            Label("元数据", systemImage: "photo.on.rectangle.angled")
        } footer: {
            Text("仅 Emby、Jellyfin、Plex 媒体条目支持元数据刷新。关闭自动下载后，仍可在详情页通过「更多 → 刷新」手动更新。")
        }
    }

    private var appearanceSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.appearance) {
                HStack(spacing: 12) {
                    ThemeSwatch(theme: viewModel.theme)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("配色主题")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(viewModel.theme.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("外观", systemImage: "paintbrush")
        }
    }

    private var storageSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.downloads) {
                Label("下载管理", systemImage: "arrow.down.circle")
            }

            HStack {
                Text("缓存大小")
                Spacer()
                Text(viewModel.cacheSize)
                    .foregroundStyle(.secondary)
            }

            Button("清除缓存") {
                viewModel.showClearCacheAlert = true
            }
            .foregroundStyle(.red)
        } header: {
            Label("存储", systemImage: "internaldrive")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(.secondary)
            }

            Button("重置所有设置") {
                viewModel.showResetAlert = true
            }
            .foregroundStyle(.red)
        } header: {
            Label("关于", systemImage: "info.circle")
        }
    }
}

// MARK: - Downloads

struct DownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.editMode) private var editMode
    @State private var selection: Set<UUID> = []
    @State private var isChoosingDirectory = false
    @State private var deleteConfirmation = false
    @State private var directoryError: String?

    var body: some View {
        List(selection: $selection) {
            directorySection
            tasksSection
        }
        .navigationTitle("下载")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            if editMode?.wrappedValue.isEditing == true, !selection.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button("删除所选", role: .destructive) {
                        deleteConfirmation = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isChoosingDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                try downloadManager.setCustomDirectory(url)
            } catch {
                directoryError = error.localizedDescription
            }
        }
        .confirmationDialog("删除选中的下载？", isPresented: $deleteConfirmation) {
            Button("删除文件和记录", role: .destructive) {
                Task {
                    await downloadManager.delete(selection)
                    selection.removeAll()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("无法修改下载目录", isPresented: Binding(
            get: { directoryError != nil },
            set: { if !$0 { directoryError = nil } }
        )) {
            Button("确定") {}
        } message: {
            Text(directoryError ?? "")
        }
    }

    private var directorySection: some View {
        Section("下载位置") {
            LabeledContent("当前目录", value: downloadManager.destination.rootPath)
            Button("选择文件夹") {
                isChoosingDirectory = true
            }
            Button("恢复默认位置") {
                downloadManager.useDefaultDirectory()
            }
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        Section("下载项目") {
            if downloadManager.tasks.isEmpty {
                ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle")
            } else {
                ForEach(downloadManager.tasks) { task in
                    DownloadTaskRow(task: task) {
                        play(task)
                    } retry: {
                        Task { await downloadManager.retry(task.id) }
                    }
                }
            }
        }
    }

    private func play(_ task: DownloadTaskSnapshot) {
        guard task.status == .completed,
              let url = try? downloadManager.completedFileURL(for: task.id),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
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
}

private struct DownloadTaskRow: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    let task: DownloadTaskSnapshot
    let play: () -> Void
    let retry: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.request.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        if let detailText {
                            Text(detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    statusView
                }
                if task.status == .downloading || task.status == .queued {
                    ProgressView(value: task.totalBytes > 0 ? task.progress : nil)
                }
                if let errorMessage = task.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(task.status != .completed)
        .swipeActions {
            if task.status == .failed {
                Button("重新下载", action: retry)
                    .tint(.blue)
            }
        }
        .contextMenu {
            if task.status == .completed,
               let url = try? downloadManager.completedFileURL(for: task.id) {
                ShareLink(item: url) {
                    Label("文件操作", systemImage: "square.and.arrow.up")
                }
            }
            if task.status == .failed {
                Button(action: retry) {
                    Label("重新下载", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var detailText: String? {
        if let season = task.request.seasonNumber, let episode = task.request.episodeNumber {
            return "第 \(season) 季 · 第 \(episode) 集 · \(task.request.episodeTitle ?? "")"
        }
        if task.totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
        }
        return nil
    }

    @ViewBuilder
    private var statusView: some View {
        switch task.status {
        case .queued:
            Text("等待中").foregroundStyle(.secondary)
        case .downloading:
            Text("\(Int(task.progress * 100))%").foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - Theme Picker

/// 设置页中的外观主题选择网格。
/// 每个卡片以一张缩略卡片预览该主题下 background / surface / primary 三色搭配。
///
/// 使用手写的 `VStack + HStack` 而非 `LazyVGrid`：
/// `LazyVGrid` 嵌入在 `Form` 的 `Section` row 内时，由于 row 不是滚动上下文，
/// lazy 容器的纵向 spacing 经常算不准，会导致两行卡片视觉上重叠。
struct ThemePickerGrid: View {
    @Binding var selection: ColorTheme

    private let columnCount = 2
    private let rowSpacing: CGFloat = 12
    private let columnSpacing: CGFloat = 12

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: columnSpacing) {
                    ForEach(rows[rowIndex], id: \.self) { theme in
                        cell(for: theme)
                    }

                    let missing = columnCount - rows[rowIndex].count
                    if missing > 0 {
                        ForEach(0..<missing, id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private var rows: [[ColorTheme]] {
        let all = ColorTheme.allCases
        return stride(from: 0, to: all.count, by: columnCount).map { start in
            Array(all[start..<min(start + columnCount, all.count)])
        }
    }

    private func cell(for theme: ColorTheme) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = theme
            }
        } label: {
            ThemePreviewCard(
                theme: theme,
                isSelected: selection == theme
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// 单个主题的预览卡片：展示主色 / 背景 / 卡片三色搭配。
struct ThemePreviewCard: View {
    let theme: ColorTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            previewCanvas
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    selectionBadge
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(theme.displayName)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(theme.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? theme.primary : Color.clear,
                    lineWidth: 2
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 仿照真实 App 缩影：背景 + 一张 surface 卡片 + primary 高亮按钮 + 文本占位条。
    private var previewCanvas: some View {
        ZStack(alignment: .topLeading) {
            theme.background

            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(theme.primary.opacity(0.85))
                    .frame(width: 28, height: 5)

                Capsule()
                    .fill(theme.primary.opacity(0.45))
                    .frame(width: 44, height: 4)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.surface)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .fill(theme.primary)
                                .frame(width: 11, height: 11)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Capsule()
                            .fill(theme.primary.opacity(0.7))
                            .frame(width: 38, height: 4)
                        Capsule()
                            .fill(theme.primary.opacity(0.35))
                            .frame(width: 24, height: 3)
                    }

                    Spacer(minLength: 0)

                    Capsule()
                        .fill(theme.primary)
                        .frame(width: 18, height: 10)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(theme.primary)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(CloudSyncCoordinator.shared)
    .preferredColorScheme(.dark)
}

// MARK: - Appearance 二级页

/// 外观（配色主题）独立设置页。
/// 进入该页后切换主题不会影响 `SettingsView` 在导航栈中的位置——
/// `NavigationStack` 的 path 由 `AppState.settingsPath` 持有，跨
/// `.id(theme)` 触发的 `ContentView` 重建依然保留。
struct AppearanceSettingsView: View {
    @AppStorage(ColorTheme.storageKey) private var theme: ColorTheme = .system

    var body: some View {
        Form {
            Section {
                ThemePickerGrid(selection: $theme)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } footer: {
                Text(theme.subtitle)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.vanmoBackground)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 主题色块（设置入口的右侧 trailing 缩略图）

/// 设置主页面「外观」入口右侧的迷你色块，用三色拼贴展示当前主题。
struct ThemeSwatch: View {
    let theme: ColorTheme

    var body: some View {
        HStack(spacing: 0) {
            theme.background
            theme.surface
            theme.primary
        }
        .frame(width: 36, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        }
    }
}

#Preview("Appearance") {
    NavigationStack {
        AppearanceSettingsView()
    }
}
