import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            playbackSection
            subtitleSection
            librarySection
            appearanceSection
            storageSection
            aboutSection
        }
        .navigationTitle("设置")
        .task { await viewModel.calculateCacheSize() }
        .alert("清除缓存", isPresented: $viewModel.showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
        } message: {
            Text("确定要清除所有缓存数据吗？这不会删除已下载的文件。")
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
        } header: {
            Label("字幕", systemImage: "captions.bubble")
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

    private var appearanceSection: some View {
        Section {
            Picker("外观模式", selection: $viewModel.appearance) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } header: {
            Label("外观", systemImage: "paintbrush")
        }
    }

    private var storageSection: some View {
        Section {
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

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
