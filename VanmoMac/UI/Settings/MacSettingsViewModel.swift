import SwiftUI
import Combine
import VanmoCore

enum MacSubtitleStyleKeys {
    static let textColorKey = "subtitle.textColorHex"
    static let backgroundColorKey = "subtitle.backgroundColorHex"
    static let positionKey = "subtitle.position"
}

enum MacSubtitlePosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "顶部"
        case .bottom: "底部"
        }
    }
}

@MainActor
final class MacSettingsViewModel: ObservableObject {
    @AppStorage("playback.autoPlay") var autoPlayNext = true
    @AppStorage("playback.resumePlayback") var resumePlayback = true
    @AppStorage("playback.defaultRate") var defaultRate: Double = 1.0
    @AppStorage(PlaybackPreferences.hardwareDecodingKey) var hardwareDecoding = true
    @AppStorage(PlaybackPreferences.audioOutputModeKey) var audioOutputMode: AudioOutputMode = .auto

    @AppStorage("subtitle.autoLoad") var subtitleAutoLoad = true
    @AppStorage("subtitle.fontSize") var subtitleFontSize: Double = 18
    @AppStorage("subtitle.preferredLanguage") var subtitlePreferredLanguage = "zh"
    @AppStorage(OpenSubtitlesCredentialStore.enabledKey) var openSubtitlesEnabled = false
    @AppStorage(MacSubtitleStyleKeys.textColorKey) var subtitleTextColorHex = "#FFFFFFFF"
    @AppStorage(MacSubtitleStyleKeys.backgroundColorKey) var subtitleBackgroundColorHex = "#00000099"
    @AppStorage(MacSubtitleStyleKeys.positionKey) var subtitlePositionRaw = MacSubtitlePosition.bottom.rawValue

    @AppStorage("library.autoScan") var libraryAutoScan = true
    @AppStorage("metadata.autoDownload") var metadataAutoDownload = true
    @AppStorage(MacAppearanceMode.storageKey) var appearanceMode: MacAppearanceMode = .system

    @AppStorage(CloudSyncPreferences.enabledKey) var cloudSyncEnabled = true
    @Published var cloudSyncStatusMessage: String?

    @Published var cacheSize: String = "计算中..."
    @Published var metadataCacheSize: String = "计算中..."
    @Published var showClearCacheAlert = false
    @Published var showClearMetadataCacheAlert = false
    @Published var showResetAlert = false

    var subtitleTextColor: Color {
        get { Color(rgbaHex: subtitleTextColorHex) ?? .white }
        set { subtitleTextColorHex = newValue.rgbaHex }
    }

    var subtitleBackgroundColor: Color {
        get { Color(rgbaHex: subtitleBackgroundColorHex) ?? Color.black.opacity(0.6) }
        set { subtitleBackgroundColorHex = newValue.rgbaHex }
    }

    var subtitlePosition: MacSubtitlePosition {
        get { MacSubtitlePosition(rawValue: subtitlePositionRaw) ?? .bottom }
        set { subtitlePositionRaw = newValue.rawValue }
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var cloudSyncLastUpdatedText: String {
        guard let lastSyncAt = CloudSyncPreferences.lastSyncAt else {
            return "尚未同步"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    func bindCloudSyncCoordinator(_ coordinator: CloudSyncCoordinator) {
        cloudSyncStatusMessage = coordinator.statusMessage
    }

    func updateCloudSyncEnabled(_ enabled: Bool, coordinator: CloudSyncCoordinator) {
        guard CloudSyncAvailability.isCloudKitEnabled else { return }
        cloudSyncEnabled = enabled
        coordinator.setEnabled(enabled)
        cloudSyncStatusMessage = coordinator.statusMessage
    }

    func calculateCacheSize() async {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cachePath else {
            cacheSize = "未知"
            return
        }

        let totalSize = await Task.detached(priority: .utility) {
            Self.directorySize(at: cachePath)
        }.value

        cacheSize = totalSize.map(\.formattedFileSize) ?? "未知"
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

        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: cachePath)
            try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
        }.value

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
        openSubtitlesEnabled = false
        subtitleTextColorHex = "#FFFFFFFF"
        subtitleBackgroundColorHex = "#00000099"
        subtitlePositionRaw = MacSubtitlePosition.bottom.rawValue
        libraryAutoScan = true
        metadataAutoDownload = true
        appearanceMode = .system
        cloudSyncEnabled = true
        CloudSyncPreferences.isEnabled = true
    }

    private nonisolated static func directorySize(at url: URL) -> Int64? {
        let resourceKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: resourceKeys),
                  attrs.isRegularFile == true else { continue }
            totalSize += Int64(attrs.totalFileAllocatedSize ?? 0)
        }
        return totalSize
    }
}
