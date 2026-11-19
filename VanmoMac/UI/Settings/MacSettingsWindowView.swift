import AppKit
import SwiftUI
import VanmoCore

enum MacSettingsTab: String, CaseIterable, Identifiable {
    case generalAndSync
    case playback
    case subtitles
    case appearance
    case cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalAndSync: L10n.tr("通用与同步")
        case .playback: L10n.tr("播放")
        case .subtitles: L10n.tr("字幕")
        case .appearance: L10n.tr("外观")
        case .cache: L10n.tr("缓存")
        }
    }

    var activeIconAssetName: String {
        switch self {
        case .generalAndSync: "MacPrefCloudActive"
        case .playback: "MacPrefFilmActive"
        case .subtitles: "MacPrefSubTailActive"
        case .appearance: "MacPrefThemeNight"
        case .cache: "MacPrefCacheActive"
        }
    }

    var inactiveIconAssetName: String {
        switch self {
        case .generalAndSync: "MacPrefCloudCat"
        case .playback: "MacPrefFilmCat"
        case .subtitles: "MacPrefSubTail"
        case .appearance: "MacPrefMoonInactive"
        case .cache: "MacPrefCacheCat"
        }
    }
}

struct MacSettingsWindowView: View {
    @StateObject private var viewModel = MacSettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: MacSettingsTab
    @State private var showLanguageRestartAlert = false

    init(initialTab: MacSettingsTab = .appearance) {
        _selectedTab = State(initialValue: initialTab)
    }

