import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("playback.autoPlay") var autoPlayNext = true
    @AppStorage("playback.resumePlayback") var resumePlayback = true
    @AppStorage("playback.defaultRate") var defaultRate: Double = 1.0
    @AppStorage(PlaybackPreferences.hardwareDecodingKey) var hardwareDecoding = true
    @AppStorage(PlaybackPreferences.audioOutputModeKey) var audioOutputMode: AudioOutputMode = .auto

    @AppStorage("subtitle.autoLoad") var subtitleAutoLoad = true
    @AppStorage("subtitle.fontSize") var subtitleFontSize: Double = 18
    @AppStorage("subtitle.preferredLanguage") var subtitlePreferredLanguage = "zh"
    @AppStorage(SubtitleStylePreferences.textColorKey) var subtitleTextColorHex = "#FFFFFFFF"
    @AppStorage(SubtitleStylePreferences.backgroundColorKey) var subtitleBackgroundColorHex = "#00000099"
    @AppStorage(SubtitleStylePreferences.positionKey) var subtitlePositionRaw = SubtitleStyle.SubtitlePosition.bottom.rawValue

    var subtitleTextColor: Color {
        get { Color(rgbaHex: subtitleTextColorHex) ?? .white }
        set { subtitleTextColorHex = newValue.rgbaHex }
    }

    var subtitleBackgroundColor: Color {
        get { Color(rgbaHex: subtitleBackgroundColorHex) ?? Color.black.opacity(0.6) }
        set { subtitleBackgroundColorHex = newValue.rgbaHex }
    }

    @AppStorage("library.autoScan") var libraryAutoScan = true
    @AppStorage("library.showUnwatched") var showUnwatchedBadge = true
    @AppStorage("metadata.autoDownload") var metadataAutoDownload = true

    @AppStorage(ColorTheme.storageKey) var theme: ColorTheme = .system

    @Published var cacheSize: String = "计算中..."
    @Published var metadataCacheSize: String = "计算中..."
    @Published var showClearCacheAlert = false
    @Published var showClearMetadataCacheAlert = false
    @Published var showResetAlert = false

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    func calculateCacheSize() async {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cachePath else {
            cacheSize = "未知"
            return
        }

        let resourceKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: cachePath,
            includingPropertiesForKeys: Array(resourceKeys),
            options: .skipsHiddenFiles
        ) else {
            cacheSize = "未知"
            return
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: resourceKeys),
                  attrs.isRegularFile == true else { continue }
            totalSize += Int64(attrs.totalFileAllocatedSize ?? 0)
        }

        cacheSize = totalSize.formattedFileSize
    }

    func calculateMetadataCacheSize() async {
        let size = (try? await MetadataCache.shared.diskSize()) ?? 0
        metadataCacheSize = size.formattedFileSize
    }

    func clearMetadataCache() async {
        try? await MetadataCache.shared.deleteAll()
        await calculateMetadataCacheSize()
    }

    func clearCache() async {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cachePath else { return }

        try? FileManager.default.removeItem(at: cachePath)
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)

        await calculateCacheSize()
    }

    func resetAllSettings() {
        autoPlayNext = true
        resumePlayback = true
        defaultRate = 1.0
        hardwareDecoding = true
        audioOutputMode = .auto
        subtitleAutoLoad = true
        subtitleFontSize = 18
        subtitlePreferredLanguage = "zh"
        subtitleTextColorHex = "#FFFFFFFF"
        subtitleBackgroundColorHex = "#00000099"
        subtitlePositionRaw = SubtitleStyle.SubtitlePosition.bottom.rawValue
        libraryAutoScan = true
        showUnwatchedBadge = true
        metadataAutoDownload = true
        theme = .system
    }
}
