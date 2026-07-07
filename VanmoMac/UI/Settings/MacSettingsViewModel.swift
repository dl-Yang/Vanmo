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

    @AppStorage(CloudSyncPreferences.enabledKey) var cloudSyncEnabled = true
    @Published var cloudSyncStatusMessage: String?

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
}