    private var isDark: Bool {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme)
    }

    private var theme: MacThemeColors {
        isDark ? .dark : .light
    }

    private var canvasBackground: Color {
        isDark
            ? Color(red: 11 / 255, green: 12 / 255, blue: 14 / 255) // #0B0C0E
            : theme.appBackground
    }

    private var toolbarBackground: Color {
        isDark
            ? Color(red: 23 / 255, green: 25 / 255, blue: 30 / 255).opacity(0.85)
            : theme.sidebarBackground
    }

    var body: some View {
        ZStack {
            canvasBackground
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                preferencesToolbar
                Rectangle()
                    .fill(isDark ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.14) : theme.strokeGlass)
                    .frame(height: 1)

                tabBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .frame(
            width: MacDesignTokens.Layout.settingsWindowWidth,
            height: MacDesignTokens.Layout.settingsWindowHeight
        )
        .background {
            MacSettingsWindowAccessor(appearanceMode: appState.appearanceMode, isDark: isDark)
        }
        .macTheme(theme)
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
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

    // MARK: - Top Toolbar (5 Tabs, 76px Immersive Header)

    private var preferencesToolbar: some View {
        HStack(spacing: 6) {
            ForEach(MacSettingsTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        tabIcon(for: tab, isSelected: isSelected)
                            .frame(width: 20, height: 20)

                        Text(tab.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        isSelected ? theme.amberTintFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.9)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 532)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(height: 76)
        .background(toolbarBackground)
    }

    @ViewBuilder
    private func tabIcon(for tab: MacSettingsTab, isSelected: Bool) -> some View {
        if isSelected {
            if isDark {
                Image(tab.activeIconAssetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(tab.activeIconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(theme.accentAmber)
            }
        } else {
            Image(tab.inactiveIconAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(theme.secondaryText)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selectedTab {
        case .generalAndSync: generalAndSyncPane
        case .playback: playbackPane
        case .subtitles: subtitlesPane
        case .appearance: appearancePane
        case .cache: cachePane
        }
    }

    // MARK: - 1. General & Sync (Figma 182:1121)

    private var generalAndSyncPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Section: ICLOUD SYNC
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("iCloud 同步"), uppercase: false)

                    ZStack(alignment: .bottomTrailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.tr("iCloud 同步"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)

                                    Text(L10n.tr("通过 CloudKit 同步服务器配置、播放进度、收藏和文件夹书签。密码与 OAuth 凭据保存在本机 Keychain。"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.secondaryText)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if !CloudSyncAvailability.isCloudKitEnabled {
                                        Text(CloudSyncAvailability.unavailableMessage)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(theme.dangerRed)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle(L10n.tr("iCloud 同步"), isOn: Binding(
                                    get: { viewModel.cloudSyncEnabled },
                                    set: { viewModel.updateCloudSyncEnabled($0, coordinator: cloudSyncCoordinator) }
                                ))
                                .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                                .disabled(!CloudSyncAvailability.isCloudKitEnabled)
                            }

                            cardDivider

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(L10n.tr("上次同步"))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer()
                                    Text(viewModel.cloudSyncLastUpdatedText)
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.secondaryText)
                                }

                                Text(viewModel.cloudSyncStatusMessage ?? cloudSyncCoordinator.statusMessage ?? "iCloud.com.vanmo.app")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.tertiaryText)
                                    .lineLimit(1)
                            }
                            .padding(.trailing, 54)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 140, alignment: .top)
                        .macCatGlassCard(theme: theme, cornerRadius: 16)

                        Image("MacPrefCurledSyncCircle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .padding(.trailing, 13)
                            .padding(.bottom, 11)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                // Section: LIBRARY & STORAGE
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("媒体库与存储"))

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(L10n.tr("自动扫描新文件"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            Toggle(L10n.tr("自动扫描新文件"), isOn: $viewModel.libraryAutoScan)
                                .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                        }

                        cardDivider

                        HStack(spacing: 12) {
                            Text(L10n.tr("下载位置"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Spacer(minLength: 16)
                            Text(downloadManager.destination.rootPath)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack(spacing: 8) {
                            prefGlassPillButton(L10n.tr("下载管理")) {
                                openWindow(id: "downloads")
                            }
                            prefGlassPillButton(L10n.tr("选择下载目录"), action: chooseDownloadDirectory)
                            prefGlassPillButton(L10n.tr("恢复默认目录")) {
                                downloadManager.useDefaultDirectory()
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 11)
                    .padding(.bottom, 12)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }

                // Section: ABOUT
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("关于"))

                    HStack {
                        HStack(spacing: 12) {
                            Text(L10n.tr("版本"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Text(viewModel.appVersion)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                        Spacer()
                        Button(L10n.tr("重置所有设置")) {
                            viewModel.showResetAlert = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.dangerRed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 2. Playback (Figma 185:1143)

    private var playbackPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Section: PLAYBACK CONTROLS
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("播放控制"))

                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.tr("自动播放下一集"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Spacer()
                                Toggle(L10n.tr("自动播放下一集"), isOn: $viewModel.autoPlayNext)
                                    .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                            }

                            cardDivider

                            HStack {
                                Text(L10n.tr("断点续播"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Spacer()
                                Toggle(L10n.tr("断点续播"), isOn: $viewModel.resumePlayback)
                                    .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                            }

                            cardDivider

                            HStack {
                                Text(L10n.tr("硬件解码优先"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Spacer()
                                Toggle(L10n.tr("硬件解码优先"), isOn: $viewModel.hardwareDecoding)
                                    .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                            }

                            cardDivider

                            HStack {
                                HStack(spacing: 8) {
                                    Text(L10n.tr("默认播放速度"))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                    Text("0.5x – 2.0x")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(theme.tertiaryText)
                                }

                                Spacer()

                                Menu {
                                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                        Button {
                                            viewModel.defaultRate = rate
                                        } label: {
                                            HStack {
                                                Text(MacFormatters.playbackRate(rate))
                                                if viewModel.defaultRate == rate {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("\(MacFormatters.playbackRate(viewModel.defaultRate))  ▾")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .padding(.leading, 12)
                                .padding(.trailing, 10)
                                .frame(height: 30)
                                .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                                }
                                .fixedSize()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .macCatGlassCard(theme: theme, cornerRadius: 16)
                        .padding(.top, 14)

                        Image("MacPrefCardTopRightResting")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 40)
                            .offset(x: -24, y: -13)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                // Section: AUDIO OUTPUT
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("音频输出"))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("输出模式"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)

                            Spacer()

                            Menu {
                                ForEach(AudioOutputMode.allCases, id: \.self) { mode in
                                    Button {
                                        viewModel.audioOutputMode = mode
                                    } label: {
                                        HStack {
                                            Text(mode.displayName)
                                            if viewModel.audioOutputMode == mode {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Text("\(viewModel.audioOutputMode.displayName)  ▾")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.leading, 12)
                            .padding(.trailing, 10)
                            .frame(height: 30)
                            .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                            }
                            .fixedSize()
                        }

                        cardDivider

                        Text(L10n.tr("「自动」根据当前输出设备自动选择最佳音频模式。连接支持杜比的耳机或音箱时将启用空间音频。"))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 13)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 3. Subtitles (Figma 189:1196)

    private var subtitlesPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Section: DEFAULT SUBTITLE BEHAVIOR
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("默认字幕行为"))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.tr("自动加载字幕"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            Toggle(L10n.tr("自动加载字幕"), isOn: $viewModel.subtitleAutoLoad)
                                .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                        }

                        cardDivider

                        HStack {
                            Text(L10n.tr("首选语言"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)

                            Spacer()

                            Menu {
                                Button { viewModel.subtitlePreferredLanguage = "zh" } label: {
                                    HStack {
                                        Text("中文 / Chinese")
                                        if viewModel.subtitlePreferredLanguage == "zh" { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { viewModel.subtitlePreferredLanguage = "en" } label: {
                                    HStack {
                                        Text("English")
                                        if viewModel.subtitlePreferredLanguage == "en" { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { viewModel.subtitlePreferredLanguage = "ja" } label: {
                                    HStack {
                                        Text("日本語")
                                        if viewModel.subtitlePreferredLanguage == "ja" { Image(systemName: "checkmark") }
                                    }
                                }
                            } label: {
                                Text("\(preferredLanguageDisplay)  ▾")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.leading, 12)
                            .padding(.trailing, 10)
                            .frame(height: 30)
                            .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                            }
                            .fixedSize()
                        }

                        cardDivider

                        HStack {
                            Text(L10n.tr("字幕位置"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)

                            Spacer()

                            HStack(spacing: 3) {
                                ForEach([MacSubtitlePosition.bottom, .top]) { pos in
                                    let isSelected = viewModel.subtitlePosition == pos
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            viewModel.subtitlePosition = pos
                                        }
                                    } label: {
                                        Text(pos.title)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                                            .padding(.horizontal, 14)
                                            .frame(height: 24)
                                            .background(
                                                isSelected ? theme.amberTintFill : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                            )
                                            .overlay {
                                                if isSelected {
                                                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                                        .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }
                            .padding(3)
                            .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.strokeGlass, lineWidth: 0.75)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }

                // Section: SUBTITLE APPEARANCE
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        sectionLabel(L10n.tr("字幕外观"))
                        Spacer()
                        Image("MacPrefTailAccent")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 12)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 28) {
                            amberSliderControl(
                                title: L10n.tr("字幕大小"),
                                valueText: "\(Int(viewModel.subtitleFontSize)) pt",
                                value: $viewModel.subtitleFontSize,
                                range: 12...36,
                                step: 1
                            )

                            textColorSwatchesControl
                        }

                        cardDivider

                        amberSliderControl(
                            title: L10n.tr("背景透明度"),
                            valueText: "\(Int((viewModel.subtitleBackgroundOpacity * 100).rounded()))%",
                            value: Binding(
                                get: { viewModel.subtitleBackgroundOpacity },
                                set: { viewModel.subtitleBackgroundOpacity = $0 }
                            ),
                            range: 0...1,
                            step: 0.05
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    private var preferredLanguageDisplay: String {
        switch viewModel.subtitlePreferredLanguage {
        case "zh": return "中文 / Chinese"
        case "en": return "English"
        case "ja": return "日本語"
        default: return viewModel.subtitlePreferredLanguage
        }
    }

    // MARK: - 4. Appearance (Figma 173:1151)

    private var appearancePane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                liveSubtitlePreviewTray
                themeCardsRow
                subtitleAndLanguageControlsCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    private var liveSubtitlePreviewTray: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("实时字幕预览").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accentAmber)

                    Text(L10n.tr("外观与默认字幕样式"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.primaryText)

                    Text(L10n.tr("在 16:9 影院场景上实时预览字幕字号、文字颜色和背景透明度。"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.secondaryText)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .bottom) {
                    Image("MacSubtitlePreviewScene")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 244, height: 136)
                        .clipped()

                    LinearGradient(
                        colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 62)

                    Text(L10n.tr("黑猫影院 · 00:42:18"))
                        .font(.system(size: max(9, min(16, viewModel.subtitleFontSize * 0.56)), weight: .semibold))
                        .foregroundStyle(viewModel.subtitleTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(viewModel.subtitleBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.bottom, 12)
                }
                .frame(width: 244, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 11)
            .frame(height: 158)
            .macCatGlassCard(theme: theme, cornerRadius: 16)

            Image("MacPrefSubtitleWatcher")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 34)
                .offset(x: -24, y: -17)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.top, 10)
    }

    private var themeCardsRow: some View {
        HStack(spacing: 14) {
            themeModeCard(
                mode: .system,
                title: L10n.tr("跟随系统"),
                subtitle: L10n.tr("自动日夜切换"),
                iconName: "MacPrefThemeSystem",
                cardBg: theme.surfaceGlass,
                titleColor: theme.primaryText,
                subtitleColor: theme.secondaryText,
                templateColor: theme.primaryText
            )

            themeModeCard(
                mode: .light,
                title: L10n.tr("日间模式"),
                subtitle: L10n.tr("暖燕麦色"),
                iconName: "MacPrefThemeDay",
                cardBg: Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255),
                titleColor: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255),
                subtitleColor: Color(red: 0x6B / 255, green: 0x68 / 255, blue: 0x60 / 255),
                templateColor: nil
            )

            themeModeCard(
                mode: .dark,
                title: L10n.tr("夜间模式"),
                subtitle: L10n.tr("曜石黑猫玻璃"),
                iconName: "MacPrefThemeNight",
                cardBg: Color(red: 0x12 / 255, green: 0x13 / 255, blue: 0x16 / 255),
                titleColor: MacDesignTokens.glowAmber,
                subtitleColor: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
                templateColor: nil
            )
        }
    }

    private func themeModeCard(
        mode: MacAppearanceMode,
        title: String,
        subtitle: String,
        iconName: String,
        cardBg: Color,
        titleColor: Color,
        subtitleColor: Color,
        templateColor: Color?
    ) -> some View {
        let isSelected = viewModel.appearanceMode == mode
        return Button {
            viewModel.appearanceMode = mode
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let templateColor {
                        Image(iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(isSelected ? theme.accentAmber : templateColor)
                    } else {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected && mode == .system ? theme.accentAmber : titleColor)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(subtitleColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.strokeAmber : (mode == .light ? Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255) : theme.strokeGlass),
                        lineWidth: isSelected ? 1.25 : 0.9
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitleAndLanguageControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                amberSliderControl(
                    title: L10n.tr("字幕大小"),
                    valueText: "\(Int(viewModel.subtitleFontSize)) pt",
                    value: $viewModel.subtitleFontSize,
                    range: 12...36,
                    step: 1
                )

                textColorSwatchesControl
            }

            cardDivider

            HStack(spacing: 28) {
                amberSliderControl(
                    title: L10n.tr("背景透明度"),
                    valueText: "\(Int((viewModel.subtitleBackgroundOpacity * 100).rounded()))%",
                    value: Binding(
                        get: { viewModel.subtitleBackgroundOpacity },
                        set: { viewModel.subtitleBackgroundOpacity = $0 }
                    ),
                    range: 0...1,
                    step: 0.05
                )

                appLanguageControl
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .macCatGlassCard(theme: theme, cornerRadius: 16)
    }

    // MARK: - 5. Cache (Figma 186:1177)

    private var cachePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("缓存管理"))

                    HStack {
                        HStack(spacing: 12) {
                            Text(L10n.tr("缓存大小"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Text(viewModel.cacheSize)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()

                        Button(L10n.tr("清除缓存")) {
                            viewModel.showClearCacheAlert = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.dangerRed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("元数据"))

                    VStack(alignment: .leading, spacing: 11) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.tr("自动从媒体服务器下载元数据"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)

                                Text(L10n.tr("仅 Emby、Jellyfin、Plex 媒体条目支持元数据刷新。关闭自动下载后，仍可在详情页手动更新。"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Toggle(L10n.tr("自动从媒体服务器下载元数据"), isOn: $viewModel.metadataAutoDownload)
                                .toggleStyle(MacCatAmberToggleStyle(theme: theme))
                        }

                        cardDivider

                        HStack {
                            HStack(spacing: 12) {
                                Text(L10n.tr("元数据缓存大小"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Text(viewModel.metadataCacheSize)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer()

                            Button(L10n.tr("删除所有元数据缓存")) {
                                viewModel.showClearMetadataCacheAlert = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.dangerRed)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .macCatGlassCard(theme: theme, cornerRadius: 16)
                }
            }

            Spacer(minLength: 10)

            HStack {
                Spacer()
                Image("MacPrefBattingYarnBall")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116, height: 62)
                Spacer()
            }
            .padding(.bottom, 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - Shared Controls

    private func sectionLabel(_ title: String, uppercase: Bool = true) -> some View {
        Text(uppercase ? title.uppercased() : title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
    }

    private func prefGlassPillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(theme.surfacePill, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                }
        }
        .buttonStyle(.plain)
    }

    private func amberSliderControl(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let fraction = min(max((value.wrappedValue - range.lowerBound) / span, 0), 1)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(valueText)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.accentAmber)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let fillWidth = max(4, width * fraction)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.progressTrack)
                        .frame(height: 3)

                    Capsule()
                        .fill(MacDesignTokens.glowAmber)
                        .frame(width: fillWidth, height: 3)

                    MacPawDotIndicator(size: 10, useCinemaGlow: true)
                        .offset(x: min(max(fillWidth - 5, 0), max(0, width - 10)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let ratio = min(max(drag.location.x / width, 0), 1)
                            let raw = range.lowerBound + ratio * span
                            let snapped = (raw / step).rounded() * step
                            value.wrappedValue = min(max(snapped, range.lowerBound), range.upperBound)
                        }
                )
            }
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value.wrappedValue = min(value.wrappedValue + step, range.upperBound)
            case .decrement:
                value.wrappedValue = max(value.wrappedValue - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private var textColorSwatchesControl: some View {
        let swatches: [(hex: String, color: Color, name: String)] = [
            ("#FFFFFFFF", .white, L10n.tr("白色")),
            ("#FFB547FF", MacDesignTokens.glowAmber, L10n.tr("琥珀金")),
            ("#7DD3FCFF", Color(red: 0x7D / 255, green: 0xD3 / 255, blue: 0xFC / 255), L10n.tr("天蓝")),
            ("#A8A59EFF", Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255), L10n.tr("浅灰")),
        ]

        return HStack {
            Text(L10n.tr("文字颜色"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Spacer()

            HStack(spacing: 9) {
                ForEach(swatches, id: \.hex) { swatch in
                    let isSelected = viewModel.subtitleTextColorHex.uppercased() == swatch.hex
                    Button {
                        viewModel.subtitleTextColorHex = swatch.hex
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        isSelected ? theme.accentAmber : theme.strokeGlass,
                                        lineWidth: isSelected ? 2 : 0.9
                                    )
                            }
                            .shadow(color: isSelected ? MacDesignTokens.glowAmber.opacity(0.45) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var appLanguageControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tr("语言"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("中文 / English / Follow System")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer()

            Menu {
                ForEach(AppLanguagePreference.allCases, id: \.self) { preference in
                    Button {
                        if preference != viewModel.languagePreference {
                            viewModel.languagePreference = preference
                            showLanguageRestartAlert = true
                        }
                    } label: {
                        HStack {
                            Text(preference.displayName)
                            if viewModel.languagePreference == preference {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(viewModel.languagePreference.displayName)  ▾")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(theme.strokeSubtle)
            .frame(height: 0.75)
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

// MARK: - Custom Amber Toggle Style (38×22 Figma Control)

private struct MacCatAmberToggleStyle: ToggleStyle {
    let theme: MacThemeColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            if reduceMotion {
                configuration.isOn.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    configuration.isOn.toggle()
                }
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? MacDesignTokens.glowAmber : theme.surfacePill)
                    .frame(width: 38, height: 22)
                    .overlay {
                        if !configuration.isOn {
                            Capsule()
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                        }
                    }

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

// MARK: - Immersive NSWindow Configuration (Eliminates Top White Bar)

private struct MacSettingsWindowAccessor: NSViewRepresentable {
    let appearanceMode: MacAppearanceMode
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        let coordinator = context.coordinator
        view.onWindowAttached = { window in
            coordinator.configureIfNeeded(window: window, appearanceMode: appearanceMode, isDark: isDark)
        }
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        let coordinator = context.coordinator
        view.onWindowAttached = { window in
            coordinator.configureIfNeeded(window: window, appearanceMode: appearanceMode, isDark: isDark)
        }
        coordinator.configureIfNeeded(window: view.window, appearanceMode: appearanceMode, isDark: isDark)
    }

    final class HostView: NSView {
        var onWindowAttached: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowAttached?(window)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onWindowAttached?(self.window)
            }
        }
    }

    final class Coordinator {
        private var configuredWindowID: ObjectIdentifier?
        private var lastAppearanceMode: MacAppearanceMode?
        private var lastIsDark: Bool?

        func configureIfNeeded(window: NSWindow?, appearanceMode: MacAppearanceMode, isDark: Bool) {
            guard let window else { return }
            let windowID = ObjectIdentifier(window)
            let isNewWindow = configuredWindowID != windowID
            let appearanceChanged = lastAppearanceMode != appearanceMode || lastIsDark != isDark
            guard isNewWindow || appearanceChanged else { return }

            configuredWindowID = windowID
            lastAppearanceMode = appearanceMode
            lastIsDark = isDark

            if isNewWindow {
                if !window.styleMask.contains(.fullSizeContentView) {
                    window.styleMask.insert(.fullSizeContentView)
                }
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.titlebarSeparatorStyle = .none
                window.toolbar = nil
                window.isMovableByWindowBackground = true
            }

            window.backgroundColor = isDark
                ? NSColor(red: 11 / 255, green: 12 / 255, blue: 14 / 255, alpha: 1)
                : NSColor(red: 250 / 255, green: 247 / 255, blue: 242 / 255, alpha: 1)

            switch appearanceMode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}

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

#Preview("Settings General") {
    MacSettingsWindowView(initialTab: .generalAndSync)
        .environmentObject(CloudSyncCoordinator.shared)
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .frame(width: 720, height: 540)
}
