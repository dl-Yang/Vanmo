import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

// MARK: - 共享子页壳体

private struct CatSettingsSubpageShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            HStack {
                CatAmberHalo(width: 180, height: 80, opacity: 0.16)
                    .padding(.top, 20)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CatBackButton(size: 36) { dismiss() }
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    CatStretchingDivider()
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.top, 10)
                .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        content()
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                    .padding(.bottom, 34)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
    }
}

private struct CatSettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(CatDesign.accentAmber)
                .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

// MARK: - iCloud 同步子页

struct ICloudSyncSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("iCloud 同步")) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(
                    title: L10n.tr("启用 iCloud 同步"),
                    isOn: Binding(
                        get: { viewModel.cloudSyncEnabled },
                        set: { viewModel.updateCloudSyncEnabled($0, coordinator: cloudSyncCoordinator) }
                    ),
                    disabled: !CloudSyncAvailability.isCloudKitEnabled
                )

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                HStack {
                    Text(L10n.tr("上次同步"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text(viewModel.cloudSyncLastUpdatedText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
            }
            .catGlassCard(cornerRadius: 20)

            if !CloudSyncAvailability.isCloudKitEnabled {
                Text(CloudSyncAvailability.unavailableMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.dangerRed)
            }

            if let message = viewModel.cloudSyncStatusMessage ?? cloudSyncCoordinator.statusMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.textMuted)
            }

            Text(L10n.tr("通过 CloudKit 同步服务器配置、非 Emby/Plex 播放进度、收藏和文件夹书签。密码与 OAuth 凭据仍保存在本机 Keychain，不会进入 iCloud。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
                .lineSpacing(3)
        }
        .task {
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
    }
}

// MARK: - 播放设置子页

struct PlaybackSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("播放")) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(title: L10n.tr("自动播放下一集"), isOn: $viewModel.autoPlayNext)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)
                CatSettingsToggleRow(title: L10n.tr("断点续播"), isOn: $viewModel.resumePlayback)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)
                CatSettingsToggleRow(title: L10n.tr("硬件解码优先"), isOn: $viewModel.hardwareDecoding)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                HStack {
                    Text(L10n.tr("默认播放速度"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Picker("", selection: $viewModel.defaultRate) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Text("\(rate, specifier: "%.2g")x").tag(rate)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(CatDesign.accentAmber)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
            }
            .catGlassCard(cornerRadius: 20)

            Text(L10n.tr("硬件解码优先仅影响 KSPlayer 播放路径，并在下一次加载视频时生效；如果硬解初始化失败，播放器会自动尝试软解。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
                .lineSpacing(3)
        }
    }
}

// MARK: - 音频设置子页

struct AudioSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("音频")) {
            VStack(spacing: 0) {
                ForEach(Array(AudioOutputMode.allCases.enumerated()), id: \.element) { index, mode in
                    if index > 0 {
                        Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)
                    }
                    let isSelected = viewModel.audioOutputMode == mode
                    Button {
                        viewModel.audioOutputMode = mode
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isSelected ? CatDesign.accentAmber : CatDesign.textMuted)
                                .frame(width: 24)
                            Text(mode.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(CatDesign.textIvory)
                            Spacer()
                            if isSelected {
                                Image("CatPawDot")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                                    .foregroundStyle(CatDesign.accentAmber)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .catGlassCard(cornerRadius: 20)

            Text(L10n.tr("「自动」根据当前输出设备自动选择最佳音频模式。连接支持杜比的耳机或音箱时将启用空间音频。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
                .lineSpacing(3)
        }
    }
}

// MARK: - 字幕与 OpenSubtitles 设置子页

struct SubtitlesSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("字幕")) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(title: L10n.tr("自动加载字幕"), isOn: $viewModel.subtitleAutoLoad)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                HStack {
                    Text(L10n.tr("首选语言"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Picker(L10n.tr("首选语言"), selection: $viewModel.subtitlePreferredLanguage) {
                        Text(L10n.tr("中文")).tag("zh")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                    }
                    .labelsHidden()
                    .tint(CatDesign.accentAmber)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                NavigationLink(value: SettingsRoute.appearance) {
                    HStack {
                        Text(L10n.tr("外观与字体样式"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                        Spacer()
                        Text("\(Int(viewModel.subtitleFontSize))pt · \(viewModel.subtitleOutlineWeight.displayName)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(CatDesign.accentAmber)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CatDesign.textDim)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                }
                .buttonStyle(.plain)
            }
            .catGlassCard(cornerRadius: 20)

            openSubtitlesSection

            Text(L10n.tr("字幕外观为全局默认值，进入播放器后仍可临时调整。OpenSubtitles 搜索使用官方 REST API；下载需要账户额度，API Key、用户名和密码会保存在 Keychain。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
                .lineSpacing(3)
        }
    }

    private var openSubtitlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(title: L10n.tr("启用 OpenSubtitles"), isOn: $viewModel.openSubtitlesEnabled)
            }
            .catGlassCard(cornerRadius: 18)

            if viewModel.openSubtitlesEnabled {
                VStack(spacing: 10) {
                    credentialField("OpenSubtitles API Key", text: $viewModel.openSubtitlesAPIKey)
                    credentialField(L10n.tr("用户名"), text: $viewModel.openSubtitlesUsername)
                    credentialField(L10n.tr("密码"), text: $viewModel.openSubtitlesPassword, isSecure: true)

                    HStack(spacing: 10) {
                        Button(L10n.tr("保存配置")) {
                            viewModel.saveOpenSubtitlesCredentials()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(CatDesign.amberTintFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.85))

                        Button {
                            Task { await viewModel.testOpenSubtitlesLogin() }
                        } label: {
                            if viewModel.isTestingOpenSubtitles {
                                ProgressView().tint(CatDesign.textIvory)
                            } else {
                                Text(L10n.tr("测试登录"))
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill)
                        .disabled(viewModel.isTestingOpenSubtitles)
                    }
                    .buttonStyle(.plain)

                    Button(L10n.tr("清除 OpenSubtitles 配置"), role: .destructive) {
                        viewModel.clearOpenSubtitlesCredentials()
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(CatDesign.dangerRed)
                    .padding(.top, 2)

                    if let message = viewModel.openSubtitlesStatusMessage {
                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                }
                .padding(14)
                .catGlassCard(cornerRadius: 20)
            }
        }
    }

    private func credentialField(_ placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        Group {
            if isSecure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(CatDesign.textDim))
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(CatDesign.textDim))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(CatDesign.textIvory)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(CatDesign.surfacePill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
        )
    }
}

// MARK: - 媒体库与扫描设置子页

struct LibraryScanSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("媒体库与扫描")) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(title: L10n.tr("自动扫描新文件"), isOn: $viewModel.libraryAutoScan)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)
                CatSettingsToggleRow(title: L10n.tr("显示未观看标记"), isOn: $viewModel.showUnwatchedBadge)
            }
            .catGlassCard(cornerRadius: 20)
        }
    }
}

// MARK: - 元数据缓存子页

struct MetadataCacheSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("元数据缓存")) {
            VStack(spacing: 0) {
                CatSettingsToggleRow(title: L10n.tr("自动从媒体服务器下载元数据"), isOn: $viewModel.metadataAutoDownload)
                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)
                HStack {
                    Text(L10n.tr("元数据缓存大小"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text(viewModel.metadataCacheSize)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CatDesign.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
            }
            .catGlassCard(cornerRadius: 20)

            Button {
                viewModel.showClearMetadataCacheAlert = true
            } label: {
                Text(L10n.tr("删除所有元数据缓存"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.dangerRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .catGlassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)

            Text(L10n.tr("仅 Emby、Jellyfin、Plex 媒体条目支持元数据刷新。关闭自动下载后，仍可在详情页通过右上角刷新按钮手动更新。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
                .lineSpacing(3)
        }
        .task {
            await viewModel.calculateMetadataCacheSize()
        }
        .alert(L10n.tr("删除元数据缓存"), isPresented: $viewModel.showClearMetadataCacheAlert) {
            Button(L10n.tr("取消"), role: .cancel) {}
            Button(L10n.tr("删除"), role: .destructive) {
                Task { await viewModel.clearMetadataCache() }
            }
        } message: {
            Text(L10n.tr("确定要删除所有元数据缓存吗？已保存的媒体信息不会被删除，但 Logo、演职人员头像和单集封面等缓存图片将被移除。"))
        }
    }
}

// MARK: - 存储、下载与重置子页

struct StorageDownloadsSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var isChoosingDirectory = false
    @State private var directoryError: String?

    var body: some View {
        CatSettingsSubpageShell(title: L10n.tr("存储与下载")) {
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.downloads) {
                    HStack {
                        Image("CatDownloadFeline")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(L10n.tr("下载管理"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                        Spacer()
                        Text("\(downloadManager.tasks.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(CatDesign.accentAmber)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CatDesign.textDim)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                }
                .buttonStyle(.plain)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("下载目录"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Text(downloadManager.destination.rootPath)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                Button {
                    isChoosingDirectory = true
                } label: {
                    HStack {
                        Text(L10n.tr("选择下载文件夹"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(CatDesign.accentAmber)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                Button {
                    downloadManager.useDefaultDirectory()
                } label: {
                    HStack {
                        Text(L10n.tr("恢复默认下载位置"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(CatDesign.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
            .catGlassCard(cornerRadius: 20)

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.tr("缓存大小"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text(viewModel.cacheSize)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CatDesign.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                Button {
                    viewModel.showClearCacheAlert = true
                } label: {
                    HStack {
                        Text(L10n.tr("清除缓存"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.dangerRed)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
            .catGlassCard(cornerRadius: 20)

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.tr("版本"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text(viewModel.appVersion)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CatDesign.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)

                Rectangle().fill(CatDesign.hairSeparator).frame(height: 0.75)

                Button {
                    viewModel.showResetAlert = true
                } label: {
                    HStack {
                        Text(L10n.tr("重置所有设置"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.dangerRed)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
            .catGlassCard(cornerRadius: 20)
        }
        .task {
            await viewModel.calculateCacheSize()
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
        .alert(L10n.tr("无法修改下载目录"), isPresented: Binding(
            get: { directoryError != nil },
            set: { if !$0 { directoryError = nil } }
        )) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(directoryError ?? "")
        }
        .alert(L10n.tr("清除缓存"), isPresented: $viewModel.showClearCacheAlert) {
            Button(L10n.tr("取消"), role: .cancel) {}
            Button(L10n.tr("清除"), role: .destructive) {
                Task { await viewModel.clearCache() }
            }
        } message: {
            Text(L10n.tr("确定要清除所有缓存数据吗？这不会删除已下载的文件。"))
        }
        .alert(L10n.tr("重置设置"), isPresented: $viewModel.showResetAlert) {
            Button(L10n.tr("取消"), role: .cancel) {}
            Button(L10n.tr("重置"), role: .destructive) {
                viewModel.resetAllSettings()
            }
        } message: {
            Text(L10n.tr("确定要重置所有设置为默认值吗？"))
        }
    }
}
