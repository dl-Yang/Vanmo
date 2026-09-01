import AppKit
import SwiftUI
import VanmoCore

/// 设置窗口侧边栏中的设置项。
enum MacSettingsPane: String, CaseIterable, Identifiable {
    case playback
    case audio
    case subtitles
    case cloudSync
    case library
    case metadata
    case appearance
    case storage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playback: L10n.tr("播放")
        case .audio: L10n.tr("音频")
        case .subtitles: L10n.tr("字幕")
        case .cloudSync: L10n.tr("iCloud 同步")
        case .library: L10n.tr("媒体库")
        case .metadata: L10n.tr("元数据")
        case .appearance: L10n.tr("外观")
        case .storage: L10n.tr("存储")
        case .about: L10n.tr("关于")
        }
    }

    var systemImage: String {
        switch self {
        case .playback: "play.circle"
        case .audio: "hifispeaker.2"
        case .subtitles: "captions.bubble"
        case .cloudSync: "icloud"
        case .library: "film.stack"
        case .metadata: "photo.on.rectangle.angled"
        case .appearance: "paintbrush"
        case .storage: "internaldrive"
        case .about: "info.circle"
        }
    }
}

/// 设置窗口侧边栏的分组。
enum MacSettingsPaneGroup: String, CaseIterable, Identifiable {
    case playback
    case dataAndSync
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playback: L10n.tr("播放").uppercased()
        case .dataAndSync: L10n.tr("数据与同步").uppercased()
        case .general: L10n.tr("通用").uppercased()
        }
    }

    var panes: [MacSettingsPane] {
        switch self {
        case .playback: [.playback, .audio, .subtitles]
        case .dataAndSync: [.cloudSync, .library, .metadata]
        case .general: [.appearance, .storage, .about]
        }
    }
}

/// 设置独立窗口：左侧为设置项侧边栏，右侧为对应设置内容。
struct MacSettingsWindowView: View {
    @StateObject private var viewModel = MacSettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedPane: MacSettingsPane? = .playback
    @State private var showLanguageRestartAlert = false

//    private var isDark: Bool {
//        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme)
//    }

    private var theme: MacThemeColors {
        .light
    }

    private var currentPane: MacSettingsPane {
        selectedPane ?? .playback
    }

    private var paneSelection: Binding<MacSettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { pane in
                guard let pane else { return }
                selectedPane = pane
            }
        )
    }

    var body: some View {
        settingsLayout
            .macTheme(theme)
            .task {
                viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
                async let cacheSize: Void = viewModel.calculateCacheSize()
                async let metadataSize: Void = viewModel.calculateMetadataCacheSize()
                _ = await (cacheSize, metadataSize)
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
            .modifier(MacSettingsAlertModifier(viewModel: viewModel, appState: appState, colorScheme: colorScheme))
            .alert(L10n.tr("语言"), isPresented: $showLanguageRestartAlert) {
                Button(L10n.tr("确定"), role: .cancel) {}
            } message: {
                Text(L10n.tr("语言将在下次启动后生效"))
            }
    }

    private var settingsLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            settingsSidebar
        } detail: {
            contentPane
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar(.hidden)
        .background {
            MacVibrancyBackground(isDark: false, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - 侧边栏

    private var settingsSidebar: some View {
        List(selection: paneSelection) {
            ForEach(MacSettingsPaneGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.panes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationSplitViewColumnWidth(MacDesignTokens.Layout.settingsSidebarWidth)
    }

    // MARK: - 内容区域

    private var contentPane: some View {
        ZStack {
            theme.appBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(currentPane.title)
                    .font(MacDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
                    .padding(.top, MacDesignTokens.Layout.contentPadding)

                Form {
                    paneContent
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .controlSize(.regular)
                .toggleStyle(.switch)
                .frame(maxWidth: MacDesignTokens.Layout.settingsContentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch currentPane {
        case .playback: playbackPane
        case .audio: audioPane
        case .subtitles: subtitlePane
        case .cloudSync: cloudSyncPane
        case .library: libraryPane
        case .metadata: metadataPane
        case .appearance: appearancePane
        case .storage: storagePane
        case .about: aboutPane
        }
    }

    private var cloudSyncPane: some View {
        settingsCard {
            Toggle(L10n.tr("iCloud 同步"), isOn: Binding(
                get: { viewModel.cloudSyncEnabled },
                set: { viewModel.updateCloudSyncEnabled($0, coordinator: cloudSyncCoordinator) }
            ))
            .disabled(!CloudSyncAvailability.isCloudKitEnabled)

            if !CloudSyncAvailability.isCloudKitEnabled {
                Text(CloudSyncAvailability.unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            settingsRow(label: L10n.tr("上次同步"), value: viewModel.cloudSyncLastUpdatedText)

            if let message = viewModel.cloudSyncStatusMessage ?? cloudSyncCoordinator.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Text(L10n.tr("通过 CloudKit 同步服务器配置、播放进度、收藏和文件夹书签。密码与 OAuth 凭据保存在本机 Keychain。"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var playbackPane: some View {
        settingsCard {
            Toggle(L10n.tr("自动播放下一集"), isOn: $viewModel.autoPlayNext)
            Toggle(L10n.tr("断点续播"), isOn: $viewModel.resumePlayback)
            Toggle(L10n.tr("硬件解码优先"), isOn: $viewModel.hardwareDecoding)

            HStack {
                Text(L10n.tr("默认播放速度"))
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

    private var audioPane: some View {
        settingsCard {
            Picker(L10n.tr("输出模式"), selection: $viewModel.audioOutputMode) {
                ForEach(AudioOutputMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }

            Text(L10n.tr("「自动」根据当前输出设备自动选择最佳音频模式。连接支持杜比的耳机或音箱时将启用空间音频。"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var subtitlePane: some View {
        settingsCard {
            Toggle(L10n.tr("自动加载字幕"), isOn: $viewModel.subtitleAutoLoad)

            HStack {
                Text(L10n.tr("字幕大小"))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Stepper(
                    "\(Int(viewModel.subtitleFontSize))pt",
                    value: $viewModel.subtitleFontSize,
                    in: 12...36,
                    step: 2
                )
            }

            Picker(L10n.tr("首选语言"), selection: $viewModel.subtitlePreferredLanguage) {
                Text(L10n.tr("中文")).tag("zh")
                Text("English").tag("en")
                Text("日本語").tag("ja")
            }

            Picker(L10n.tr("字幕位置"), selection: $viewModel.subtitlePosition) {
                ForEach(MacSubtitlePosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            }

            ColorPicker(L10n.tr("文字颜色"), selection: Binding(
                get: { viewModel.subtitleTextColor },
                set: { viewModel.subtitleTextColor = $0 }
            ))

            ColorPicker(L10n.tr("背景颜色"), selection: Binding(
                get: { viewModel.subtitleBackgroundColor },
                set: { viewModel.subtitleBackgroundColor = $0 }
            ))
        }
    }

    private var libraryPane: some View {
        settingsCard {
            Toggle(L10n.tr("自动扫描新文件"), isOn: $viewModel.libraryAutoScan)
        }
    }

    private var metadataPane: some View {
        settingsCard {
            Toggle(L10n.tr("自动从媒体服务器下载元数据"), isOn: $viewModel.metadataAutoDownload)

            settingsRow(label: L10n.tr("元数据缓存大小"), value: viewModel.metadataCacheSize)

            Button(L10n.tr("删除所有元数据缓存")) {
                viewModel.showClearMetadataCacheAlert = true
            }
            .foregroundStyle(.red)

            Text(L10n.tr("仅 Emby、Jellyfin、Plex 媒体条目支持元数据刷新。关闭自动下载后，仍可在详情页手动更新。"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var appearancePane: some View {
        settingsCard {
            Picker(L10n.tr("主题"), selection: $viewModel.appearanceMode) {
                ForEach(MacAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(L10n.tr("跟随系统时，界面外观随 macOS 系统深浅色自动切换。"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            Picker(L10n.tr("语言"), selection: languageSelection) {
                ForEach(AppLanguagePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }

            Text(L10n.tr("语言将在下次启动后生效"))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var languageSelection: Binding<AppLanguagePreference> {
        Binding(
            get: { viewModel.languagePreference },
            set: { newValue in
                guard newValue != viewModel.languagePreference else { return }
                viewModel.languagePreference = newValue
                showLanguageRestartAlert = true
            }
        )
    }

    private var storagePane: some View {
        settingsCard {
            settingsRow(label: L10n.tr("下载位置"), value: downloadManager.destination.rootPath)

            HStack {
                Button(L10n.tr("下载管理")) {
                    openWindow(id: "downloads")
                }
                Button(L10n.tr("选择下载目录")) {
                    chooseDownloadDirectory()
                }
                Button(L10n.tr("恢复默认目录")) {
                    downloadManager.useDefaultDirectory()
                }
            }

            settingsRow(label: L10n.tr("缓存大小"), value: viewModel.cacheSize)

            Button(L10n.tr("清除缓存")) {
                viewModel.showClearCacheAlert = true
            }
            .foregroundStyle(.red)
        }
    }

    private var aboutPane: some View {
        settingsCard {
            settingsRow(label: L10n.tr("版本"), value: viewModel.appVersion)

            Button(L10n.tr("重置所有设置")) {
                viewModel.showResetAlert = true
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - 通用组件

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        }
    }

    private func settingsRow(label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("选择")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try downloadManager.setCustomDirectory(url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

/// 设置窗口的三个确认弹窗（清缓存 / 删元数据缓存 / 重置设置）。
private struct MacSettingsAlertModifier: ViewModifier {
    @ObservedObject var viewModel: MacSettingsViewModel
    @ObservedObject var appState: MacAppState
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .alert(L10n.tr("清除缓存"), isPresented: $viewModel.showClearCacheAlert) {
                Button(L10n.tr("取消"), role: .cancel) {}
                Button(L10n.tr("清除"), role: .destructive) {
                    Task { await viewModel.clearCache() }
                }
            } message: {
                Text(L10n.tr("确定要清除所有缓存数据吗？这不会删除已下载的文件。"))
            }
            .alert(L10n.tr("删除元数据缓存"), isPresented: $viewModel.showClearMetadataCacheAlert) {
                Button(L10n.tr("取消"), role: .cancel) {}
                Button(L10n.tr("删除"), role: .destructive) {
                    Task { await viewModel.clearMetadataCache() }
                }
            } message: {
                Text(L10n.tr("确定要删除所有元数据缓存吗？已保存的媒体信息不会被删除，但 Logo、演职人员头像和单集封面等缓存图片将被移除。"))
            }
            .alert(L10n.tr("重置设置"), isPresented: $viewModel.showResetAlert) {
                Button(L10n.tr("取消"), role: .cancel) {}
                Button(L10n.tr("重置"), role: .destructive) {
                    viewModel.resetAllSettings()
                    appState.appearanceMode = .system
                    appState.syncAppearance(with: colorScheme)
                    Task {
                        await viewModel.calculateCacheSize()
                        await viewModel.calculateMetadataCacheSize()
                    }
                }
            } message: {
                Text(L10n.tr("确定要重置所有设置为默认值吗？"))
            }
    }
}

#Preview("Settings Window") {
    MacSettingsWindowView()
        .environmentObject(CloudSyncCoordinator.shared)
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .frame(
            width: MacDesignTokens.Layout.settingsWindowWidth,
            height: MacDesignTokens.Layout.settingsWindowHeight
        )
}
